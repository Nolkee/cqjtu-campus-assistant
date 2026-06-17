package com.example.campus_app

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

object ScheduleWidgetManager {
    const val ACTION_REFRESH = "com.example.campus_app.SCHEDULE_WIDGET_REFRESH"

    private const val PREFS_NAME = "campus_schedule_widgets"
    private const val SCHEDULE_KEY = "schedule_json"
    private const val DEFAULT_TOTAL_WEEKS = 20
    private const val MIN_TOTAL_WEEKS = 12
    private const val MAX_TOTAL_WEEKS = 30
    private const val REFRESH_REQUEST_CODE = 43_210

    private val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
    private val slotTimes = mapOf(
        1 to (LocalTime.of(8, 20) to LocalTime.of(9, 0)),
        2 to (LocalTime.of(9, 5) to LocalTime.of(9, 45)),
        3 to (LocalTime.of(10, 0) to LocalTime.of(10, 40)),
        4 to (LocalTime.of(10, 45) to LocalTime.of(11, 25)),
        5 to (LocalTime.of(11, 30) to LocalTime.of(12, 10)),
        6 to (LocalTime.of(14, 0) to LocalTime.of(14, 40)),
        7 to (LocalTime.of(14, 45) to LocalTime.of(15, 25)),
        8 to (LocalTime.of(15, 40) to LocalTime.of(16, 20)),
        9 to (LocalTime.of(16, 25) to LocalTime.of(17, 5)),
        10 to (LocalTime.of(17, 10) to LocalTime.of(17, 50)),
        11 to (LocalTime.of(19, 0) to LocalTime.of(19, 40)),
        12 to (LocalTime.of(19, 45) to LocalTime.of(20, 25)),
        13 to (LocalTime.of(20, 30) to LocalTime.of(21, 10)),
    )

    fun updateFromFlutter(
        context: Context,
        rawCourses: List<Map<String, Any?>>,
        semesterStartMillis: Long,
        selectedSemester: String?,
        remark: String,
        totalWeeks: Int,
    ) {
        val courses = rawCourses.mapNotNull { ScheduleWidgetCourse.fromMap(it) }
        val cache = ScheduleWidgetCache(
            courses = courses,
            semesterStartMillis = semesterStartMillis,
            selectedSemester = selectedSemester,
            remark = remark,
            totalWeeks = normalizeTotalWeeks(totalWeeks),
            campusCardBalance = readCache(context)?.campusCardBalance,
            electricityBalance = readCache(context)?.electricityBalance,
            updatedAtMillis = System.currentTimeMillis(),
        )
        saveCache(context, cache)
        refreshAllWidgets(context)
    }

    fun updateBalances(
        context: Context,
        campusCardBalance: String?,
        electricityBalance: String?,
    ) {
        val existing = readCache(context)
        val cache = existing?.copy(
            campusCardBalance = campusCardBalance?.takeIf { it.isNotBlank() }
                ?: existing.campusCardBalance,
            electricityBalance = electricityBalance?.takeIf { it.isNotBlank() }
                ?: existing.electricityBalance,
            updatedAtMillis = System.currentTimeMillis(),
        ) ?: ScheduleWidgetCache(
            courses = emptyList(),
            semesterStartMillis = 0L,
            selectedSemester = null,
            remark = "",
            totalWeeks = DEFAULT_TOTAL_WEEKS,
            campusCardBalance = campusCardBalance?.takeIf { it.isNotBlank() },
            electricityBalance = electricityBalance?.takeIf { it.isNotBlank() },
            updatedAtMillis = System.currentTimeMillis(),
        )
        saveCache(context, cache)
        refreshAllWidgets(context)
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(SCHEDULE_KEY).apply()
        cancelRefreshAlarm(context)
        refreshAllWidgets(context)
    }

    fun refreshAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val cache = readCache(context)
        val snapshot = cache?.takeIf { it.hasSchedule }?.let {
            buildSnapshot(it, System.currentTimeMillis(), ZoneId.systemDefault())
        }

        updateNextClassWidgets(context, manager, snapshot)
        updateTodayScheduleWidgets(context, manager, snapshot, cache)

        if (cache == null || !hasAnyWidget(context, manager)) {
            cancelRefreshAlarm(context)
        } else {
            scheduleNextRefresh(context, cache)
        }
    }

    private fun updateNextClassWidgets(
        context: Context,
        manager: AppWidgetManager,
        snapshot: ScheduleWidgetSnapshot?,
    ) {
        val ids = widgetIds(context, manager, NextClassWidgetProvider::class.java)
        if (ids.isEmpty()) return

        val views = RemoteViews(context.packageName, R.layout.widget_next_class)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            launchPendingIntent(context, 10_001, "schedule"),
        )

        if (snapshot == null) {
            renderNextEmpty(views)
            manager.updateAppWidget(ids, views)
            return
        }

        val next = snapshot.nextClass
        val occurrence = next.occurrence
        val isExam = occurrence?.course?.isExam == true
        val statusText = when (next.status) {
            NextClassStatus.CURRENT -> if (isExam) "正在考试" else "正在上课"
            NextClassStatus.NEXT -> if (occurrence?.isToday == false) {
                "${if (isExam) "下一场考试" else "下一节课"} · ${weekdayLabel(occurrence.startAtDate)}"
            } else {
                if (isExam) "下一场考试" else "下一节课"
            }
            NextClassStatus.TODAY_DONE -> "今日课程已结束"
            NextClassStatus.TODAY_EMPTY -> "今日无课"
            NextClassStatus.BEFORE_SEMESTER -> "学期还没开始"
            NextClassStatus.SEMESTER_DONE -> "本学期已结束"
        }

        views.setTextViewText(R.id.widget_next_status, statusText)
        views.setTextViewText(R.id.widget_next_week, weekLabel(snapshot.currentWeek, snapshot.totalWeeks))

        if (occurrence == null) {
            views.setTextViewText(
                R.id.widget_next_course,
                when (next.status) {
                    NextClassStatus.TODAY_DONE -> "今天的课已经全部结束"
                    NextClassStatus.TODAY_EMPTY -> "今天没有课程安排"
                    NextClassStatus.BEFORE_SEMESTER -> "等待学期开始"
                    NextClassStatus.SEMESTER_DONE -> "可以准备下一学期课表"
                    else -> "打开 CQJTU Hub 刷新课表"
                },
            )
            views.setViewVisibility(R.id.widget_next_meta_row, View.GONE)
            views.setViewVisibility(R.id.widget_next_teacher, View.GONE)
            views.setInt(
                R.id.widget_next_status,
                "setBackgroundResource",
                R.drawable.widget_status_neutral,
            )
            manager.updateAppWidget(ids, views)
            return
        }

        val course = occurrence.course
        val room = formatPlace(course)
        val teacher = if (course.isExam) "" else formatTeacher(course.teacher)

        views.setTextViewText(R.id.widget_next_course, fullCourseName(course.name))
        views.setViewVisibility(R.id.widget_next_meta_row, View.VISIBLE)
        views.setTextViewText(R.id.widget_next_time, occurrence.timeRange)
        views.setTextViewText(R.id.widget_next_room, room.ifBlank { "教室待确认" })
        views.setViewVisibility(
            R.id.widget_next_teacher,
            if (teacher.isBlank()) View.GONE else View.VISIBLE,
        )
        views.setTextViewText(R.id.widget_next_teacher, teacher)
        views.setInt(
            R.id.widget_next_status,
            "setBackgroundResource",
            if (next.status == NextClassStatus.CURRENT) {
                R.drawable.widget_status_current
            } else {
                R.drawable.widget_status_next
            },
        )
        manager.updateAppWidget(ids, views)
    }

    private fun renderNextEmpty(views: RemoteViews) {
        views.setTextViewText(R.id.widget_next_status, "未同步")
        views.setTextViewText(R.id.widget_next_week, "课程表")
        views.setTextViewText(R.id.widget_next_course, "打开 CQJTU Hub 刷新课表")
        views.setViewVisibility(R.id.widget_next_meta_row, View.GONE)
        views.setViewVisibility(R.id.widget_next_teacher, View.GONE)
        views.setInt(
            R.id.widget_next_status,
            "setBackgroundResource",
            R.drawable.widget_status_neutral,
        )
    }

    private fun updateTodayScheduleWidgets(
        context: Context,
        manager: AppWidgetManager,
        snapshot: ScheduleWidgetSnapshot?,
        cache: ScheduleWidgetCache?,
    ) {
        val ids = widgetIds(context, manager, TodayScheduleWidgetProvider::class.java)
        if (ids.isEmpty()) return

        val views = RemoteViews(context.packageName, R.layout.widget_today_schedule)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            launchPendingIntent(context, 10_002, "schedule"),
        )
        views.setOnClickPendingIntent(
            R.id.widget_action_card,
            launchPendingIntent(context, 10_003, "campus_card_qr"),
        )
        views.setOnClickPendingIntent(
            R.id.widget_action_electricity,
            launchPendingIntent(context, 10_004, "electricity"),
        )
        renderActionBar(views, cache)

        if (snapshot == null) {
            views.setTextViewText(R.id.widget_today_title, "今日课表")
            views.setTextViewText(R.id.widget_today_count, "未同步")
            renderTodayRows(views, emptyList())
            views.setViewVisibility(R.id.widget_today_empty, View.VISIBLE)
            views.setTextViewText(R.id.widget_today_empty, "打开 CQJTU Hub 刷新课表")
            manager.updateAppWidget(ids, views)
            return
        }

        val courses = snapshot.todayCourses
        views.setTextViewText(R.id.widget_today_title, "今日课表 · ${weekLabel(snapshot.currentWeek, snapshot.totalWeeks)}")
        views.setTextViewText(
            R.id.widget_today_count,
            if (courses.isEmpty()) "无课" else "共 ${courses.size} 节",
        )
        renderTodayRows(views, courses)
        views.setViewVisibility(
            R.id.widget_today_empty,
            if (courses.isEmpty()) View.VISIBLE else View.GONE,
        )
        views.setTextViewText(R.id.widget_today_empty, "今日无课")
        val hiddenCount = (courses.size - 3).coerceAtLeast(0)
        views.setViewVisibility(
            R.id.widget_today_more,
            if (hiddenCount > 0) View.VISIBLE else View.GONE,
        )
        views.setTextViewText(R.id.widget_today_more, "还有 $hiddenCount 节")
        manager.updateAppWidget(ids, views)
    }

    private fun renderActionBar(
        views: RemoteViews,
        cache: ScheduleWidgetCache?,
    ) {
        views.setTextViewText(
            R.id.widget_action_card_balance,
            formatBalance(cache?.campusCardBalance, "校园卡"),
        )
        views.setTextViewText(
            R.id.widget_action_electricity_balance,
            formatBalance(cache?.electricityBalance, "电费"),
        )
    }

    private fun renderTodayRows(
        views: RemoteViews,
        courses: List<ScheduleWidgetOccurrence>,
    ) {
        val now = Instant.now()
        // Reorder: ongoing/upcoming first, finished courses sink to bottom
        val ordered = courses.sortedWith(
            compareBy<ScheduleWidgetOccurrence> { it.isEndedAt(now) }
                .thenBy { it.startAt }
        )
        val rows = listOf(
            WidgetRowIds(
                R.id.widget_today_row_1,
                R.id.widget_today_accent_1,
                R.id.widget_today_time_1,
                R.id.widget_today_course_1,
                R.id.widget_today_meta_1,
            ),
            WidgetRowIds(
                R.id.widget_today_row_2,
                R.id.widget_today_accent_2,
                R.id.widget_today_time_2,
                R.id.widget_today_course_2,
                R.id.widget_today_meta_2,
            ),
            WidgetRowIds(
                R.id.widget_today_row_3,
                R.id.widget_today_accent_3,
                R.id.widget_today_time_3,
                R.id.widget_today_course_3,
                R.id.widget_today_meta_3,
            ),
            WidgetRowIds(
                R.id.widget_today_row_4,
                R.id.widget_today_accent_4,
                R.id.widget_today_time_4,
                R.id.widget_today_course_4,
                R.id.widget_today_meta_4,
            ),
        )

        rows.forEachIndexed { index, row ->
            val occurrence = ordered.take(3).getOrNull(index)
            if (occurrence == null) {
                views.setViewVisibility(row.rootId, View.GONE)
                return@forEachIndexed
            }

            val isCurrent = occurrence.isCurrentAt(now)
            val isEnded = occurrence.isEndedAt(now)
            val room = formatPlace(occurrence.course)

            views.setViewVisibility(row.rootId, View.VISIBLE)
            views.setTextViewText(row.timeId, occurrence.startText)
            views.setTextViewText(row.courseId, fullCourseName(occurrence.course.name))
            views.setTextViewText(row.metaId, room.ifBlank { "教室待确认" })
            views.setInt(
                row.rootId,
                "setBackgroundResource",
                if (isCurrent) R.drawable.widget_today_row_current else R.drawable.widget_today_row_normal,
            )
            views.setInt(
                row.accentId,
                "setBackgroundResource",
                if (isCurrent) {
                    R.drawable.widget_accent_current
                } else if (isEnded) {
                    R.drawable.widget_accent_ended
                } else {
                    R.drawable.widget_accent_next
                },
            )
            val primaryColor = when {
                isCurrent -> 0xFF0F4C81.toInt()
                isEnded -> 0xFF94A3B8.toInt()
                else -> 0xFF263241.toInt()
            }
            val secondaryColor = when {
                isCurrent -> 0xFF2563EB.toInt()
                isEnded -> 0xFFA8B1BD.toInt()
                else -> 0xFF6B7280.toInt()
            }
            views.setTextColor(row.timeId, secondaryColor)
            views.setTextColor(row.courseId, primaryColor)
            views.setTextColor(row.metaId, secondaryColor)
        }
    }

    private fun buildSnapshot(
        cache: ScheduleWidgetCache,
        nowMillis: Long,
        zone: ZoneId,
    ): ScheduleWidgetSnapshot {
        val now = Instant.ofEpochMilli(nowMillis)
        val today = now.atZone(zone).toLocalDate()
        val totalWeeks = cache.totalWeeks
        val currentWeek = calculateCurrentWeek(cache.semesterStartMillis, nowMillis, zone, totalWeeks)
        val todayCourses = occurrencesForDay(cache.courses, currentWeek, today, zone, totalWeeks)
        val current = todayCourses.firstOrNull { it.isCurrentAt(now) }
        if (current != null) {
            return ScheduleWidgetSnapshot(
                currentWeek = currentWeek,
                totalWeeks = totalWeeks,
                todayCourses = todayCourses,
                nextClass = NextClassState(NextClassStatus.CURRENT, current),
            )
        }

        val upcomingToday = todayCourses.firstOrNull { it.startAt.isAfter(now) }
        if (upcomingToday != null) {
            return ScheduleWidgetSnapshot(
                currentWeek = currentWeek,
                totalWeeks = totalWeeks,
                todayCourses = todayCourses,
                nextClass = NextClassState(NextClassStatus.NEXT, upcomingToday),
            )
        }

        val nextOccurrence = futureOccurrences(cache.courses, cache.semesterStartMillis, now, zone, totalWeeks)
            .firstOrNull()
        val status = when {
            currentWeek == 0 && nextOccurrence != null -> NextClassStatus.NEXT
            currentWeek == 0 -> NextClassStatus.BEFORE_SEMESTER
            currentWeek > totalWeeks -> NextClassStatus.SEMESTER_DONE
            todayCourses.isEmpty() -> NextClassStatus.TODAY_EMPTY
            else -> NextClassStatus.TODAY_DONE
        }
        return ScheduleWidgetSnapshot(
            currentWeek = currentWeek,
            totalWeeks = totalWeeks,
            todayCourses = todayCourses,
            nextClass = NextClassState(
                status,
                if (status == NextClassStatus.NEXT) nextOccurrence else null,
            ),
        )
    }

    private fun futureOccurrences(
        courses: List<ScheduleWidgetCourse>,
        semesterStartMillis: Long,
        now: Instant,
        zone: ZoneId,
        totalWeeks: Int,
    ): List<ScheduleWidgetOccurrence> {
        val currentWeek = calculateCurrentWeek(
            semesterStartMillis,
            now.toEpochMilli(),
            zone,
            totalWeeks,
        )
        val firstWeek = currentWeek.coerceAtLeast(1)
        val occurrences = mutableListOf<ScheduleWidgetOccurrence>()
        for (week in firstWeek..totalWeeks) {
            val weekStart = weekStartOf(semesterStartMillis, week, zone)
            for (dayOffset in 0L..6L) {
                occurrences.addAll(
                    occurrencesForDay(
                        courses,
                        week,
                        weekStart.plusDays(dayOffset),
                        zone,
                        totalWeeks,
                    ).filter { it.startAt.isAfter(now) },
                )
            }
        }
        return occurrences.sortedWith(occurrenceComparator)
    }

    private fun occurrencesForDay(
        courses: List<ScheduleWidgetCourse>,
        week: Int,
        date: LocalDate,
        zone: ZoneId,
        totalWeeks: Int,
    ): List<ScheduleWidgetOccurrence> {
        if (week < 1 || week > totalWeeks) return emptyList()
        val weekday = date.dayOfWeek.value
        return courses
            .filter { it.dayOfWeek == weekday && it.weekList.contains(week) }
            .mapNotNull { occurrenceForCourse(it, week, date, zone) }
            .sortedWith(occurrenceComparator)
    }

    private fun occurrenceForCourse(
        course: ScheduleWidgetCourse,
        week: Int,
        date: LocalDate,
        zone: ZoneId,
    ): ScheduleWidgetOccurrence? {
        val startSlot = slotTimes[course.timeSlot] ?: return null
        val endSlot = slotTimes[course.endTimeSlot] ?: startSlot
        val startAt = date.atTime(startSlot.first).atZone(zone).toInstant()
        val endAt = date.atTime(endSlot.second).atZone(zone).toInstant()
        val today = LocalDate.now(zone)
        return ScheduleWidgetOccurrence(
            course = course,
            week = week,
            startAt = startAt,
            endAt = endAt,
            startAtDate = date,
            startText = startSlot.first.format(timeFormatter),
            endText = endSlot.second.format(timeFormatter),
            isToday = date == today,
        )
    }

    private fun calculateCurrentWeek(
        semesterStartMillis: Long,
        nowMillis: Long,
        zone: ZoneId,
        totalWeeks: Int,
    ): Int {
        val semesterStart = Instant.ofEpochMilli(semesterStartMillis)
            .atZone(zone)
            .toLocalDate()
        val semesterMonday = semesterStart.minusDays((semesterStart.dayOfWeek.value - 1).toLong())
        val today = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        if (today.isBefore(semesterMonday)) return 0

        val week = (ChronoUnit.DAYS.between(semesterMonday, today) / 7L + 1L).toInt()
        return if (week > totalWeeks) totalWeeks + 1 else week
    }

    private fun weekStartOf(
        semesterStartMillis: Long,
        week: Int,
        zone: ZoneId,
    ): LocalDate {
        val semesterStart = Instant.ofEpochMilli(semesterStartMillis)
            .atZone(zone)
            .toLocalDate()
        val semesterMonday = semesterStart.minusDays((semesterStart.dayOfWeek.value - 1).toLong())
        return semesterMonday.plusDays((week - 1) * 7L)
    }

    @SuppressLint("ScheduleExactAlarm")
    private fun scheduleNextRefresh(context: Context, cache: ScheduleWidgetCache) {
        val manager = AppWidgetManager.getInstance(context)
        if (!hasAnyWidget(context, manager)) {
            cancelRefreshAlarm(context)
            return
        }

        val zone = ZoneId.systemDefault()
        val nowMillis = System.currentTimeMillis()
        val now = Instant.ofEpochMilli(nowMillis)
        val snapshot = buildSnapshot(cache, nowMillis, zone)
        val candidateTimes = mutableListOf<Long>()

        snapshot.todayCourses.forEach { occurrence ->
            if (occurrence.startAt.isAfter(now)) candidateTimes.add(occurrence.startAt.toEpochMilli())
            if (occurrence.endAt.isAfter(now)) candidateTimes.add(occurrence.endAt.toEpochMilli())
        }

        val tomorrowMorning = now.atZone(zone)
            .toLocalDate()
            .plusDays(1)
            .atTime(0, 5)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()
        candidateTimes.add(tomorrowMorning)

        val triggerAt = candidateTimes
            .filter { it > nowMillis + 60_000L }
            .minOrNull() ?: tomorrowMorning

        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = refreshPendingIntent(context, PendingIntent.FLAG_UPDATE_CURRENT)
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

    private fun cancelRefreshAlarm(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(refreshPendingIntent(context, PendingIntent.FLAG_UPDATE_CURRENT))
    }

    private fun refreshPendingIntent(context: Context, flags: Int): PendingIntent {
        val intent = Intent(context, ScheduleWidgetRefreshReceiver::class.java).apply {
            action = ACTION_REFRESH
            data = Uri.parse("campus://schedule-widget/refresh")
        }
        return PendingIntent.getBroadcast(
            context,
            REFRESH_REQUEST_CODE,
            intent,
            flags or immutableFlag(),
        )
    }

    private fun launchPendingIntent(
        context: Context,
        requestCode: Int,
        target: String,
    ): PendingIntent {
        return PendingIntent.getActivity(
            context,
            requestCode,
            launchIntent(context, target),
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
    }

    private fun launchIntent(context: Context, target: String): Intent {
        return context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("widget_target", target)
        } ?: Intent(context, MainActivity::class.java).apply {
            putExtra("widget_target", target)
        }
    }

    private fun widgetIds(
        context: Context,
        manager: AppWidgetManager,
        providerClass: Class<*>,
    ): IntArray = manager.getAppWidgetIds(ComponentName(context, providerClass))

    private fun hasAnyWidget(context: Context, manager: AppWidgetManager): Boolean =
        widgetIds(context, manager, NextClassWidgetProvider::class.java).isNotEmpty() ||
            widgetIds(context, manager, TodayScheduleWidgetProvider::class.java).isNotEmpty()

    private fun saveCache(context: Context, cache: ScheduleWidgetCache) {
        prefs(context).edit().putString(SCHEDULE_KEY, cache.toJson().toString()).apply()
    }

    private fun readCache(context: Context): ScheduleWidgetCache? {
        val raw = prefs(context).getString(SCHEDULE_KEY, null) ?: return null
        return try {
            ScheduleWidgetCache.fromJson(JSONObject(raw))
        } catch (_: Exception) {
            null
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun weekLabel(week: Int, totalWeeks: Int): String = when (week) {
        0 -> "开学前"
        totalWeeks + 1 -> "学期结束"
        else -> "第 $week 周"
    }

    private fun weekdayLabel(date: LocalDate): String = when (date.dayOfWeek.value) {
        1 -> "周一"
        2 -> "周二"
        3 -> "周三"
        4 -> "周四"
        5 -> "周五"
        6 -> "周六"
        else -> "周日"
    }

    private fun compactClassroom(classroom: String): String {
        val trimmed = classroom.trim()
        if (trimmed.isBlank()) return ""

        Regex("[A-Za-z]\\d{4,5}")
            .find(trimmed)
            ?.value
            ?.uppercase(Locale.ROOT)
            ?.let { return it }

        val withoutCampus = trimmed
            .replace("科学城校区", "")
            .replace("南岸校区", "")
            .replace("教学楼", "")
            .trim()
        return if (withoutCampus.length <= 8) withoutCampus else withoutCampus.take(8)
    }

    private fun formatPlace(course: ScheduleWidgetCourse): String {
        val room = compactClassroom(course.classroom)
        if (!course.isExam) return room

        val seat = course.seatNumber.trim().takeIf { it.isNotBlank() && it != "-" }
            ?: return room
        val normalizedSeat = seat.replace(Regex("\\s+"), "")
        val seatText = if (normalizedSeat.contains("座")) normalizedSeat else "座位$normalizedSeat"
        return listOf(room, seatText)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
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
            .replace("概率论与数理统计B", "概统B")
            .replace("马克思主义基本原理", "马原")
            .replace("数字电子技术", "数电")
            .replace("WEB前端设计", "Web前端")
            .replace("数据库原理", "数据库")
            .replace("形势与政策", "形势政策")
            .replace("大学体育", "体育")

        return if (compact.length <= maxChars) compact else compact.take(maxChars - 1) + "…"
    }

    private fun fullCourseName(courseName: String): String {
        return courseName
            .trim()
            .replace(Regex("\\s+"), "")
            .ifBlank { "课程" }
    }

    private fun formatTeacher(teacher: String): String {
        val normalized = teacher
            .trim()
            .replace("☼", " · ")
            .replace("（高校）", "")
            .replace("(高校)", "")
            .replace(Regex("\\s+"), " ")
        if (normalized.isBlank()) return ""
        return "教师 $normalized"
    }

    private fun formatBalance(balance: String?, fallbackLabel: String): String {
        val raw = balance?.trim().orEmpty()
        if (raw.isBlank()) return "未同步"

        val number = Regex("-?\\d+(?:\\.\\d+)?").find(raw)?.value
        if (number == null) return raw.take(8)

        return when {
            raw.contains("度") || raw.contains("电") -> "$number 度"
            raw.contains("元") || raw.contains("¥") || raw.contains("￥") || raw.contains("余额") -> "¥$number"
            fallbackLabel == "校园卡" -> "¥$number"
            else -> number
        }
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun normalizeTotalWeeks(value: Int): Int =
        value.coerceIn(MIN_TOTAL_WEEKS, MAX_TOTAL_WEEKS)

    private val occurrenceComparator = compareBy<ScheduleWidgetOccurrence>(
        { it.startAt },
        { it.endAt },
        { it.course.name },
        { it.course.classroom },
    )
}

private data class ScheduleWidgetCache(
    val courses: List<ScheduleWidgetCourse>,
    val semesterStartMillis: Long,
    val selectedSemester: String?,
    val remark: String,
    val totalWeeks: Int,
    val campusCardBalance: String?,
    val electricityBalance: String?,
    val updatedAtMillis: Long,
) {
    val hasSchedule: Boolean get() = semesterStartMillis > 0L && courses.isNotEmpty()

    fun toJson(): JSONObject = JSONObject().apply {
        put("semesterStartMillis", semesterStartMillis)
        put("selectedSemester", selectedSemester ?: JSONObject.NULL)
        put("remark", remark)
        put("totalWeeks", totalWeeks)
        put("campusCardBalance", campusCardBalance ?: JSONObject.NULL)
        put("electricityBalance", electricityBalance ?: JSONObject.NULL)
        put("updatedAtMillis", updatedAtMillis)
        put("courses", JSONArray().also { array ->
            courses.forEach { array.put(it.toJson()) }
        })
    }

    companion object {
        fun fromJson(json: JSONObject): ScheduleWidgetCache {
            val array = json.optJSONArray("courses") ?: JSONArray()
            val courses = buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    add(ScheduleWidgetCourse.fromJson(item))
                }
            }
            return ScheduleWidgetCache(
                courses = courses,
                semesterStartMillis = json.optLong("semesterStartMillis", 0L),
                selectedSemester = json.optString("selectedSemester").takeIf { it.isNotBlank() },
                remark = json.optString("remark"),
                totalWeeks = json.optInt("totalWeeks", 20).coerceIn(12, 30),
                campusCardBalance = json.optNullableString("campusCardBalance"),
                electricityBalance = json.optNullableString("electricityBalance"),
                updatedAtMillis = json.optLong("updatedAtMillis", 0L),
            )
        }
    }
}

private data class ScheduleWidgetCourse(
    val name: String,
    val teacher: String,
    val timeStr: String,
    val classroom: String,
    val dayOfWeek: Int,
    val timeSlot: Int,
    val endTimeSlot: Int,
    val weekList: Set<Int>,
    val isExam: Boolean,
    val isCustom: Boolean,
    val seatNumber: String,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("name", name)
        put("teacher", teacher)
        put("timeStr", timeStr)
        put("classroom", classroom)
        put("dayOfWeek", dayOfWeek)
        put("timeSlot", timeSlot)
        put("endTimeSlot", endTimeSlot)
        put("isExam", isExam)
        put("isCustom", isCustom)
        put("seatNumber", seatNumber)
        put("weekList", JSONArray().also { array ->
            weekList.sorted().forEach { array.put(it) }
        })
    }

    companion object {
        fun fromMap(map: Map<String, Any?>): ScheduleWidgetCourse? {
            val timeSlot = map["timeSlot"].toIntOrNull() ?: return null
            return ScheduleWidgetCourse(
                name = map["name"]?.toString().orEmpty(),
                teacher = map["teacher"]?.toString().orEmpty(),
                timeStr = map["timeStr"]?.toString().orEmpty(),
                classroom = map["classroom"]?.toString().orEmpty(),
                dayOfWeek = map["dayOfWeek"].toIntOrNull() ?: 1,
                timeSlot = timeSlot,
                endTimeSlot = map["endTimeSlot"].toIntOrNull() ?: timeSlot,
                weekList = map["weekList"].toIntSet(),
                isExam = map["isExam"].toBooleanValue(),
                isCustom = map["isCustom"].toBooleanValue(),
                seatNumber = map["seatNumber"]?.toString().orEmpty(),
            )
        }

        fun fromJson(json: JSONObject): ScheduleWidgetCourse {
            val timeSlot = json.optInt("timeSlot", 1)
            val weekArray = json.optJSONArray("weekList") ?: JSONArray()
            val weeks = buildSet {
                for (index in 0 until weekArray.length()) {
                    weekArray.optInt(index).takeIf { it > 0 }?.let { add(it) }
                }
            }
            return ScheduleWidgetCourse(
                name = json.optString("name"),
                teacher = json.optString("teacher"),
                timeStr = json.optString("timeStr"),
                classroom = json.optString("classroom"),
                dayOfWeek = json.optInt("dayOfWeek", 1),
                timeSlot = timeSlot,
                endTimeSlot = json.optInt("endTimeSlot", timeSlot),
                weekList = weeks,
                isExam = json.optBoolean("isExam", false),
                isCustom = json.optBoolean("isCustom", false),
                seatNumber = json.optString("seatNumber"),
            )
        }
    }
}

private data class ScheduleWidgetSnapshot(
    val currentWeek: Int,
    val totalWeeks: Int,
    val todayCourses: List<ScheduleWidgetOccurrence>,
    val nextClass: NextClassState,
)

private data class NextClassState(
    val status: NextClassStatus,
    val occurrence: ScheduleWidgetOccurrence?,
)

private enum class NextClassStatus {
    CURRENT,
    NEXT,
    TODAY_DONE,
    TODAY_EMPTY,
    BEFORE_SEMESTER,
    SEMESTER_DONE,
}

private data class ScheduleWidgetOccurrence(
    val course: ScheduleWidgetCourse,
    val week: Int,
    val startAt: Instant,
    val endAt: Instant,
    val startAtDate: LocalDate,
    val startText: String,
    val endText: String,
    val isToday: Boolean,
) {
    val timeRange: String get() = "$startText-$endText"

    fun isCurrentAt(now: Instant): Boolean =
        !now.isBefore(startAt) && now.isBefore(endAt)

    fun isEndedAt(now: Instant): Boolean = !endAt.isAfter(now)
}

private data class WidgetRowIds(
    val rootId: Int,
    val accentId: Int,
    val timeId: Int,
    val courseId: Int,
    val metaId: Int,
)

private fun Any?.toIntOrNull(): Int? = when (this) {
    is Number -> toInt()
    is String -> toIntOrNull()
    else -> null
}

private fun Any?.toIntSet(): Set<Int> = when (this) {
    is List<*> -> mapNotNull { it.toIntOrNull() }.toSet()
    is IntArray -> toSet()
    else -> emptySet()
}

private fun Any?.toBooleanValue(): Boolean = when (this) {
    is Boolean -> this
    is Number -> toInt() != 0
    is String -> trim().lowercase(Locale.ROOT).let { it == "true" || it == "1" }
    else -> false
}

private fun JSONObject.optNullableString(name: String): String? {
    if (!has(name) || isNull(name)) return null
    return optString(name).takeIf { it.isNotBlank() }
}
