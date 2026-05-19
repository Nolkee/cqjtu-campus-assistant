import 'dart:async';
import 'dart:convert';

import 'package:campus_adapters_mock/campus_adapters_mock.dart';
import 'package:campus_app/config/app_config.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/dorm_service.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/session_service.dart';
import 'package:core/models/course.dart';
import 'package:core/models/dorm_room.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/utils/polling_utils.dart';
import 'package:data/data.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/semester_service.dart';

enum SystemDomain { schedule, oneCard, leave }

extension SystemDomainX on SystemDomain {
  String get key => switch (this) {
    SystemDomain.schedule => 'schedule',
    SystemDomain.oneCard => 'one_card',
    SystemDomain.leave => 'leave',
  };

  String get displayName => switch (this) {
    SystemDomain.schedule => '课表',
    SystemDomain.oneCard => '校园卡/电费',
    SystemDomain.leave => '请假',
  };

  Duration get freshness => switch (this) {
    SystemDomain.schedule => const Duration(hours: 2),
    SystemDomain.oneCard => const Duration(minutes: 45),
    SystemDomain.leave => const Duration(minutes: 30),
  };
}

enum RecoveryState { healthy, refreshing, degraded, manualRequired }

enum RecoveryFailureKind {
  none,
  sessionExpired,
  securityVerificationRequired,
  authInvalid,
  transientNetwork,
  unknown,
}

class RecoverySnapshot {
  const RecoverySnapshot({
    required this.domain,
    required this.state,
    required this.failureKind,
    required this.message,
    required this.retryCount,
    required this.updatedAt,
    required this.latencyMs,
  });

  factory RecoverySnapshot.initial(SystemDomain domain) => RecoverySnapshot(
    domain: domain,
    state: RecoveryState.healthy,
    failureKind: RecoveryFailureKind.none,
    message: '',
    retryCount: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    latencyMs: 0,
  );

  final SystemDomain domain;
  final RecoveryState state;
  final RecoveryFailureKind failureKind;
  final String message;
  final int retryCount;
  final DateTime updatedAt;
  final int latencyMs;

  Map<String, dynamic> toJson() => {
    'domain': domain.name,
    'state': state.name,
    'failureKind': failureKind.name,
    'message': message,
    'retryCount': retryCount,
    'updatedAtMs': updatedAt.millisecondsSinceEpoch,
    'latencyMs': latencyMs,
  };

  static RecoverySnapshot? fromJson(
    Map<String, dynamic> json,
    SystemDomain expectedDomain,
  ) {
    final stateName = json['state']?.toString();
    final failureName = json['failureKind']?.toString();
    final state = RecoveryState.values.where((v) => v.name == stateName);
    final failure = RecoveryFailureKind.values.where(
      (v) => v.name == failureName,
    );
    if (state.isEmpty || failure.isEmpty) return null;
    final updatedAtMs =
        int.tryParse(json['updatedAtMs']?.toString() ?? '') ?? 0;
    final retryCount = int.tryParse(json['retryCount']?.toString() ?? '') ?? 0;
    final latencyMs = int.tryParse(json['latencyMs']?.toString() ?? '') ?? 0;

    return RecoverySnapshot(
      domain: expectedDomain,
      state: state.first,
      failureKind: failure.first,
      message: json['message']?.toString() ?? '',
      retryCount: retryCount,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      latencyMs: latencyMs,
    );
  }
}

class ManualVerificationRequiredException implements Exception {
  const ManualVerificationRequiredException({
    required this.domain,
    required this.message,
    this.cause,
  });

  final SystemDomain domain;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class RecoveryHealthNotifier
    extends Notifier<Map<SystemDomain, RecoverySnapshot>> {
  @override
  Map<SystemDomain, RecoverySnapshot> build() => {
    SystemDomain.schedule: RecoverySnapshot.initial(SystemDomain.schedule),
    SystemDomain.oneCard: RecoverySnapshot.initial(SystemDomain.oneCard),
    SystemDomain.leave: RecoverySnapshot.initial(SystemDomain.leave),
  };

  void setSnapshot(RecoverySnapshot snapshot) {
    state = {...state, snapshot.domain: snapshot};
  }
}

final recoveryHealthProvider =
    NotifierProvider<
      RecoveryHealthNotifier,
      Map<SystemDomain, RecoverySnapshot>
    >(RecoveryHealthNotifier.new);

final systemHealthProvider = Provider.family<RecoverySnapshot, SystemDomain>((
  ref,
  domain,
) {
  final state = ref.watch(recoveryHealthProvider);
  return state[domain] ?? RecoverySnapshot.initial(domain);
});

final lastRecoverySnapshotProvider =
    FutureProvider.family<RecoverySnapshot?, SystemDomain>((ref, domain) async {
      return SessionManager.loadLastRecoverySnapshot(domain);
    });

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(baseUrl: AppConfig.baseUrl);
});

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final api = ref.read(apiServiceProvider);
  final sessionService = ref.read(sessionServiceProvider);
  final recoveryHealth = ref.read(recoveryHealthProvider.notifier);
  return SessionManager(api, sessionService, recoveryHealth);
});

class SessionManager {
  SessionManager(this._api, this._sessionService, this._recoveryHealth);

  final ApiService _api;
  final SessionService _sessionService;
  final RecoveryHealthNotifier _recoveryHealth;
  final Map<String, String> _sessionIdCache = {};
  final Map<String, Future<void>> _inflightRecoveryTasks = {};
  final Map<String, int> _recoveryFailureCount = {};
  final Map<String, int> _recoveryBlockedUntilMs = {};
  final Map<String, int> _lastHealthyAtMs = {};

  static const _snapshotPrefsPrefix = 'session_recovery_snapshot_v1_';
  static const _maxBackoff = Duration(minutes: 10);

  static const _casDomain = 'ids.cqjtu.edu.cn';
  static const _jwgDomain = 'jwgln.cqjtu.edu.cn';
  static const _ecardDomain = 'ecard.cqjtu.edu.cn';

  static Future<RecoverySnapshot?> loadLastRecoverySnapshot(
    SystemDomain domain,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_snapshotPrefsPrefix${domain.key}');
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final mapped = json.map((key, value) => MapEntry(key.toString(), value));
      return RecoverySnapshot.fromJson(mapped, domain);
    } catch (_) {
      return null;
    }
  }

  Future<String> ensureSessionId(String username) async {
    final cached = _sessionIdCache[username];
    if (cached != null && cached.isNotEmpty) return cached;
    final persisted = await _sessionService.loadSessionId(username);
    if (persisted != null && persisted.isNotEmpty) {
      _sessionIdCache[username] = persisted;
      return persisted;
    }
    return refreshSessionId(username);
  }

  Future<String> refreshSessionId(String username) async {
    final sessionId = await _api.createSession(username);
    _sessionIdCache[username] = sessionId;
    await _sessionService.saveSessionId(username, sessionId);
    return sessionId;
  }

  Future<void> saveWebLoginArtifacts(
    String username, {
    String? ticket,
    String? casCookies,
    String? jwgCookies,
    String? ecardCookies,
    String? zoveToken,
  }) async {
    if (ticket != null && ticket.isNotEmpty) {
      await _sessionService.saveTicket(username, ticket);
    }
    if (casCookies != null && casCookies.isNotEmpty) {
      await _sessionService.saveCasCookies(username, casCookies);
    }
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      await _sessionService.saveJwgCookies(username, jwgCookies);
    }
    if (ecardCookies != null && ecardCookies.isNotEmpty) {
      await _sessionService.saveEcardCookies(username, ecardCookies);
    }
    if (zoveToken != null && zoveToken.isNotEmpty) {
      await _sessionService.saveZoveToken(username, zoveToken);
    }
  }

  Future<void> restoreLoginState(String username, String sessionId) async {
    final ticket = await _sessionService.loadTicket(username);
    if (ticket != null && ticket.isNotEmpty) {
      debugPrint(
        '[SessionManager] restoreLoginState use ticket username=$username',
      );
      await _api.loginWithTicket(username, ticket, sessionId: sessionId);
    }

    final casCookies = await _sessionService.loadCasCookies(username);
    if (casCookies != null && casCookies.isNotEmpty) {
      debugPrint(
        '[SessionManager] restoreLoginState inject CAS cookies username=$username',
      );
      await _api.injectCookies(
        username,
        _casDomain,
        casCookies,
        sessionId: sessionId,
      );
    }

    final jwgCookies = await _sessionService.loadJwgCookies(username);
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      debugPrint(
        '[SessionManager] restoreLoginState inject JWG cookies username=$username',
      );
      await _api.injectCookies(
        username,
        _jwgDomain,
        jwgCookies,
        sessionId: sessionId,
      );
    }

    final ecardCookies = await _sessionService.loadEcardCookies(username);
    if (ecardCookies != null && ecardCookies.isNotEmpty) {
      debugPrint(
        '[SessionManager] restoreLoginState inject ECARD cookies username=$username',
      );
      await _api.injectCookies(
        username,
        _ecardDomain,
        ecardCookies,
        sessionId: sessionId,
      );
    }
  }

  bool isSessionExpiredError(Object error) {
    if (error is! ApiException) return false;
    return error.code == 403 &&
        error.message.toLowerCase().contains('sessionid');
  }

  bool isManualVerificationRequired(Object error, {SystemDomain? domain}) {
    if (error is! ManualVerificationRequiredException) return false;
    return domain == null || error.domain == domain;
  }

  bool isSecurityVerificationError(Object error) {
    final kind = _classifyFailure(error);
    return kind == RecoveryFailureKind.securityVerificationRequired;
  }

  bool isTransientNetworkError(Object error) {
    final kind = _classifyFailure(error);
    return kind == RecoveryFailureKind.transientNetwork;
  }

  Future<void> ensureDomainReady({
    required SystemDomain domain,
    required String username,
    Future<void> Function(String sessionId)? silentRefresh,
    bool force = false,
  }) async {
    await _maybeRecoverForFreshness(
      domain: domain,
      username: username,
      silentRefresh: silentRefresh,
      force: force,
    );
  }

  Future<void> verifyScheduleReady(
    String username,
    String password, {
    String? semester,
  }) async {
    await runWithRecovery(
      domain: SystemDomain.schedule,
      username: username,
      forceRefresh: true,
      request: (sessionId) => _api.getSchedule(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: true,
      ),
    );
  }

  Future<T> runWithRecovery<T>({
    required SystemDomain domain,
    required String username,
    required Future<T> Function(String sessionId) request,
    Future<T> Function(String sessionId)? retryRequest,
    Future<void> Function(String sessionId)? silentRefresh,
    bool Function(Object error)? shouldRecoverOnError,
    bool forceRefresh = false,
  }) async {
    final retry = retryRequest ?? request;
    final stopwatch = Stopwatch()..start();

    await _maybeRecoverForFreshness(
      domain: domain,
      username: username,
      silentRefresh: silentRefresh,
      force: forceRefresh,
    );

    var sessionId = await ensureSessionId(username);
    try {
      final result = await request(sessionId);
      await _markHealthy(
        domain: domain,
        username: username,
        message: 'request_ok',
        retryCount: 0,
        latency: stopwatch.elapsed,
      );
      return result;
    } catch (error) {
      final kind = _classifyFailure(error);
      final recoverable =
          _isRecoverable(kind) || (shouldRecoverOnError?.call(error) ?? false);
      if (!recoverable) {
        await _markFailure(
          domain: domain,
          username: username,
          failureKind: kind,
          message: error.toString(),
          retryCount: 0,
          latency: stopwatch.elapsed,
        );
        rethrow;
      }

      await _recoverDomain(
        domain: domain,
        username: username,
        silentRefresh: silentRefresh,
        initialFailureKind: kind,
        cause: error,
      );

      sessionId = await ensureSessionId(username);
      try {
        final result = await retry(sessionId);
        await _markHealthy(
          domain: domain,
          username: username,
          message: 'recovered_once',
          retryCount: 1,
          latency: stopwatch.elapsed,
        );
        return result;
      } catch (retryError) {
        final retryKind = _classifyFailure(retryError);
        await _markFailure(
          domain: domain,
          username: username,
          failureKind: retryKind,
          message: retryError.toString(),
          retryCount: 1,
          latency: stopwatch.elapsed,
        );
        if (_requiresManualVerification(retryKind)) {
          throw ManualVerificationRequiredException(
            domain: domain,
            message: '${domain.displayName}恢复失败，需要重新验证登录状态。',
            cause: retryError,
          );
        }
        rethrow;
      }
    }
  }

  Future<T> runWithSessionRetry<T>({
    required String username,
    required Future<T> Function(String sessionId) request,
  }) async {
    return runWithRecovery(
      domain: SystemDomain.schedule,
      username: username,
      request: request,
    );
  }

  Future<void> _maybeRecoverForFreshness({
    required SystemDomain domain,
    required String username,
    Future<void> Function(String sessionId)? silentRefresh,
    required bool force,
  }) async {
    final key = _domainUserKey(domain, username);
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastHealthy = _lastHealthyAtMs[key] ?? 0;
    final age = now - lastHealthy;
    if (!force && lastHealthy != 0 && age < domain.freshness.inMilliseconds) {
      return;
    }

    await _recoverDomain(
      domain: domain,
      username: username,
      silentRefresh: silentRefresh,
      initialFailureKind: RecoveryFailureKind.sessionExpired,
      cause: null,
    );
  }

  Future<void> _recoverDomain({
    required SystemDomain domain,
    required String username,
    Future<void> Function(String sessionId)? silentRefresh,
    required RecoveryFailureKind initialFailureKind,
    required Object? cause,
  }) async {
    final key = _domainUserKey(domain, username);
    final existing = _inflightRecoveryTasks[key];
    if (existing != null) return existing;

    late final Future<void> task;
    task =
        (() async {
          try {
            if (_isBackoffActive(key)) {
              throw ManualVerificationRequiredException(
                domain: domain,
                message: '${domain.displayName}连续恢复失败，已暂时停止自动重试。',
                cause: cause,
              );
            }

            await _reportSnapshot(
              RecoverySnapshot(
                domain: domain,
                state: RecoveryState.refreshing,
                failureKind: initialFailureKind,
                message: 'silent_recovering',
                retryCount: 0,
                updatedAt: DateTime.now(),
                latencyMs: 0,
              ),
            );

            final sessionId = await refreshSessionId(username);
            await restoreLoginState(username, sessionId);
            if (silentRefresh != null) {
              await silentRefresh(sessionId);
            }

            _noteRecoverySuccess(key);
            await _markHealthy(
              domain: domain,
              username: username,
              message: 'silent_recovery_ok',
              retryCount: 0,
              latency: Duration.zero,
            );
          } catch (error) {
            _noteRecoveryFailure(key);
            final failureKind = _classifyFailure(error);
            await _markFailure(
              domain: domain,
              username: username,
              failureKind: failureKind,
              message: error.toString(),
              retryCount: 0,
              latency: Duration.zero,
            );
            if (_requiresManualVerification(failureKind) ||
                _requiresManualVerification(initialFailureKind)) {
              throw ManualVerificationRequiredException(
                domain: domain,
                message: '${domain.displayName}静默恢复失败，需要重新验证登录状态。',
                cause: error,
              );
            }
            rethrow;
          }
        })().whenComplete(() {
          if (identical(_inflightRecoveryTasks[key], task)) {
            _inflightRecoveryTasks.remove(key);
          }
        });

    _inflightRecoveryTasks[key] = task;
    await task;
  }

  RecoveryFailureKind _classifyFailure(Object error) {
    if (error is ManualVerificationRequiredException) {
      return RecoveryFailureKind.securityVerificationRequired;
    }
    if (error is CaptchaRequiredException) {
      return RecoveryFailureKind.securityVerificationRequired;
    }
    if (error is ApiException) {
      final msg = error.message.toLowerCase();
      if (error.code == 403 && msg.contains('sessionid')) {
        return RecoveryFailureKind.sessionExpired;
      }
      if (error.code == 449 ||
          msg.contains('captcha') ||
          msg.contains('verify') ||
          msg.contains('verification') ||
          msg.contains('cas') ||
          msg.contains('authserver/login') ||
          msg.contains('html') ||
          msg.contains('security')) {
        return RecoveryFailureKind.securityVerificationRequired;
      }
      if (error.code == 401) {
        return RecoveryFailureKind.authInvalid;
      }
      if (error.code >= 500 || error.code <= 0) {
        return RecoveryFailureKind.transientNetwork;
      }
      return RecoveryFailureKind.unknown;
    }
    if (error is TimeoutException) {
      return RecoveryFailureKind.transientNetwork;
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown) {
        return RecoveryFailureKind.transientNetwork;
      }
    }
    final message = error.toString().toLowerCase();
    if (message.contains('socket') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('connection')) {
      return RecoveryFailureKind.transientNetwork;
    }
    return RecoveryFailureKind.unknown;
  }

  bool _isRecoverable(RecoveryFailureKind kind) {
    return kind == RecoveryFailureKind.sessionExpired ||
        kind == RecoveryFailureKind.securityVerificationRequired ||
        kind == RecoveryFailureKind.authInvalid ||
        kind == RecoveryFailureKind.transientNetwork;
  }

  bool _requiresManualVerification(RecoveryFailureKind kind) {
    return kind == RecoveryFailureKind.securityVerificationRequired ||
        kind == RecoveryFailureKind.authInvalid;
  }

  bool _isBackoffActive(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = _recoveryBlockedUntilMs[key] ?? 0;
    return until > now;
  }

  void _noteRecoveryFailure(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = (_recoveryFailureCount[key] ?? 0) + 1;
    _recoveryFailureCount[key] = count;
    final seconds = (30 * (1 << (count - 1))).clamp(30, _maxBackoff.inSeconds);
    _recoveryBlockedUntilMs[key] = now + seconds * 1000;
  }

  void _noteRecoverySuccess(String key) {
    _recoveryFailureCount.remove(key);
    _recoveryBlockedUntilMs.remove(key);
  }

  String _domainUserKey(SystemDomain domain, String username) =>
      '${domain.key}@$username';

  Future<void> _markHealthy({
    required SystemDomain domain,
    required String username,
    required String message,
    required int retryCount,
    required Duration latency,
  }) async {
    _lastHealthyAtMs[_domainUserKey(domain, username)] =
        DateTime.now().millisecondsSinceEpoch;
    await _reportSnapshot(
      RecoverySnapshot(
        domain: domain,
        state: RecoveryState.healthy,
        failureKind: RecoveryFailureKind.none,
        message: message,
        retryCount: retryCount,
        updatedAt: DateTime.now(),
        latencyMs: latency.inMilliseconds,
      ),
    );
  }

  Future<void> _markFailure({
    required SystemDomain domain,
    required String username,
    required RecoveryFailureKind failureKind,
    required String message,
    required int retryCount,
    required Duration latency,
  }) async {
    final state = _requiresManualVerification(failureKind)
        ? RecoveryState.manualRequired
        : RecoveryState.degraded;
    await _reportSnapshot(
      RecoverySnapshot(
        domain: domain,
        state: state,
        failureKind: failureKind,
        message: message,
        retryCount: retryCount,
        updatedAt: DateTime.now(),
        latencyMs: latency.inMilliseconds,
      ),
    );
  }

  Future<void> _reportSnapshot(RecoverySnapshot snapshot) async {
    unawaited(
      Future<void>(() {
        _recoveryHealth.setSnapshot(snapshot);
      }),
    );
    final prefs = await SharedPreferences.getInstance();
    final key = '$_snapshotPrefsPrefix${snapshot.domain.key}';
    await prefs.setString(key, jsonEncode(snapshot.toJson()));
  }
}

final campusBackendProvider = Provider<CampusBackend>((ref) {
  if (AppConfig.env == 'mock') {
    return MockCampusBackend();
  }
  final api = ref.read(apiServiceProvider);
  final sessionManager = ref.read(sessionManagerProvider);
  return _ApiCampusBackend(api, sessionManager);
});

class _ApiCampusBackend implements CampusBackend {
  _ApiCampusBackend(this._api, this._sessionManager);

  final ApiService _api;
  final SessionManager _sessionManager;

  bool _isOneCardAuthFailure(Object error) {
    if (error is! ApiException) return false;
    if (error.code == 401) return true;
    if (error.code == 403 &&
        error.message.toLowerCase().contains('sessionid')) {
      return true;
    }
    if (error.code != 500) return false;
    final msg = error.message.toLowerCase();
    return msg.contains('auth') ||
        msg.contains('login') ||
        msg.contains('token') ||
        msg.contains('ecard') ||
        msg.contains('electric');
  }

  Future<T> _runOneCardRequest<T>({
    required String username,
    required bool forceRefresh,
    required Future<T> Function(String sessionId, bool forceRefresh) request,
  }) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.oneCard,
      username: username,
      forceRefresh: forceRefresh,
      request: (sessionId) => request(sessionId, forceRefresh),
      retryRequest: (sessionId) => request(sessionId, true),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.schedule,
      username: username,
      forceRefresh: forceRefresh,
      request: (sessionId) => _api.getSchedule(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.schedule,
      username: username,
      forceRefresh: forceRefresh,
      request: (sessionId) => _api.getGrades(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.schedule,
      username: username,
      forceRefresh: forceRefresh,
      request: (sessionId) => _api.getExams(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) {
    return _runOneCardRequest(
      username: username,
      forceRefresh: forceRefresh,
      request: (sessionId, shouldForceRefresh) => _api.getElecBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: shouldForceRefresh,
        dormParams: dormParams,
      ),
    );
  }

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) {
    return _runOneCardRequest(
      username: username,
      forceRefresh: forceRefresh,
      request: (sessionId, shouldForceRefresh) => _api.getCampusCardBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: shouldForceRefresh,
      ),
    );
  }

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    Map<String, String>? dormParams,
  }) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.oneCard,
      username: username,
      request: (sessionId) => _api.rechargeElec(
        username,
        amount,
        sessionId: sessionId,
        dormParams: dormParams,
      ),
      retryRequest: (sessionId) => _api.rechargeElec(
        username,
        amount,
        sessionId: sessionId,
        dormParams: dormParams,
      ),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<String> getPayCodeToken(String username) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.oneCard,
      username: username,
      request: (sessionId) =>
          _api.getPayCodeToken(username, sessionId: sessionId),
      retryRequest: (sessionId) =>
          _api.getPayCodeToken(username, sessionId: sessionId),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<String> getCampusCardAlipayUrl(String username, double amount) {
    return _sessionManager.runWithRecovery(
      domain: SystemDomain.oneCard,
      username: username,
      request: (sessionId) =>
          _api.getCampusCardAlipayUrl(username, amount, sessionId: sessionId),
      retryRequest: (sessionId) =>
          _api.getCampusCardAlipayUrl(username, amount, sessionId: sessionId),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }
}

class CredentialsNotifier
    extends Notifier<({String username, String password})?> {
  @override
  ({String username, String password})? build() => null;

  Future<void> load(CredentialService svc) async {
    state = await svc.load();
  }

  void set(String username, String password) {
    state = (username: username, password: password);
  }

  void clear() => state = null;
}

final credentialsProvider =
    NotifierProvider<
      CredentialsNotifier,
      ({String username, String password})?
    >(CredentialsNotifier.new);

void _ensureCredentialPassword(({String username, String password}) creds) {
  if (creds.password.trim().isEmpty) {
    debugPrint(
      '[Providers] empty password detected for username=${creds.username}',
    );
    throw Exception('Credential password is empty, please login again');
  }
}

class NoDormSetException implements Exception {
  @override
  String toString() => '璇峰厛璁剧疆瀹胯垗';
}

class DormRoomNotifier extends AsyncNotifier<DormRoom?> {
  @override
  Future<DormRoom?> build() async {
    return ref.read(dormServiceProvider).load();
  }

  Future<void> set(DormRoom room) async {
    await ref.read(dormServiceProvider).save(room);
    state = AsyncData(room);
  }

  Future<void> clear() async {
    await ref.read(dormServiceProvider).clear();
    state = const AsyncData(null);
  }
}

final dormRoomProvider = AsyncNotifierProvider<DormRoomNotifier, DormRoom?>(
  DormRoomNotifier.new,
);

class SemesterStartNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    return ref.read(semesterServiceProvider).load();
  }

  Future<void> set(DateTime date) async {
    await ref.read(semesterServiceProvider).save(date);
    state = AsyncData(date);
  }
}

final semesterStartProvider =
    AsyncNotifierProvider<SemesterStartNotifier, DateTime?>(
      SemesterStartNotifier.new,
    );

class SemesterStartForKeyNotifier
    extends FamilyAsyncNotifier<DateTime?, String> {
  @override
  Future<DateTime?> build(String arg) async {
    return ref.read(semesterServiceProvider).loadForKey(arg);
  }

  Future<void> set(DateTime date) async {
    await ref.read(semesterServiceProvider).saveForKey(arg, date);
    state = AsyncData(date);
  }
}

final semesterStartForKeyProvider =
    AsyncNotifierProvider.family<
      SemesterStartForKeyNotifier,
      DateTime?,
      String
    >(SemesterStartForKeyNotifier.new);

class SelectedSemesterNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    return ref.read(semesterServiceProvider).loadSelectedSemester();
  }

  Future<void> set(String? value) async {
    state = AsyncData(value);
    await ref.read(semesterServiceProvider).saveSelectedSemester(value);
  }
}

final selectedScheduleSemesterProvider =
    AsyncNotifierProvider<SelectedSemesterNotifier, String?>(
      SelectedSemesterNotifier.new,
    );

final activeSemesterStartProvider = Provider<AsyncValue<DateTime?>>((ref) {
  final selectedAsync = ref.watch(selectedScheduleSemesterProvider);
  if (selectedAsync.isLoading) return const AsyncValue.loading();
  if (selectedAsync.hasError) {
    return AsyncValue.error(selectedAsync.error!, selectedAsync.stackTrace!);
  }

  final selected = selectedAsync.valueOrNull;
  if (selected == null) return ref.watch(semesterStartProvider);
  return ref.watch(semesterStartForKeyProvider(selected));
});

class SelectedWeekNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void setWeek(int week) => state = week;
}

final selectedWeekProvider = NotifierProvider<SelectedWeekNotifier, int>(
  SelectedWeekNotifier.new,
);

const _scheduleSundayFirstKey = 'schedule_sunday_first';

class ScheduleSundayFirstNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scheduleSundayFirstKey) ?? false;
  }

  Future<void> setSundayFirst(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scheduleSundayFirstKey, value);
  }
}

final scheduleSundayFirstProvider =
    AsyncNotifierProvider<ScheduleSundayFirstNotifier, bool>(
      ScheduleSundayFirstNotifier.new,
    );

typedef ScheduleResult = ({List<Course> courses, String remark});

final scheduleProvider = FutureProvider.family<ScheduleResult, String?>((
  ref,
  semester,
) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  _ensureCredentialPassword(creds);

  final backend = ref.watch(campusBackendProvider);
  return backend.getSchedule(
    creds.username,
    creds.password,
    semester: semester,
  );
});

final electricityProvider = FutureProvider<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final interval = pollingInterval();
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  _ensureCredentialPassword(creds);

  final backend = ref.watch(campusBackendProvider);
  final dormAsync = ref.watch(dormRoomProvider);
  final dorm = await dormAsync.when(
    loading: () => ref.read(dormRoomProvider.future),
    error: (e, _) => Future<DormRoom?>.error(e),
    data: (d) => Future.value(d),
  );

  if (dorm == null) throw NoDormSetException();

  debugPrint('[FG] 鏌ヨ鐢佃垂: ${dorm.displayName}');
  debugPrint(
    '[FG] getElecBalance request username=${creds.username} passwordLen=${creds.password.length}',
  );
  final balance = await backend.getElecBalance(
    creds.username,
    creds.password,
    dormParams: dorm.toQueryParams(),
  );
  debugPrint('[FG] 鐢佃垂浣欓鑾峰彇鎴愬姛: $balance');
  NotificationService.checkAndNotify(balance);
  return balance;
});

final campusCardBalanceProvider = FutureProvider<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final interval = pollingInterval();
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  _ensureCredentialPassword(creds);

  final backend = ref.watch(campusBackendProvider);
  debugPrint(
    '[FG] getCampusCardBalance request username=${creds.username} passwordLen=${creds.password.length}',
  );
  final balance = await backend.getCampusCardBalance(
    creds.username,
    creds.password,
  );
  return balance;
});

final payCodeProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  _ensureCredentialPassword(creds);

  final backend = ref.watch(campusBackendProvider);
  debugPrint(
    '[FG] getPayCodeToken request username=${creds.username} passwordLen=${creds.password.length}',
  );
  return backend.getPayCodeToken(creds.username);
});

typedef GradeResult = ({Map<String, String> summary, List<Grade> grades});

final gradesProvider = FutureProvider.autoDispose.family<GradeResult, String>((
  ref,
  semester,
) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  _ensureCredentialPassword(creds);

  final backend = ref.watch(campusBackendProvider);
  return backend.getGrades(creds.username, creds.password, semester: semester);
});

final examsProvider = FutureProvider.autoDispose.family<List<Exam>, String?>((
  ref,
  semester,
) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  _ensureCredentialPassword(creds);

  final backend = ref.watch(campusBackendProvider);
  return backend.getExams(creds.username, creds.password, semester: semester);
});

class SessionUpdateNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void triggerRefresh() => state++;
}

final sessionUpdateProvider = NotifierProvider<SessionUpdateNotifier, int>(
  SessionUpdateNotifier.new,
);
