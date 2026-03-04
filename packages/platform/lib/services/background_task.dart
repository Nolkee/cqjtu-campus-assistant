import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:core/models/dorm_room.dart';

/// WorkManager 任务标识
const kBgTaskName = 'balanceMonitor';
const kBgTaskTag = 'com.axu.schedule.balanceMonitor';

// ✅ 与 NotificationService 保持完全一致的 Channel ID，
// 必须用 v2 版本；旧的 'elec_alert'/'card_alert' 未配置
// Importance.high，发出的通知没有悬浮横幅且无声音。
const _elecChannelId = 'elec_alert_v2';
const _cardChannelId = 'card_alert_v2';

/// 后台任务入口，必须是顶层函数且加 @pragma。
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[BG] ══════════════════════════════════════');
    debugPrint('[BG] 任务触发：$taskName @ ${DateTime.now()}');

    if (taskName != kBgTaskName) {
      debugPrint('[BG] 任务名不匹配，跳过');
      return true;
    }

    try {
      // ── 1. 读取凭据
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final username = await storage.read(key: 'username');
      final password = await storage.read(key: 'password');
      if (username == null || password == null) {
        debugPrint('[BG] 未找到凭据，跳过本次任务');
        return true;
      }
      debugPrint('[BG] 凭据读取成功，user=$username');

      // ── 夜间降频：00:00 ~ 06:00 每 3 小时才真正执行一次 ──────────
      final now = DateTime.now();
      final isNight = now.hour >= 0 && now.hour < 6;
      if (isNight) {
        final prefs0 = await SharedPreferences.getInstance();
        final lastRun = prefs0.getInt('bg_last_run') ?? 0;
        final elapsed = now.millisecondsSinceEpoch - lastRun;
        const nightInterval = Duration(hours: 3);
        if (elapsed < nightInterval.inMilliseconds) {
          debugPrint('[BG] 夜间降频模式，距上次执行 ${elapsed ~/ 60000} 分钟，未到 3 小时，跳过');
          return true;
        }
        debugPrint('[BG] 夜间降频模式，已超过 3 小时，本次正常执行');
      }

      // ── 2. 初始化通知插件并创建渠道
      // ✅ 修复：后台进程是独立的 Isolate，不能依赖主进程创建过的渠道。
      // 必须在此处显式创建渠道，否则 Android 8+ 上通知会被静默丢弃。
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final androidPlugin = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // ✅ 每次后台任务启动都重新确保渠道存在（createNotificationChannel 是幂等的）
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _elecChannelId,
          '电费预警',
          description: '电费余额低于预警阈值时通知',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _cardChannelId,
          '校园卡预警',
          description: '校园卡余额低于预警阈值时通知',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      debugPrint('[BG] 通知插件初始化 & 渠道创建完成');

      // ── 3. 读取预警阈值
      final prefs = await SharedPreferences.getInstance();
      final elecThreshold = prefs.getDouble('elec_threshold') ?? 10.0;
      final cardThreshold = prefs.getDouble('card_threshold') ?? 20.0;
      debugPrint('[BG] 阈值读取：电费=$elecThreshold，校园卡=$cardThreshold');

      // ── 4. 读取宿舍参数（用户在 App 内选择并保存的）
      final dormParams = _readDormParams(prefs);
      debugPrint('[BG] 宿舍参数：${dormParams ?? "未设置，使用默认"}');

      // ── 5. 初始化 HTTP 客户端
      final dio = Dio(BaseOptions(
        baseUrl: const String.fromEnvironment(
          'BASE_URL',
          defaultValue: 'http://127.0.0.1:8080',
        ),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

      // ── 6. 查询电费余额
      debugPrint('[BG] 开始查询电费余额...');
      await _checkElec(
          dio, plugin, prefs, username, password, elecThreshold, dormParams);

      // ── 7. 查询校园卡余额
      debugPrint('[BG] 开始查询校园卡余额...');
      await _checkCard(dio, plugin, prefs, username, password, cardThreshold);

      debugPrint('[BG] 任务执行完成 ✅');
      await prefs.setInt('bg_last_run', DateTime.now().millisecondsSinceEpoch);
      debugPrint('[BG] ══════════════════════════════════════');
      return true;
    } catch (e) {
      debugPrint('[BG] 任务异常：$e');
      debugPrint('[BG] ══════════════════════════════════════');
      return true;
    }
  });
}

/// 按实际存储的 key 读取，然后手动拼出 buildid宿舍查询参数
Map<String, String>? _readDormParams(SharedPreferences prefs) {
  // 1. 尝试使用与 DormService.load() 相同的逻辑读取
  final map = {
    'dorm_campus': prefs.getString('dorm_campus'),
    'dorm_garden': prefs.getString('dorm_garden'),
    'dorm_number': prefs.getString('dorm_number'),
    'dorm_roomid': prefs.getString('dorm_roomid'),
  };

  // 2. 利用模型自身的工厂方法反序列化
  final dormRoom = DormRoom.fromPrefsMap(map);

  // 3. 直接调用模型已经封装好的 toQueryParams() 方法，保证与前台查询电费 100% 一致！
  return dormRoom?.toQueryParams();
}

// ── 电费查询 ──────────────────────────────────────────────────
Future<void> _checkElec(
  Dio dio,
  FlutterLocalNotificationsPlugin plugin,
  SharedPreferences prefs,
  String username,
  String password,
  double threshold,
  Map<String, String>? dormParams,
) async {
  try {
    final queryParams = <String, dynamic>{
      'username': username,
      'password': password,
      if (dormParams != null) ...dormParams,
    };

    final res =
        await dio.get('/api/elec/balance', queryParameters: queryParams);
    if (res.data['code'] != 200) {
      debugPrint('[BG] 电费接口返回非200：${res.data['code']}');
      return;
    }

    final balStr = res.data['data'] as String? ?? '';
    final bal = _parseBalance(balStr);
    debugPrint('[BG] 电费余额：$balStr（parsed=$bal），阈值=$threshold');

    if (bal.isNaN) {
      debugPrint('[BG] 电费余额解析失败，跳过');
      return;
    }
    if (threshold <= 0) {
      debugPrint('[BG] 电费预警已关闭');
      return;
    }
    if (bal >= threshold) {
      debugPrint('[BG] 电费余额充足');
      return;
    }
    if (!_canNotify(prefs, 'elec_last_notif')) {
      debugPrint('[BG] 电费通知冷却中');
      return;
    }

    debugPrint('[BG] 电费余额不足，发送通知！');
    await plugin.show(
      101,
      '⚡ 电费不足提醒',
      '寝室剩余电费 ¥$balStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值！',
      // ✅ 修复：使用 v2 Channel ID，与 NotificationService 保持一致
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _elecChannelId, // 'elec_alert_v2'
          '电费预警',
          channelDescription: '电费余额低于预警阈值时通知',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
    await prefs.setInt('elec_last_notif', _nowMs());
    debugPrint('[BG] 电费通知已发出');
  } catch (e) {
    debugPrint('[BG] 电费查询异常：$e');
  }
}

// ── 校园卡查询 ────────────────────────────────────────────────
Future<void> _checkCard(
  Dio dio,
  FlutterLocalNotificationsPlugin plugin,
  SharedPreferences prefs,
  String username,
  String password,
  double threshold,
) async {
  try {
    final res = await dio.get('/api/elec/cardBalance', queryParameters: {
      'username': username,
      'password': password,
    });
    if (res.data['code'] != 200) {
      debugPrint('[BG] 校园卡接口返回非200：${res.data['code']}');
      return;
    }

    final balStr = res.data['data'] as String? ?? '';
    final bal = _parseBalance(balStr);
    debugPrint('[BG] 校园卡余额：$balStr（parsed=$bal），阈值=$threshold');

    if (bal.isNaN) {
      debugPrint('[BG] 校园卡余额解析失败，跳过');
      return;
    }
    if (threshold <= 0) {
      debugPrint('[BG] 校园卡预警已关闭');
      return;
    }
    if (bal >= threshold) {
      debugPrint('[BG] 校园卡余额充足');
      return;
    }
    if (!_canNotify(prefs, 'card_last_notif')) {
      debugPrint('[BG] 校园卡通知冷却中');
      return;
    }

    debugPrint('[BG] 校园卡余额不足，发送通知！');
    await plugin.show(
      102,
      '💳 校园卡余额不足',
      '校园卡余额 ¥$balStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值！',
      // ✅ 修复：使用 v2 Channel ID
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _cardChannelId, // 'card_alert_v2'
          '校园卡预警',
          channelDescription: '校园卡余额低于预警阈值时通知',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
    await prefs.setInt('card_last_notif', _nowMs());
    debugPrint('[BG] 校园卡通知已发出');
  } catch (e) {
    debugPrint('[BG] 校园卡查询异常：$e');
  }
}

// ── 工具函数 ──────────────────────────────────────────────────
double _parseBalance(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^\-0-9.]'), '')) ?? double.nan;

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

bool _canNotify(SharedPreferences prefs, String key) {
  const cooldown = Duration(hours: 4);
  final last = prefs.getInt(key) ?? 0;
  return _nowMs() - last > cooldown.inMilliseconds;
}
