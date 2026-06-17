import 'package:core/models/course.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../src/class_reminder_schedule.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _classReminderChannel = MethodChannel(
    'campus_app/class_reminder',
  );

  static const _elecThresholdKey = 'elec_threshold';
  static const _cardThresholdKey = 'card_threshold';
  static const _courseReminderKey = 'course_reminder';
  static const _courseReminderMinutesKey = 'course_reminder_minutes';
  static const _legacyClassReminderCleanupKey =
      'class_reminder_legacy_plugin_cleanup_done';

  static const double defaultElecThreshold = 10.0;
  static const double defaultCardThreshold = 20.0;
  static const bool defaultCourseReminder = true;
  static const int defaultCourseReminderMinutes = 15;
  static const int minCourseReminderMinutes = 15;
  static const int maxCourseReminderMinutes = 60;

  static const double defaultThreshold = defaultElecThreshold;

  static const _classChannelId = 'class_reminder_v2';
  static const _classChannelName = '上课提醒';
  static const _elecChannelId = 'elec_alert_v2';
  static const _cardChannelId = 'card_alert_v2';

  static Future<void> init() async {
    debugPrint('[NOTIF] init() start');
    tz.initializeTimeZones();

    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    debugPrint('[NOTIF] timezone initialized: ${tzInfo.identifier}');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

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

    final notifGranted =
        await androidPlugin?.requestNotificationsPermission() ?? false;
    debugPrint('[NOTIF] notification permission: $notifGranted');

    final alarmGranted =
        await androidPlugin?.requestExactAlarmsPermission() ?? false;
    debugPrint('[NOTIF] exact alarm permission: $alarmGranted');
  }

  static Future<void> scheduleClassReminders(
    List<Course> courses,
    DateTime semesterStart, {
    int totalWeeks = 20,
  }) async {
    final isReminderEnabled = await getCourseReminderEnabled();
    final reminderMinutes = await getCourseReminderMinutes();
    final reminders = buildClassReminders(
      courses: courses,
      semesterStart: semesterStart,
      now: DateTime.now(),
      reminderMinutes: reminderMinutes,
      totalWeeks: totalWeeks,
      includeActiveReminders: _usesNativeAndroidClassReminders,
    );

    debugPrint(
      '[NOTIF] scheduleClassReminders enabled=$isReminderEnabled '
      'minutes=$reminderMinutes reminders=${reminders.length}',
    );

    if (!isReminderEnabled) {
      await cancelAllClassReminders();
      return;
    }

    if (_usesNativeAndroidClassReminders) {
      try {
        await _scheduleNativeAndroidClassReminders(reminders);
        await _cleanupLegacyPluginClassRemindersOnce();
        return;
      } catch (error, stackTrace) {
        debugPrint('[NOTIF] native class reminder scheduling failed: $error');
        debugPrint('$stackTrace');
      }
    }

    await _schedulePluginClassReminders(reminders, reminderMinutes);
  }

  static bool get _usesNativeAndroidClassReminders =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, Object?>> getLiveReminderCapabilities() async {
    if (!_usesNativeAndroidClassReminders) {
      return const {'isAndroid': false};
    }

    try {
      final result =
          await _classReminderChannel.invokeMapMethod<String, Object?>(
        'getLiveReminderCapabilities',
      );
      return result ?? const {'isAndroid': true};
    } catch (error) {
      debugPrint('[NOTIF] getLiveReminderCapabilities failed: $error');
      return const {'isAndroid': true, 'error': true};
    }
  }

  static Future<void> _scheduleNativeAndroidClassReminders(
    List<ClassReminder> reminders,
  ) async {
    await _classReminderChannel.invokeMethod<void>(
      'scheduleClassReminders',
      {
        'reminders': reminders.map((r) => r.toPlatformMap()).toList(),
      },
    );
  }

  static Future<void> _cancelNativeAndroidClassReminders() async {
    await _classReminderChannel.invokeMethod<void>('cancelClassReminders');
  }

  static Future<void> _schedulePluginClassReminders(
    List<ClassReminder> reminders,
    int reminderMinutes,
  ) async {
    if (_usesNativeAndroidClassReminders) {
      await _cancelLegacyPluginClassReminderIds();
    } else {
      await _plugin.cancelAll();
    }

    for (final reminder in reminders) {
      final tzRemindTime = tz.TZDateTime.from(reminder.remindAt, tz.local);
      final titlePrefix = reminder.isExam ? '考试提醒' : '上课提醒';
      final actionText = reminder.isExam ? '考试' : '上课';
      final seatText = reminder.isExam && reminder.seatNumber.trim().isNotEmpty
          ? '，座位号 ${reminder.seatNumber.trim()}'
          : '';
      await _plugin.zonedSchedule(
        reminder.id,
        '$titlePrefix：${reminder.courseName}',
        '将在 $reminderMinutes 分钟后（${reminder.timeText}）在 ${reminder.classroom} $actionText$seatText',
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
            vibrationPattern: Int64List.fromList([0, 200, 200, 400, 200, 400]),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> _cleanupLegacyPluginClassRemindersOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyClassReminderCleanupKey) ?? false) return;

    await _cancelLegacyPluginClassReminderIds();
    await prefs.setBool(_legacyClassReminderCleanupKey, true);
  }

  static Future<void> _cancelLegacyPluginClassReminderIds() async {
    for (var week = 1; week <= 20; week++) {
      for (var weekday = 1; weekday <= 7; weekday++) {
        for (final timeSlot in classSlotStartTimes.keys) {
          await _plugin.cancel(week * 1000 + weekday * 100 + timeSlot);
        }
      }
    }
  }

  static Future<void> checkAndNotify(String balanceStr) async {
    final match = RegExp(r'-?[\d.]+').firstMatch(balanceStr);
    if (match == null) return;
    final balance = double.tryParse(match.group(0)!);
    if (balance == null) return;

    final threshold = await getElecThreshold();
    if (threshold <= 0 || balance >= threshold) return;

    await _plugin.show(
      1,
      '电费不足提醒',
      '寝室剩余电费 ¥$balanceStr，已低于 ¥${threshold.toStringAsFixed(0)}，请及时充值。',
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

  static Future<double> getElecThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_elecThresholdKey) ?? defaultElecThreshold;
  }

  static Future<void> setElecThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_elecThresholdKey, value);
  }

  static Future<double> getThreshold() => getElecThreshold();
  static Future<void> setThreshold(double value) => setElecThreshold(value);

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

  static Future<void> cancelAllClassReminders() async {
    debugPrint('[NOTIF] cancelAllClassReminders');

    if (_usesNativeAndroidClassReminders) {
      try {
        await _cancelNativeAndroidClassReminders();
      } catch (error) {
        debugPrint('[NOTIF] native class reminder cancel failed: $error');
      }
      await _cancelLegacyPluginClassReminderIds();
      return;
    }

    await _plugin.cancelAll();
  }
}
