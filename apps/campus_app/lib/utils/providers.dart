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

  static const _casDomain = 'ids.cqjtu.edu.cn';
  static const _jwgDomain = 'jwgln.cqjtu.edu.cn';

  Future<String> ensureSessionId(String username) async {
    final cached = await _sessionService.loadSessionId(username);
    if (cached != null && cached.isNotEmpty) return cached;
    return refreshSessionId(username);
  }

  Future<String> refreshSessionId(String username) async {
    final sessionId = await _api.createSession(username);
    await _sessionService.saveSessionId(username, sessionId);
    return sessionId;
  }

  Future<void> saveWebLoginArtifacts(
    String username, {
    String? ticket,
    String? casCookies,
    String? jwgCookies,
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
  }

  Future<void> restoreLoginState(String username, String sessionId) async {
    final ticket = await _sessionService.loadTicket(username);
    if (ticket != null && ticket.isNotEmpty) {
      await _api.loginWithTicket(username, ticket, sessionId: sessionId);
      return;
    }

    final casCookies = await _sessionService.loadCasCookies(username);
    if (casCookies != null && casCookies.isNotEmpty) {
      await _api.injectCookies(
        username,
        _casDomain,
        casCookies,
        sessionId: sessionId,
      );
    }

    final jwgCookies = await _sessionService.loadJwgCookies(username);
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      await _api.injectCookies(
        username,
        _jwgDomain,
        jwgCookies,
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
    try {
      return await request(sessionId);
    } catch (error) {
      if (!isSessionExpiredError(error)) rethrow;
      sessionId = await refreshSessionId(username);
      await restoreLoginState(username, sessionId);
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
  return _ApiCampusBackend(api, sessionManager);
});

class _ApiCampusBackend implements CampusBackend {
  _ApiCampusBackend(this._api, this._sessionManager);

  final ApiService _api;
  final SessionManager _sessionManager;

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) =>
      _sessionManager.runWithSessionRetry(
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
  }) =>
      _sessionManager.runWithSessionRetry(
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
  }) =>
      _sessionManager.runWithSessionRetry(
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
  }) =>
      _sessionManager.runWithSessionRetry(
        username: username,
        request: (sessionId) => _api.getElecBalance(
          username,
          password,
          sessionId: sessionId,
          forceRefresh: forceRefresh,
          dormParams: dormParams,
        ),
      );

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) =>
      _sessionManager.runWithSessionRetry(
        username: username,
        request: (sessionId) => _api.getCampusCardBalance(
          username,
          password,
          sessionId: sessionId,
          forceRefresh: forceRefresh,
        ),
      );

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    Map<String, String>? dormParams,
  }) =>
      _sessionManager.runWithSessionRetry(
        username: username,
        request: (sessionId) => _api.rechargeElec(
          username,
          amount,
          sessionId: sessionId,
          dormParams: dormParams,
        ),
      );

  @override
  Future<String> getPayCodeToken(String username) =>
      _sessionManager.runWithSessionRetry(
        username: username,
        request: (sessionId) =>
            _api.getPayCodeToken(username, sessionId: sessionId),
      );

  @override
  Future<String> getCampusCardAlipayUrl(String username, double amount) =>
      _sessionManager.runWithSessionRetry(
        username: username,
        request: (sessionId) =>
            _api.getCampusCardAlipayUrl(username, amount, sessionId: sessionId),
      );
}

class CredentialsNotifier extends Notifier<({String username, String password})?> {
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
    NotifierProvider<CredentialsNotifier, ({String username, String password})?>(
      CredentialsNotifier.new,
    );

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

class SemesterStartForKeyNotifier extends FamilyAsyncNotifier<DateTime?, String> {
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
    AsyncNotifierProvider.family<SemesterStartForKeyNotifier, DateTime?, String>(
      SemesterStartForKeyNotifier.new,
    );

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

final scheduleProvider = FutureProvider.family<ScheduleResult, String?>(
  (ref, semester) async {
    ref.watch(sessionUpdateProvider);
    final creds = ref.watch(credentialsProvider);
    if (creds == null) throw Exception('未登录');

    final backend = ref.watch(campusBackendProvider);
    return backend.getSchedule(
      creds.username,
      creds.password,
      semester: semester,
    );
  },
);

final electricityProvider = FutureProvider<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final interval = pollingInterval();
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');

  final backend = ref.watch(campusBackendProvider);
  final dormAsync = ref.watch(dormRoomProvider);
  final dorm = await dormAsync.when(
    loading: () => ref.read(dormRoomProvider.future),
    error: (e, _) => Future<DormRoom?>.error(e),
    data: (d) => Future.value(d),
  );

  if (dorm == null) throw NoDormSetException();

  debugPrint('[FG] 查询电费: ${dorm.displayName}');
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
  if (creds == null) throw Exception('未登录');

  final backend = ref.watch(campusBackendProvider);
  final balance = await backend.getCampusCardBalance(
    creds.username,
    creds.password,
  );
  return balance;
});

final payCodeProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');

  final backend = ref.watch(campusBackendProvider);
  return backend.getPayCodeToken(creds.username);
});

typedef GradeResult = ({Map<String, String> summary, List<Grade> grades});

final gradesProvider = FutureProvider.autoDispose.family<GradeResult, String>(
  (ref, semester) async {
    final creds = ref.watch(credentialsProvider);
    if (creds == null) throw Exception('未登录');

    final backend = ref.watch(campusBackendProvider);
    return backend.getGrades(
      creds.username,
      creds.password,
      semester: semester,
    );
  },
);

final examsProvider = FutureProvider.autoDispose.family<List<Exam>, String?>(
  (ref, semester) async {
    final creds = ref.watch(credentialsProvider);
    if (creds == null) throw Exception('未登录');

    final backend = ref.watch(campusBackendProvider);
    return backend.getExams(
      creds.username,
      creds.password,
      semester: semester,
    );
  },
);

class SessionUpdateNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void triggerRefresh() => state++;
}

final sessionUpdateProvider = NotifierProvider<SessionUpdateNotifier, int>(
  SessionUpdateNotifier.new,
);
