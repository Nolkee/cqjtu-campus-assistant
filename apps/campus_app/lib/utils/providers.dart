import 'dart:async';

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
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/semester_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(baseUrl: AppConfig.baseUrl);
});

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final api = ref.read(apiServiceProvider);
  final sessionService = ref.read(sessionServiceProvider);
  return SessionManager(api, sessionService);
});

class SessionManager {
  SessionManager(this._api, this._sessionService);

  final ApiService _api;
  final SessionService _sessionService;
  final Map<String, String> _sessionIdCache = {};

  static const _casDomain = 'ids.cqjtu.edu.cn';
  static const _jwgDomain = 'jwgln.cqjtu.edu.cn';
  static const _ecardDomain = 'ecard.cqjtu.edu.cn';

  Future<String> ensureSessionId(String username) async {
    final cached = _sessionIdCache[username];
    if (cached != null && cached.isNotEmpty) return cached;
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

  Future<T> runWithSessionRetry<T>({
    required String username,
    required Future<T> Function(String sessionId) request,
  }) async {
    var sessionId = await ensureSessionId(username);
    debugPrint(
      '[SessionManager] request start username=$username sessionId=$sessionId',
    );
    try {
      return await request(sessionId);
    } catch (error) {
      if (!isSessionExpiredError(error)) rethrow;
      debugPrint(
        '[SessionManager] session expired username=$username oldSessionId=$sessionId, refreshing',
      );
      sessionId = await refreshSessionId(username);
      await restoreLoginState(username, sessionId);
      debugPrint(
        '[SessionManager] retry request username=$username newSessionId=$sessionId',
      );
      return request(sessionId);
    }
  }
}

final campusBackendProvider = Provider<CampusBackend>((ref) {
  if (AppConfig.env == 'mock') {
    return MockCampusBackend();
  }
  final api = ref.read(apiServiceProvider);
  final sessionManager = ref.read(sessionManagerProvider);
  final credentialService = ref.read(credentialServiceProvider);
  return _ApiCampusBackend(api, sessionManager, credentialService);
});

class _ApiCampusBackend implements CampusBackend {
  _ApiCampusBackend(this._api, this._sessionManager, this._credentialService);

  final ApiService _api;
  final SessionManager _sessionManager;
  final CredentialService _credentialService;
  final Map<String, Future<String>> _oneCardRehydrateTasks = {};
  final Map<String, Future<String>> _oneCardRestoreTasks = {};

  bool _isOneCardAuthFailure(Object error) {
    if (error is! ApiException) return false;
    if (error.code == 401) return true;
    if (error.code != 500) return false;
    final msg = error.message;
    return msg.contains('授权失败') ||
        msg.contains('登录状态') ||
        msg.contains('校园卡') ||
        msg.contains('电费') ||
        msg.contains('获取失败') ||
        msg.contains('登录失败');
  }

  Future<void> _tryRestoreLoginState(String username, String sessionId) async {
    try {
      await _sessionManager.restoreLoginState(username, sessionId);
    } catch (error) {
      debugPrint(
        '[ApiCampusBackend] restoreLoginState ignored username=$username sessionId=$sessionId reason=$error',
      );
    }
  }

  Future<String> _ensureRehydratedOneCardSession(
    String username,
    String? password,
  ) {
    final existing = _oneCardRehydrateTasks[username];
    if (existing != null) {
      debugPrint(
        '[ApiCampusBackend] join in-flight one-card rehydrate username=$username',
      );
      return existing;
    }

    late final Future<String> task;
    task = _rehydrateOneCardSession(username, password).whenComplete(() {
      if (identical(_oneCardRehydrateTasks[username], task)) {
        _oneCardRehydrateTasks.remove(username);
      }
    });
    _oneCardRehydrateTasks[username] = task;
    return task;
  }

  Future<String> _ensureRestoredOneCardSession(
    String username,
    String sessionId,
  ) {
    final taskKey = '$username@$sessionId';
    final existing = _oneCardRestoreTasks[taskKey];
    if (existing != null) {
      debugPrint(
        '[ApiCampusBackend] join in-flight one-card restore username=$username sessionId=$sessionId',
      );
      return existing;
    }

    late final Future<String> task;
    task =
        (() async {
          await _tryRestoreLoginState(username, sessionId);
          return sessionId;
        })().whenComplete(() {
          if (identical(_oneCardRestoreTasks[taskKey], task)) {
            _oneCardRestoreTasks.remove(taskKey);
          }
        });
    _oneCardRestoreTasks[taskKey] = task;
    return task;
  }

  Future<String> _rehydrateOneCardSession(
    String username,
    String? password,
  ) async {
    final sessionId = await _sessionManager.refreshSessionId(username);
    var passwordToSeed = password;
    if (passwordToSeed == null || passwordToSeed.trim().isEmpty) {
      final creds = await _credentialService.load();
      if (creds != null && creds.username == username) {
        passwordToSeed = creds.password;
      }
    }
    if (passwordToSeed == null || passwordToSeed.trim().isEmpty) {
      await _tryRestoreLoginState(username, sessionId);
      debugPrint(
        '[ApiCampusBackend] password seed unavailable, restored login state only username=$username sessionId=$sessionId',
      );
      return sessionId;
    }

    try {
      // Force a password-based login on the fresh session so backend can cache
      // reusable credentials for one-card auto re-login.
      await _api.getSchedule(
        username,
        passwordToSeed,
        sessionId: sessionId,
        forceRefresh: true,
      );
      debugPrint(
        '[ApiCampusBackend] password seed succeeded username=$username sessionId=$sessionId',
      );
      return sessionId;
    } on ApiException catch (error) {
      if (error.code == 401) rethrow;
      debugPrint(
        '[ApiCampusBackend] password seed failed, falling back to restored login state username=$username sessionId=$sessionId reason=$error',
      );
    } catch (error) {
      debugPrint(
        '[ApiCampusBackend] password seed failed, falling back to restored login state username=$username sessionId=$sessionId reason=$error',
      );
    }
    await _tryRestoreLoginState(username, sessionId);
    return sessionId;
  }

  Future<T> _runOneCardRequest<T>({
    required String operation,
    required String username,
    String? password,
    required Future<T> Function(String sessionId) primaryRequest,
    required Future<T> Function(String sessionId) recoveredRequest,
  }) async {
    var sessionId = await _sessionManager.ensureSessionId(username);
    try {
      return await primaryRequest(sessionId);
    } catch (error) {
      final sessionExpired = _sessionManager.isSessionExpiredError(error);
      final oneCardAuthFailure = _isOneCardAuthFailure(error);
      if (!sessionExpired && !oneCardAuthFailure) {
        rethrow;
      }

      if (sessionExpired) {
        debugPrint(
          '[ApiCampusBackend] $operation retry after session refresh username=$username reason=$error',
        );
        sessionId = await _ensureRehydratedOneCardSession(username, password);
        return recoveredRequest(sessionId);
      }

      debugPrint(
        '[ApiCampusBackend] $operation retry after login state restore username=$username sessionId=$sessionId reason=$error',
      );
      sessionId = await _ensureRestoredOneCardSession(username, sessionId);

      try {
        return await recoveredRequest(sessionId);
      } catch (retryError) {
        final retrySessionExpired = _sessionManager.isSessionExpiredError(
          retryError,
        );
        final retryOneCardAuthFailure = _isOneCardAuthFailure(retryError);
        if (!retrySessionExpired && !retryOneCardAuthFailure) {
          rethrow;
        }

        debugPrint(
          '[ApiCampusBackend] $operation escalates to full rehydrate username=$username sessionId=$sessionId reason=$retryError',
        );
        sessionId = await _ensureRehydratedOneCardSession(username, password);
        return recoveredRequest(sessionId);
      }
    }
  }

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) => _sessionManager.runWithSessionRetry(
    username: username,
    request: (sessionId) => _api.getSchedule(
      username,
      password,
      sessionId: sessionId,
      semester: semester,
      forceRefresh: forceRefresh,
    ),
  );

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) => _sessionManager.runWithSessionRetry(
    username: username,
    request: (sessionId) => _api.getGrades(
      username,
      password,
      sessionId: sessionId,
      semester: semester,
      forceRefresh: forceRefresh,
    ),
  );

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) => _sessionManager.runWithSessionRetry(
    username: username,
    request: (sessionId) => _api.getExams(
      username,
      password,
      sessionId: sessionId,
      semester: semester,
      forceRefresh: forceRefresh,
    ),
  );

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async {
    return _runOneCardRequest(
      operation: 'getElecBalance',
      username: username,
      password: password,
      primaryRequest: (sessionId) => _api.getElecBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
        dormParams: dormParams,
      ),
      recoveredRequest: (sessionId) => _api.getElecBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: true,
        dormParams: dormParams,
      ),
    );
  }

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async {
    return _runOneCardRequest(
      operation: 'getCampusCardBalance',
      username: username,
      password: password,
      primaryRequest: (sessionId) => _api.getCampusCardBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
      ),
      recoveredRequest: (sessionId) => _api.getCampusCardBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: true,
      ),
    );
  }

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    Map<String, String>? dormParams,
  }) async {
    return _runOneCardRequest(
      operation: 'rechargeElec',
      username: username,
      primaryRequest: (sessionId) => _api.rechargeElec(
        username,
        amount,
        sessionId: sessionId,
        dormParams: dormParams,
      ),
      recoveredRequest: (sessionId) => _api.rechargeElec(
        username,
        amount,
        sessionId: sessionId,
        dormParams: dormParams,
      ),
    );
  }

  @override
  Future<String> getPayCodeToken(String username) async {
    return _runOneCardRequest(
      operation: 'getPayCodeToken',
      username: username,
      primaryRequest: (sessionId) =>
          _api.getPayCodeToken(username, sessionId: sessionId),
      recoveredRequest: (sessionId) =>
          _api.getPayCodeToken(username, sessionId: sessionId),
    );
  }

  @override
  Future<String> getCampusCardAlipayUrl(String username, double amount) async {
    return _runOneCardRequest(
      operation: 'getCampusCardAlipayUrl',
      username: username,
      primaryRequest: (sessionId) =>
          _api.getCampusCardAlipayUrl(username, amount, sessionId: sessionId),
      recoveredRequest: (sessionId) =>
          _api.getCampusCardAlipayUrl(username, amount, sessionId: sessionId),
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
  String toString() => '请先设置宿舍';
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

  debugPrint('[FG] 查询电费: ${dorm.displayName}');
  debugPrint(
    '[FG] getElecBalance request username=${creds.username} passwordLen=${creds.password.length}',
  );
  final balance = await backend.getElecBalance(
    creds.username,
    creds.password,
    dormParams: dorm.toQueryParams(),
  );
  debugPrint('[FG] 电费余额获取成功: $balance');
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
