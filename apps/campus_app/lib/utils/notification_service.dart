import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:core/models/course.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // SharedPreferences key
  static const _elecThresholdKey = 'elec_threshold';
  static const _cardThresholdKey = 'card_threshold';
  static const _courseReminderKey = 'course_reminder';

  static const double defaultElecThreshold = 10.0;
  static const double defaultCardThreshold = 20.0;
  static const bool defaultCourseReminder = true;

  // 向下兼容旧代码引用
  static const double defaultThreshold = defaultElecThreshold;

  static const Map<int, String> _slotStartTimes = {
    1: '08:20', 2: '09:05', 3: '10:00', 4: '10:45', 5: '11:30',
    6: '14:00', 7: '14:45', 8: '15:40', 9: '16:25', 10: '17:10',
    11: '19:00', 12: '19:45', 13: '20:30',
  };

  // ── 通知渠道 ID 常量（修改此值可强制系统重建渠道，带走新的声音/震动配置）──
  // 每次需要"重置"渠道配置时，把末尾版本号 +1 即可，无需卸载 App
  static const _classChannelId   = 'class_reminder_v2';
  static const _classChannelName = '上课提醒';
  static const _elecChannelId    = 'elec_alert_v2';
  static const _cardChannelId    = 'card_alert_v2';

  static Future<void> init() async {
    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    final String timeZoneName = tzInfo.identifier;
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    // ── 预先创建所有通知渠道，明确指定声音与震动 ──
    // Android 8+ 要求声音/震动必须在渠道层面开启，Notification 级别的设置仅作补充。
    // 渠道一旦创建后系统会永久缓存，修改 ID（如 v2→v3）是唯一让新配置生效的办法。
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _classChannelId,
        _classChannelName,
        description: '课前 15 分钟提醒，带声音与震动',
        importance: Importance.high, // high = 横幅 + 声音 + 震动
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ),
    );
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

    // 申请 Android 13+ 通知权限
    await androidPlugin?.requestNotificationsPermission();
    // 申请精确闹钟权限 (Android 12+)
    await androidPlugin?.requestExactAlarmsPermission();
  }

  // ▼ 新增：动态调度课程提醒
  static Future<void> scheduleClassReminders(List<Course> courses, DateTime semesterStart) async {
    final now = DateTime.now();
    // 算出开学第一周的周一
    final semesterMonday = semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
    // ✅ 获取通知开关状态
    final isReminderEnabled = await getCourseReminderEnabled();
    // 当前是第几周
    final currentWeek = (now.difference(semesterMonday).inDays ~/ 7) + 1;
  
    // 策略：每次刷新只调度【今天】和【明天】的课，避免数量爆炸
    for (int w = currentWeek; w <= currentWeek + 1; w++) {
      if (w < 1 || w > 20) continue; 

      // 【核心防抖】先取消这周可能存在的旧调度（防止课表发生变更导致“幽灵通知”）
      for (int day = 1; day <= 7; day++) {
        for (int slot = 1; slot <= 13; slot++) {
           await _plugin.cancel(w * 1000 + day * 100 + slot);
        }
      }

      if (!isReminderEnabled) continue;
      
      final mondayOfWeek = semesterMonday.add(Duration(days: (w - 1) * 7));

      for (final course in courses) {
        if (!course.isActiveInWeek(w)) continue;
        final classDate = mondayOfWeek.add(Duration(days: course.dayOfWeek - 1));
        // 你一周都不开这个app说明你也不需要这个app了
        if (classDate.difference(now).inDays > 7) continue;

        final timeStr = _slotStartTimes[course.timeSlot];
        if (timeStr == null) continue;

        final timeParts = timeStr.split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);

        final classTime = DateTime(classDate.year, classDate.month, classDate.day, hour, minute);
    
        // 提前 15 分钟
        final remindTime = classTime.subtract(const Duration(minutes: 15));

        if (remindTime.isAfter(now)) {
          final notificationId = w * 1000 + course.dayOfWeek * 100 + course.timeSlot;
    
          await _plugin.zonedSchedule(
            notificationId,
            '上课提醒：${course.name}',
            '将在 15 分钟后（$timeStr）在 ${course.classroom} 上课',
            tz.TZDateTime.from(remindTime, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                _classChannelId,
                _classChannelName,
                channelDescription: '课前 15 分钟提醒，带声音与震动',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                enableLights: true,
                // 震动节奏：短-停-长-停-长（单位毫秒）
                vibrationPattern: Int64List.fromList([0, 200, 200, 400, 200, 400]),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    }
  }

  /// 前台运行时检查电费余额并推送（供 electricityProvider 调用）
  static Future<void> checkAndNotify(String balanceStr) async {
    final match = RegExp(r'-?[\d.]+').firstMatch(balanceStr);
    if (match == null) return;
    final balance = double.tryParse(match.group(0)!);
    if (balance == null) return;

    final threshold = await getElecThreshold();
    if (threshold <= 0) return;
    if (balance < threshold) {
      await _plugin.show(
        1,
        '⚡ 电费不足提醒',
        '寝室剩余电费 ¥$balanceStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值！',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _elecChannelId,
            '电费预警',
            channelDescription: '电费余额低于预警阈值时通知',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    }
  }

  // ── 电费阈值 ──────────────────────────────────────────────
  static Future<double> getElecThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_elecThresholdKey) ?? defaultElecThreshold;
  }

  static Future<void> setElecThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_elecThresholdKey, value);
  }

  // 向下兼容旧代码
  static Future<double> getThreshold() => getElecThreshold();
  static Future<void> setThreshold(double value) => setElecThreshold(value);

  // ── 校园卡阈值 ─────────────────────────────────────────────
  static Future<double> getCardThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_cardThresholdKey) ?? defaultCardThreshold;
  }

  static Future<void> setCardThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_cardThresholdKey, value);
  }

  static Future<bool> getCourseReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_courseReminderKey) ?? defaultCourseReminder;
  }

  static Future<void> setCourseReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_courseReminderKey, value);
  }
}