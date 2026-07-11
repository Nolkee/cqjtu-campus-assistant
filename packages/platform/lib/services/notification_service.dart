import 'package:flutter/foundation.dart';
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
  static const _courseReminderMinutesKey = 'course_reminder_minutes';

  static const double defaultElecThreshold = 10.0;
  static const double defaultCardThreshold = 20.0;
  static const bool defaultCourseReminder = true;
  static const int defaultCourseReminderMinutes = 15;
  static const int minCourseReminderMinutes = 15;
  static const int maxCourseReminderMinutes = 60;

  // 向下兼容旧代码引用
  static const double defaultThreshold = defaultElecThreshold;

  static const Map<int, String> _slotStartTimes = {
    1: '08:20',
    2: '09:05',
    3: '10:00',
    4: '10:45',
    5: '11:30',
    6: '14:00',
    7: '14:45',
    8: '15:40',
    9: '16:25',
    10: '17:10',
    11: '19:00',
    12: '19:45',
    13: '20:30',
  };

  // ── 通知渠道 ID 常量（修改此值可强制系统重建渠道，带走新的声音/震动配置）──
  static const _classChannelId = 'class_reminder_v2';
  static const _classChannelName = '上课提醒';
  static const _elecChannelId = 'elec_alert_v2';
  static const _cardChannelId = 'card_alert_v2';

  static Future<void> init() async {
    debugPrint('[NOTIF] init() 开始');
    tz.initializeTimeZones();

    final tzInfo = await FlutterTimezone.getLocalTimezone();
    final String timeZoneName = tzInfo.identifier;
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    debugPrint('[NOTIF] 时区初始化完成: $timeZoneName');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(settings);
    debugPrint('[NOTIF] 插件初始化完成');

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _classChannelId,
        _classChannelName,
        description: '课前提醒，带声音与震动',
        importance: Importance.high,
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
    debugPrint(
        '[NOTIF] 通知渠道创建完成: $_classChannelId / $_elecChannelId / $_cardChannelId');

    // ✅ Bug 1 说明：此处运行时申请通知权限，但若 AndroidManifest.xml 未声明
    //    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    //    系统会在 Android 13+ 上直接拒绝，通知完全失效。
    //    请确保 Manifest 已声明该权限（详见下方注释）。
    final notifGranted =
        await androidPlugin?.requestNotificationsPermission() ?? false;
    debugPrint('[NOTIF] 通知权限申请结果: $notifGranted'
        '${notifGranted ? '' : ' ⚠️ 权限被拒绝！请检查 AndroidManifest.xml 是否声明了 POST_NOTIFICATIONS'}');

    final alarmGranted =
        await androidPlugin?.requestExactAlarmsPermission() ?? false;
    debugPrint('[NOTIF] 精确闹钟权限申请结果: $alarmGranted'
        '${alarmGranted ? '' : ' ⚠️ 精确闹钟权限未获取，定时通知可能延迟或失效'}');

    final iosPermissionGranted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
    debugPrint('[NOTIF] iOS 通知权限申请结果: $iosPermissionGranted');

    debugPrint('[NOTIF] init() 完成 ✅');
  }

  // ▼ 动态调度课程提醒
  static Future<void> scheduleClassReminders(
      List<Course> courses, DateTime semesterStart) async {
    final now = DateTime.now();

    // ✅ Bug 2 修复：用纯日期（00:00:00）做天数比较，消除 now 时分秒的影响。
    //    旧写法：classDate.difference(now).inDays
    //    例：周一 14:00，下周三 classDate 为周三 00:00，相差 8 天零 10 小时，
    //    inDays 截断为 8 > 7，该课被错误丢弃。
    //    新写法：classDate.difference(today).inDays，today 也是 00:00:00，
    //    结果始终是整天数，不再受当前时间影响。
    final today = DateTime(now.year, now.month, now.day);

    final semesterMonday =
        semesterStart.subtract(Duration(days: semesterStart.weekday - 1));
    final isReminderEnabled = await getCourseReminderEnabled();
    final reminderMinutes = await getCourseReminderMinutes();
    final currentWeek = (now.difference(semesterMonday).inDays ~/ 7) + 1;

    debugPrint('[NOTIF] ══════════════════════════════════════');
    debugPrint('[NOTIF] scheduleClassReminders 开始');
    debugPrint('[NOTIF] 当前时间: $now');
    debugPrint('[NOTIF] 今日日期(00:00): $today');
    debugPrint('[NOTIF] 开学周一: $semesterMonday');
    debugPrint('[NOTIF] 时区: ${tz.local.name}');
    debugPrint(
      '[NOTIF] 当前第 $currentWeek 周，课程提醒开关: $isReminderEnabled，提前 $reminderMinutes 分钟',
    );
    debugPrint('[NOTIF] 将处理第 $currentWeek 周和第 ${currentWeek + 1} 周');

    // ✅ cancelAll() 移到循环外：只执行一次，避免第 2 周循环时
    //    把第 1 周刚调度好的通知全部删掉。
    debugPrint('[NOTIF] cancelAll() 清空所有旧通知调度...');
    final swCancel = Stopwatch()..start();
    await _plugin.cancelAll();
    swCancel.stop();
    debugPrint('[NOTIF] 旧调度清空完成，耗时 ${swCancel.elapsedMilliseconds}ms');

    if (!isReminderEnabled) {
      debugPrint('[NOTIF] 课程提醒开关已关闭，跳过全部调度');
      return;
    }

    for (int w = currentWeek; w <= currentWeek + 1; w++) {
      if (w < 1 || w > 20) {
        debugPrint('[NOTIF] 第 $w 周超出范围(1~20)，跳过');
        continue;
      }

      final mondayOfWeek = semesterMonday.add(Duration(days: (w - 1) * 7));
      int scheduledCount = 0;
      int skippedPast = 0;
      int skippedInactive = 0;
      int skippedTooFar = 0;

      for (final course in courses) {
        if (!course.isActiveInWeek(w)) {
          skippedInactive++;
          continue;
        }

        final classDate =
            mondayOfWeek.add(Duration(days: course.dayOfWeek - 1));
        final daysFromToday = classDate.difference(today).inDays;

        if (daysFromToday > 7) {
          skippedTooFar++;
          debugPrint('[NOTIF] 跳过(超7天): ${course.name} '
              '${classDate.month}/${classDate.day}，距今 $daysFromToday 天');
          continue;
        }

        final timeStr = _slotStartTimes[course.timeSlot];
        if (timeStr == null) {
          debugPrint('[NOTIF] 警告：${course.name} 节次${course.timeSlot}无时间配置');
          continue;
        }

        final parts = timeStr.split(':');
        final classTime = DateTime(classDate.year, classDate.month,
            classDate.day, int.parse(parts[0]), int.parse(parts[1]));
        final remindTime = classTime.subtract(
          Duration(minutes: reminderMinutes),
        );

        if (!remindTime.isAfter(now)) {
          skippedPast++;
          debugPrint('[NOTIF] 跳过(已过期): ${course.name} '
              '提醒时间 ${remindTime.month}/${remindTime.day} '
              '${remindTime.hour}:${remindTime.minute.toString().padLeft(2, '0')}');
          continue;
        }

        final notificationId =
            w * 1000 + course.dayOfWeek * 100 + course.timeSlot;
        final tzRemindTime = tz.TZDateTime.from(remindTime, tz.local);

        debugPrint('[NOTIF] ✅ 调度 #$notificationId: ${course.name} '
            '@ ${classDate.month}/${classDate.day} $timeStr '
            '→ 提醒 ${remindTime.month}/${remindTime.day} '
            '${remindTime.hour}:${remindTime.minute.toString().padLeft(2, '0')} '
            '(tz=${tzRemindTime.timeZoneName})');

        await _plugin.zonedSchedule(
          notificationId,
          '上课提醒：${course.name}',
          '将在 $reminderMinutes 分钟后（$timeStr）在 ${course.classroom} 上课',
          tzRemindTime,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _classChannelId,
              _classChannelName,
              channelDescription: '课前提醒，带声音与震动',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              vibrationPattern:
                  Int64List.fromList([0, 200, 200, 400, 200, 400]),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        scheduledCount++;
      }

      debugPrint('[NOTIF] 第 $w 周汇总 → '
          '已调度: $scheduledCount | '
          '已过期: $skippedPast | '
          '本周无课: $skippedInactive | '
          '超7天: $skippedTooFar');
    }

    debugPrint('[NOTIF] scheduleClassReminders 完成 ✅');
    debugPrint('[NOTIF] ══════════════════════════════════════');
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
        const NotificationDetails(
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

  static Future<int> getCourseReminderMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        prefs.getInt(_courseReminderMinutesKey) ?? defaultCourseReminderMinutes;
    return value
        .clamp(
          minCourseReminderMinutes,
          maxCourseReminderMinutes,
        )
        .toInt();
  }

  static Future<void> setCourseReminderMinutes(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final safeValue = value
        .clamp(
          minCourseReminderMinutes,
          maxCourseReminderMinutes,
        )
        .toInt();
    await prefs.setInt(_courseReminderMinutesKey, safeValue);
  }

  /// 取消所有已注册的课程提醒（关闭开关时调用）
  /// 使用 cancelAll() 一次清空，比逐个 cancel 更高效
  static Future<void> cancelAllClassReminders() async {
    debugPrint('[NOTIF] cancelAllClassReminders: 清空所有课程通知调度...');
    await _plugin.cancelAll();
    debugPrint('[NOTIF] cancelAllClassReminders: 完成');
  }
}
