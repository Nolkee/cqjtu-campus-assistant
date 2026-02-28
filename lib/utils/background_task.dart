import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager 任务标识
const kBgTaskName = 'balanceMonitor';
const kBgTaskTag  = 'com.axu.schedule.balanceMonitor';

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

      // ── 2. 初始化通知插件
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      debugPrint('[BG] 通知插件初始化完成');

      // ── 3. 读取预警阈值
      final prefs = await SharedPreferences.getInstance();
      final elecThreshold = prefs.getDouble('elec_threshold') ?? 10.0;
      final cardThreshold = prefs.getDouble('card_threshold') ?? 20.0;
      debugPrint('[BG] 阈值读取：电费=$elecThreshold，校园卡=$cardThreshold');

      // ── 4. 读取宿舍参数（用户在 App 内选择并保存的）
      // 若用户未设置宿舍，dormParams 为 null，后端使用默认逻辑
      final dormParams = _readDormParams(prefs);
      debugPrint('[BG] 宿舍参数：${dormParams ?? "未设置，使用默认"}');

      // ── 5. 初始化 HTTP 客户端
      final dio = Dio(BaseOptions(
        baseUrl: 'http://47.109.25.240:8080',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

      // ── 6. 查询电费余额（携带宿舍参数）
      debugPrint('[BG] 开始查询电费余额...');
      await _checkElec(dio, plugin, prefs, username, password, elecThreshold, dormParams);

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

/// 从 SharedPreferences 读取宿舍查询参数
/// 若任一字段缺失则返回 null（表示用户未设置宿舍）
Map<String, String>? _readDormParams(SharedPreferences prefs) {
  final buildid = prefs.getString('dorm_buildid');
  final roomid  = prefs.getString('dorm_roomid');
  final sysid   = prefs.getString('dorm_sysid');
  final areaid  = prefs.getString('dorm_areaid');
  if (buildid == null || roomid == null || sysid == null || areaid == null) {
    return null;
  }
  return {
    'sysid':   sysid,
    'areaid':  areaid,
    'buildid': buildid,
    'roomid':  roomid,
  };
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

    final res = await dio.get('/api/elec/balance', queryParameters: queryParams);
    if (res.data['code'] != 200) {
      debugPrint('[BG] 电费接口返回非200：${res.data['code']}');
      return;
    }

    final balStr = res.data['data'] as String? ?? '';
    final bal = _parseBalance(balStr);
    debugPrint('[BG] 电费余额：$balStr（parsed=$bal），阈值=$threshold');

    if (bal.isNaN) { debugPrint('[BG] 电费余额解析失败，跳过'); return; }
    if (threshold <= 0) { debugPrint('[BG] 电费预警已关闭'); return; }
    if (bal >= threshold) { debugPrint('[BG] 电费余额充足'); return; }
    if (!_canNotify(prefs, 'elec_last_notif')) { debugPrint('[BG] 电费通知冷却中'); return; }

    debugPrint('[BG] 电费余额不足，发送通知！');
    await plugin.show(
      101,
      '⚡ 电费不足提醒',
      '寝室剩余电费 ¥$balStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值！',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'elec_alert',
          '电费预警',
          channelDescription: '电费余额低于预警阈值时通知',
          importance: Importance.high,
          priority: Priority.high,
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

    if (bal.isNaN) { debugPrint('[BG] 校园卡余额解析失败，跳过'); return; }
    if (threshold <= 0) { debugPrint('[BG] 校园卡预警已关闭'); return; }
    if (bal >= threshold) { debugPrint('[BG] 校园卡余额充足'); return; }
    if (!_canNotify(prefs, 'card_last_notif')) { debugPrint('[BG] 校园卡通知冷却中'); return; }

    debugPrint('[BG] 校园卡余额不足，发送通知！');
    await plugin.show(
      102,
      '💳 校园卡余额不足',
      '校园卡余额 ¥$balStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值！',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'card_alert',
          '校园卡预警',
          channelDescription: '校园卡余额低于预警阈值时通知',
          importance: Importance.high,
          priority: Priority.high,
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