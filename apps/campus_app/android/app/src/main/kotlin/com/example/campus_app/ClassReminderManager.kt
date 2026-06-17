package com.example.campus_app

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import java.util.Locale

object ClassReminderManager {
    private const val PREFS_NAME = "campus_class_reminders"
    private const val REMINDERS_KEY = "reminders_json"
    private const val CHANNEL_ID = "class_reminder_native_v1"
    private const val CHANNEL_NAME = "课程动态提醒"
    private const val ACTION_SHOW = "com.example.campus_app.CLASS_REMINDER_SHOW"
    private const val ACTION_CANCEL = "com.example.campus_app.CLASS_REMINDER_CANCEL"
    private const val EXTRA_ID = "class_reminder_id"
    private const val SHOW_REQUEST_OFFSET = 1_000_000
    private const val CANCEL_REQUEST_OFFSET = 2_000_000

    fun scheduleFromFlutter(context: Context, rawReminders: List<Map<String, Any?>>) {
        val now = System.currentTimeMillis()
        val reminders = rawReminders
            .map { ClassReminder.fromMap(it) }
            .filter { it.classStartAtMillis > now }

        cancelAll(context)
        saveReminders(context, reminders)
        reminders.forEach { scheduleReminder(context, it) }
    }

    fun cancelAll(context: Context) {
        val reminders = readReminders(context)
        val notificationManager = NotificationManagerCompat.from(context)
        reminders.forEach { reminder ->
            cancelAlarm(context, reminder, ACTION_SHOW)
            cancelAlarm(context, reminder, ACTION_CANCEL)
            notificationManager.cancel(reminder.id)
        }
        prefs(context).edit().remove(REMINDERS_KEY).apply()
    }

    fun restoreScheduledReminders(context: Context) {
        val now = System.currentTimeMillis()
        val reminders = readReminders(context)
            .filter { it.classStartAtMillis > now }

        saveReminders(context, reminders)
        reminders.forEach { scheduleReminder(context, it) }
    }

    fun handleReceiverIntent(context: Context, intent: Intent?) {
        val id = intent?.getIntExtra(EXTRA_ID, -1) ?: -1
        if (id < 0) return

        when (intent?.action) {
            ACTION_SHOW -> showReminder(context, id)
            ACTION_CANCEL -> cancelReminder(context, id, pruneExpired = true)
        }
    }

    fun getCapabilities(context: Context): Map<String, Any?> = mapOf(
        "isAndroid" to true,
        "sdkInt" to Build.VERSION.SDK_INT,
        "manufacturer" to Build.MANUFACTURER.orEmpty(),
        "supportsPromotedOngoing" to (Build.VERSION.SDK_INT >= 36),
        "canPostNotifications" to canPostNotifications(context),
        "canPostPromotedNotifications" to canPostPromotedNotifications(context),
        "canScheduleExactAlarms" to canScheduleExactAlarms(context),
    )

    private fun scheduleReminder(context: Context, reminder: ClassReminder) {
        val now = System.currentTimeMillis()
        if (reminder.remindAtMillis <= now) {
            showReminder(context, reminder.id)
        } else {
            scheduleAlarm(context, reminder, ACTION_SHOW, reminder.remindAtMillis)
        }

        if (reminder.classStartAtMillis > now) {
            scheduleAlarm(context, reminder, ACTION_CANCEL, reminder.classStartAtMillis)
        }
    }

    @SuppressLint("ScheduleExactAlarm")
    private fun scheduleAlarm(
        context: Context,
        reminder: ClassReminder,
        action: String,
        triggerAtMillis: Long,
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = pendingIntentFor(context, reminder, action, PendingIntent.FLAG_UPDATE_CURRENT)
        val triggerAt = triggerAtMillis.coerceAtLeast(System.currentTimeMillis() + 1000L)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    private fun cancelAlarm(context: Context, reminder: ClassReminder, action: String) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntentFor(context, reminder, action, PendingIntent.FLAG_UPDATE_CURRENT))
    }

    private fun pendingIntentFor(
        context: Context,
        reminder: ClassReminder,
        action: String,
        baseFlags: Int,
    ): PendingIntent {
        val requestCode = when (action) {
            ACTION_SHOW -> SHOW_REQUEST_OFFSET + reminder.id
            else -> CANCEL_REQUEST_OFFSET + reminder.id
        }
        val flags = baseFlags or immutableFlag()
        val intent = Intent(context, ClassReminderReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_ID, reminder.id)
            data = Uri.parse("campus://class-reminder/$action/${reminder.id}")
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun showReminder(context: Context, reminderId: Int) {
        val reminder = readReminders(context).firstOrNull { it.id == reminderId } ?: return
        val now = System.currentTimeMillis()
        if (reminder.classStartAtMillis <= now) {
            cancelReminder(context, reminder.id, pruneExpired = true)
            return
        }

        ensureChannel(context)

        val title = buildNativeIslandTitle(reminder)
        val body = buildNotificationBody(reminder)
        val launchPendingIntent = PendingIntent.getActivity(
            context,
            reminder.id,
            launchIntent(context),
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_class_reminder_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setSubText(if (reminder.isExam) "考试提醒" else "上课提醒")
            .setTicker(title)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(buildExpandedNotificationText(reminder))
                    .setBigContentTitle(buildDetailTitle(reminder))
                    .setSummaryText(if (reminder.isExam) "考试提醒" else "上课提醒"),
            )
            .setContentIntent(launchPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(Color.rgb(25, 118, 210))
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(reminder.classStartAtMillis)
            .setShortCriticalText(buildNativeIslandTitle(reminder))
            .setTimeoutAfter(reminder.classStartAtMillis - now)
            .setRequestPromotedOngoing(true)

        if (!canPostNotifications(context)) return

        try {
            NotificationManagerCompat.from(context).notify(reminder.id, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS may have been revoked after scheduling.
        }
    }

    private fun cancelReminder(context: Context, reminderId: Int, pruneExpired: Boolean) {
        NotificationManagerCompat.from(context).cancel(reminderId)
        if (pruneExpired) {
            val now = System.currentTimeMillis()
            saveReminders(context, readReminders(context).filter { it.classStartAtMillis > now })
        }
    }

    private fun buildNotificationBody(reminder: ClassReminder): String {
        val course = if (reminder.isExam) {
            reminder.courseName.trim().ifBlank { "考试" }
        } else {
            compactCourseName(reminder.courseName, maxChars = 8)
        }
        val classroom = reminder.classroom.ifBlank { "教室待确认" }
        return "$course · ${formatTimeAndRoom(reminder.timeText, classroom, reminder.seatNumber, reminder.isExam)}"
    }

    private fun buildExpandedNotificationText(reminder: ClassReminder): String {
        val classroom = reminder.classroom.ifBlank { "教室待确认" }
        val teacher = if (reminder.isExam) "" else formatTeacher(reminder.teacher)
        val weekday = weekdayLabel(reminder.weekday)
        val lines = mutableListOf(
            formatTimeAndRoom(reminder.timeText, classroom, reminder.seatNumber, reminder.isExam),
            "周次  第 ${reminder.week} 周 · $weekday",
        )
        if (teacher.isNotBlank()) lines.add("教师  $teacher")
        return lines.joinToString("\n")
    }

    private fun buildDetailTitle(reminder: ClassReminder): String =
        reminder.courseName.trim().ifBlank { "课程待确认" }

    private fun buildNativeIslandTitle(reminder: ClassReminder): String {
        val time = compactTime(reminder.timeText)
        val classroom = compactClassroom(reminder.classroom)
        val seat = if (reminder.isExam) compactSeat(reminder.seatNumber) else ""
        val compactRoomAndTime = listOf(classroom, seat, time)
            .filter { it.isNotBlank() }
            .joinToString(" ")
        if (compactRoomAndTime.isNotBlank()) return compactRoomAndTime

        return compactCourseName(reminder.courseName, maxChars = 4)
    }

    private fun compactTime(timeText: String): String {
        val trimmed = timeText.trim()
        return trimmed.replace(Regex("^0(?=\\d:)"), "").ifBlank { "上课" }
    }

    private fun formatTimeAndRoom(
        timeText: String,
        classroom: String,
        seatNumber: String,
        isExam: Boolean,
    ): String {
        val time = timeText.ifBlank { "待确认" }
        val room = classroom.ifBlank { "教室待确认" }
        val seat = compactSeat(seatNumber)
        return listOf("$time ${if (isExam) "考试" else "上课"}", room, seat)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
    }

    private fun compactClassroom(classroom: String): String {
        val trimmed = classroom.trim()
        if (trimmed.isBlank()) return "教室待确认"

        Regex("[A-Za-z]\\d{4,5}")
            .find(trimmed)
            ?.value
            ?.uppercase(Locale.ROOT)
            ?.let { return it }

        val withoutCampus = trimmed
            .replace("科学城校区", "")
            .replace("南岸校区", "")
            .trim()
        return if (withoutCampus.length <= 6) withoutCampus else withoutCampus.take(6) + "…"
    }

    private fun compactSeat(seatNumber: String): String {
        val seat = seatNumber.trim()
        if (seat.isBlank() || seat == "-") return ""
        return if (seat.contains("座")) seat else "座位$seat"
    }

    private fun compactCourseName(courseName: String, maxChars: Int): String {
        val original = courseName.trim()
        if (original.isBlank()) return "课程"

        val normalized = original
            .replace("（", "(")
            .replace("）", ")")
            .replace(Regex("\\s+"), "")
        val withoutGroup = normalized.replace(Regex("\\([^)]*\\)"), "")
        val compact = withoutGroup
            .replace("概率论与数理统计", "概统")
            .replace("马克思主义基本原理", "马原")
            .replace("数字电子技术", "数电")
            .replace("WEB前端设计", "Web前端")
            .replace("数据库原理", "数据库")
            .replace("形势与政策", "形势政策")
            .replace("大学体育", "体育")

        if (compact.length <= maxChars) return compact

        val suffix = compact.lastOrNull()?.takeIf { it.isLetterOrDigit() }?.toString().orEmpty()
        val bodyMaxChars = (maxChars - suffix.length - 1).coerceAtLeast(2)
        return compact.take(bodyMaxChars) + "…" + suffix
    }

    private fun formatTeacher(teacher: String): String =
        teacher
            .trim()
            .replace("★", " · ")
            .replace("（高校）", "")
            .replace("(高校)", "")
            .replace(Regex("\\s+"), " ")

    private fun weekdayLabel(weekday: Int): String = when (weekday) {
        1 -> "周一"
        2 -> "周二"
        3 -> "周三"
        4 -> "周四"
        5 -> "周五"
        6 -> "周六"
        7 -> "周日"
        else -> "周$weekday"
    }

    private fun canScheduleExactAlarms(context: Context): Boolean {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
    }

    private fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return NotificationManagerCompat.from(context).areNotificationsEnabled()
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun canPostPromotedNotifications(context: Context): Boolean? = try {
        val manager = NotificationManagerCompat.from(context)
        val method = manager.javaClass.getMethod("canPostPromotedNotifications")
        method.invoke(manager) as? Boolean
    } catch (_: Exception) {
        null
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "课前提醒与类灵动岛状态"
            enableVibration(true)
            enableLights(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun launchIntent(context: Context): Intent {
        return context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        } ?: Intent(context, MainActivity::class.java)
    }

    private fun readReminders(context: Context): List<ClassReminder> {
        val json = prefs(context).getString(REMINDERS_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) {
                    add(ClassReminder.fromJson(array.getJSONObject(index)))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveReminders(context: Context, reminders: List<ClassReminder>) {
        val array = JSONArray()
        reminders.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(REMINDERS_KEY, array.toString()).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}
