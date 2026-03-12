import 'package:core/models/dorm_room.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'app_update_service.dart';

const kBgTaskName = 'balanceMonitor';
const kBgTaskTag = 'com.axu.schedule.balanceMonitor';

const _elecChannelId = 'elec_alert_v2';
const _cardChannelId = 'card_alert_v2';
const _updateChannelId = 'app_update_v1';
const _sessionPrefix = 'session_id_';
const _ticketPrefix = 'login_ticket_';
const _casCookiesPrefix = 'cas_cookies_';
const _jwgCookiesPrefix = 'jwg_cookies_';
const _ecardCookiesPrefix = 'ecard_cookies_';
const _casDomain = 'ids.cqjtu.edu.cn';
const _jwgDomain = 'jwgln.cqjtu.edu.cn';
const _ecardDomain = 'ecard.cqjtu.edu.cn';

class _BgSessionExpiredException implements Exception {}

@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kBgTaskName) return true;

    try {
      final now = DateTime.now();
      final isNight = now.hour >= 0 && now.hour < 6;
      if (isNight) {
        final prefs0 = await SharedPreferences.getInstance();
        final lastRun = prefs0.getInt('bg_last_run') ?? 0;
        final elapsed = now.millisecondsSinceEpoch - lastRun;
        const nightInterval = Duration(hours: 3);
        if (elapsed < nightInterval.inMilliseconds) {
          debugPrint('[BG] night throttle, skip this run');
          return true;
        }
      }

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final androidPlugin = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _elecChannelId,
          '电费预警',
          description: '电费余额低于阈值时通知',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _cardChannelId,
          '校园卡预警',
          description: '校园卡余额低于阈值时通知',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _updateChannelId,
          '应用更新',
          description: '检测到新版本时提醒下载',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      try {
        await _checkAppUpdate(plugin);
      } catch (e) {
        debugPrint('[BG] app update check failed: $e');
      }

      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final username = await storage.read(key: 'username');
      final password = await storage.read(key: 'password');
      if (username == null ||
          username.trim().isEmpty ||
          password == null ||
          password.trim().isEmpty) {
        debugPrint('[BG] credentials not found, skip');
        return true;
      }
      debugPrint(
        '[BG] credentials loaded username=$username passwordLen=${password.length}',
      );

      final elecThreshold = prefs.getDouble('elec_threshold') ?? 10.0;
      final cardThreshold = prefs.getDouble('card_threshold') ?? 20.0;
      final dormParams = _readDormParams(prefs);

      final dio = Dio(
        BaseOptions(
          baseUrl: const String.fromEnvironment(
            'BASE_URL',
            defaultValue: 'http://127.0.0.1:8080',
          ),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      var sessionId = await _ensureSessionId(storage, dio, username);
      await _restoreLoginState(storage, dio, username, sessionId);

      try {
        await _checkElec(
          dio,
          plugin,
          prefs,
          username,
          password,
          sessionId,
          elecThreshold,
          dormParams,
        );
      } on _BgSessionExpiredException {
        sessionId = await _refreshSessionId(storage, dio, username);
        await _restoreLoginState(storage, dio, username, sessionId);
        await _checkElec(
          dio,
          plugin,
          prefs,
          username,
          password,
          sessionId,
          elecThreshold,
          dormParams,
        );
      }

      try {
        await _checkCard(
          dio,
          plugin,
          prefs,
          username,
          password,
          sessionId,
          cardThreshold,
        );
      } on _BgSessionExpiredException {
        sessionId = await _refreshSessionId(storage, dio, username);
        await _restoreLoginState(storage, dio, username, sessionId);
        await _checkCard(
          dio,
          plugin,
          prefs,
          username,
          password,
          sessionId,
          cardThreshold,
        );
      }

      await prefs.setInt('bg_last_run', DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (e) {
      debugPrint('[BG] task failed: $e');
      return true;
    }
  });
}

Map<String, String>? _readDormParams(SharedPreferences prefs) {
  final map = {
    'dorm_campus': prefs.getString('dorm_campus'),
    'dorm_garden': prefs.getString('dorm_garden'),
    'dorm_number': prefs.getString('dorm_number'),
    'dorm_roomid': prefs.getString('dorm_roomid'),
  };
  return DormRoom.fromPrefsMap(map)?.toQueryParams();
}

Future<void> _checkElec(
  Dio dio,
  FlutterLocalNotificationsPlugin plugin,
  SharedPreferences prefs,
  String username,
  String password,
  String sessionId,
  double threshold,
  Map<String, String>? dormParams,
) async {
  final queryParams = <String, dynamic>{
    'username': username,
    'password': password,
    'sessionId': sessionId,
    if (dormParams != null) ...dormParams,
  };

  var res = await dio.get('/api/elec/balance', queryParameters: queryParams);
  if (_isSessionExpiredResponse(res.data)) {
    throw _BgSessionExpiredException();
  }
  if (res.data['code'] != 200) {
    debugPrint(
      '[BG] elec first attempt failed code=${res.data['code']} msg=${res.data['msg']}, retry with forceRefresh',
    );
    res = await dio.get(
      '/api/elec/balance',
      queryParameters: {...queryParams, 'forceRefresh': true},
    );
    if (_isSessionExpiredResponse(res.data)) {
      throw _BgSessionExpiredException();
    }
    if (res.data['code'] != 200) {
      debugPrint(
        '[BG] elec retry failed code=${res.data['code']} msg=${res.data['msg']}',
      );
      return;
    }
  }

  final balStr = res.data['data'] as String? ?? '';
  final bal = _parseBalance(balStr);
  if (bal.isNaN || threshold <= 0 || bal >= threshold) return;
  if (!_canNotify(prefs, 'elec_last_notif')) return;

  await plugin.show(
    101,
    '电费不足提醒',
    '宿舍剩余电费 ¥$balStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值。',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _elecChannelId,
        '电费预警',
        channelDescription: '电费余额低于阈值时通知',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    ),
  );
  await prefs.setInt('elec_last_notif', _nowMs());
}

Future<void> _checkCard(
  Dio dio,
  FlutterLocalNotificationsPlugin plugin,
  SharedPreferences prefs,
  String username,
  String password,
  String sessionId,
  double threshold,
) async {
  var res = await dio.get('/api/elec/cardBalance', queryParameters: {
    'username': username,
    'password': password,
    'sessionId': sessionId,
  });
  if (_isSessionExpiredResponse(res.data)) {
    throw _BgSessionExpiredException();
  }
  if (res.data['code'] != 200) {
    debugPrint(
      '[BG] card first attempt failed code=${res.data['code']} msg=${res.data['msg']}, retry with forceRefresh',
    );
    res = await dio.get('/api/elec/cardBalance', queryParameters: {
      'username': username,
      'password': password,
      'sessionId': sessionId,
      'forceRefresh': true,
    });
    if (_isSessionExpiredResponse(res.data)) {
      throw _BgSessionExpiredException();
    }
    if (res.data['code'] != 200) {
      debugPrint(
        '[BG] card retry failed code=${res.data['code']} msg=${res.data['msg']}',
      );
      return;
    }
  }

  final balStr = res.data['data'] as String? ?? '';
  final bal = _parseBalance(balStr);
  if (bal.isNaN || threshold <= 0 || bal >= threshold) return;
  if (!_canNotify(prefs, 'card_last_notif')) return;

  await plugin.show(
    102,
    '校园卡余额不足',
    '校园卡余额 ¥$balStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值。',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _cardChannelId,
        '校园卡预警',
        channelDescription: '校园卡余额低于阈值时通知',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    ),
  );
  await prefs.setInt('card_last_notif', _nowMs());
}

Future<String> _ensureSessionId(
  FlutterSecureStorage storage,
  Dio dio,
  String username,
) async {
  return _refreshSessionId(storage, dio, username);
}

Future<String> _refreshSessionId(
  FlutterSecureStorage storage,
  Dio dio,
  String username,
) async {
  final sessionId = await _createSession(dio, username);
  await storage.write(key: _sessionKey(username), value: sessionId);
  return sessionId;
}

Future<String> _createSession(Dio dio, String username) async {
  final res = await dio.post(
    '/api/auth/createSession',
    queryParameters: {'username': username},
  );
  if (res.data['code'] != 200) {
    throw Exception(res.data['msg'] ?? 'createSession failed');
  }

  final sessionId = _extractSessionId(res.data);
  if (sessionId == null || sessionId.isEmpty) {
    throw Exception('createSession returned empty sessionId');
  }
  return sessionId;
}

Future<void> _restoreLoginState(
  FlutterSecureStorage storage,
  Dio dio,
  String username,
  String sessionId,
) async {
  final ticket = (await storage.read(key: _ticketKey(username)))?.trim() ?? '';
  if (ticket.isNotEmpty) {
    try {
      await _loginWithTicket(dio, username, ticket, sessionId);
    } catch (error) {
      debugPrint('[BG] ticket restore failed username=$username reason=$error');
    }
  }

  await _injectCookiesFromStorage(
    storage: storage,
    dio: dio,
    username: username,
    sessionId: sessionId,
    storageKey: _casCookiesKey(username),
    domain: _casDomain,
    tag: 'CAS',
  );
  await _injectCookiesFromStorage(
    storage: storage,
    dio: dio,
    username: username,
    sessionId: sessionId,
    storageKey: _jwgCookiesKey(username),
    domain: _jwgDomain,
    tag: 'JWG',
  );
  await _injectCookiesFromStorage(
    storage: storage,
    dio: dio,
    username: username,
    sessionId: sessionId,
    storageKey: _ecardCookiesKey(username),
    domain: _ecardDomain,
    tag: 'ECARD',
  );
}

Future<void> _injectCookiesFromStorage({
  required FlutterSecureStorage storage,
  required Dio dio,
  required String username,
  required String sessionId,
  required String storageKey,
  required String domain,
  required String tag,
}) async {
  final cookies = (await storage.read(key: storageKey))?.trim() ?? '';
  if (cookies.isEmpty) return;
  try {
    await _injectCookies(dio, username, sessionId, domain, cookies);
  } catch (error) {
    debugPrint(
      '[BG] $tag cookie restore failed username=$username reason=$error',
    );
  }
}

Future<void> _loginWithTicket(
  Dio dio,
  String username,
  String ticket,
  String sessionId,
) async {
  final res = await dio.post(
    '/api/auth/loginWithTicket',
    queryParameters: {
      'username': username,
      'ticket': ticket,
      'sessionId': sessionId,
    },
  );
  _ensureSuccessCode(res.data, fallbackMessage: 'loginWithTicket failed');
}

Future<void> _injectCookies(
  Dio dio,
  String username,
  String sessionId,
  String domain,
  String cookies,
) async {
  final res = await dio.post(
    '/api/auth/injectCookies',
    queryParameters: {
      'username': username,
      'sessionId': sessionId,
      'domain': domain,
      'cookies': cookies,
    },
  );
  _ensureSuccessCode(res.data, fallbackMessage: 'injectCookies failed');
}

void _ensureSuccessCode(dynamic data, {required String fallbackMessage}) {
  final code = data is Map ? data['code'] : null;
  if (code == 200) return;
  final msg = (data is Map ? data['msg'] : null)?.toString();
  throw Exception(msg == null || msg.isEmpty ? fallbackMessage : msg);
}

String? _extractSessionId(dynamic data) {
  final direct = data['sessionId'];
  if (direct is String && direct.isNotEmpty) return direct;

  final inner = data['data'];
  if (inner is Map<String, dynamic>) {
    final nested = inner['sessionId'];
    if (nested is String && nested.isNotEmpty) return nested;
  }
  if (inner is Map) {
    final nested = inner['sessionId'];
    if (nested is String && nested.isNotEmpty) return nested;
  }
  return null;
}

bool _isSessionExpiredResponse(dynamic data) {
  final code = data['code'];
  final msg = (data['msg'] ?? '').toString().toLowerCase();
  return code == 403 && msg.contains('sessionid');
}

String _sessionKey(String username) => '$_sessionPrefix$username';
String _ticketKey(String username) => '$_ticketPrefix$username';
String _casCookiesKey(String username) => '$_casCookiesPrefix$username';
String _jwgCookiesKey(String username) => '$_jwgCookiesPrefix$username';
String _ecardCookiesKey(String username) => '$_ecardCookiesPrefix$username';

double _parseBalance(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^\-0-9.]'), '')) ?? double.nan;

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

bool _canNotify(SharedPreferences prefs, String key) {
  const cooldown = Duration(hours: 4);
  final last = prefs.getInt(key) ?? 0;
  return _nowMs() - last > cooldown.inMilliseconds;
}

Future<void> _checkAppUpdate(FlutterLocalNotificationsPlugin plugin) async {
  final result = await AppUpdateService.checkForStoredInstalledVersion();
  if (result == null || !result.hasUpdate || result.latest == null) return;

  final latest = result.latest!;
  if (!await AppUpdateService.shouldNotify(latest)) return;

  final body = latest.force
      ? '检测到重要更新 ${latest.label}，打开 App 即可下载'
      : '检测到新版本 ${latest.label}，打开 App 查看并下载';

  await plugin.show(
    103,
    '发现新版本',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _updateChannelId,
        '应用更新',
        channelDescription: '检测到新版本时提醒下载',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    ),
    payload: 'app_update',
  );

  await AppUpdateService.markNotified(latest);
}
