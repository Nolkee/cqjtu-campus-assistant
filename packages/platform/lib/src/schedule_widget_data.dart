import 'package:core/models/course.dart';

enum NextClassWidgetStatus {
  noCache,
  beforeSemester,
  current,
  next,
  todayDone,
  todayEmpty,
  semesterDone,
}

class ScheduleWidgetOccurrence {
  const ScheduleWidgetOccurrence({
    required this.course,
    required this.week,
    required this.startAt,
    required this.endAt,
    required this.startText,
    required this.endText,
  });

  final Course course;
  final int week;
  final DateTime startAt;
  final DateTime endAt;
  final String startText;
  final String endText;

  String get timeRange => '$startText-$endText';

  bool isCurrentAt(DateTime now) =>
      !now.isBefore(startAt) && now.isBefore(endAt);

  bool isEndedAt(DateTime now) => !endAt.isAfter(now);
}

class NextClassWidgetState {
  const NextClassWidgetState({
    required this.status,
    this.occurrence,
  });

  final NextClassWidgetStatus status;
  final ScheduleWidgetOccurrence? occurrence;
}

class ScheduleWidgetSnapshot {
  const ScheduleWidgetSnapshot({
    required this.currentWeek,
    required this.todayCourses,
    required this.nextClass,
  });

  final int currentWeek;
  final List<ScheduleWidgetOccurrence> todayCourses;
  final NextClassWidgetState nextClass;
}

const Map<int, (String, String)> scheduleWidgetSlotTimes = {
  1: ('08:20', '09:00'),
  2: ('09:05', '09:45'),
  3: ('10:00', '10:40'),
  4: ('10:45', '11:25'),
  5: ('11:30', '12:10'),
  6: ('14:00', '14:40'),
  7: ('14:45', '15:25'),
  8: ('15:40', '16:20'),
  9: ('16:25', '17:05'),
  10: ('17:10', '17:50'),
  11: ('19:00', '19:40'),
  12: ('19:45', '20:25'),
  13: ('20:30', '21:10'),
};

int calculateScheduleWidgetWeek(
  DateTime semesterStart,
  DateTime now, {
  int totalWeeks = 20,
}) {
  final semesterMonday = _startOfDay(
    semesterStart,
  ).subtract(Duration(days: semesterStart.weekday - 1));
  final today = _startOfDay(now);
  if (today.isBefore(semesterMonday)) return 0;

  final week = today.difference(semesterMonday).inDays ~/ 7 + 1;
  if (week > totalWeeks) return totalWeeks + 1;
  return week;
}

ScheduleWidgetSnapshot buildScheduleWidgetSnapshot({
  required List<Course> courses,
  required DateTime semesterStart,
  required DateTime now,
  int totalWeeks = 20,
}) {
  final currentWeek = calculateScheduleWidgetWeek(
    semesterStart,
    now,
    totalWeeks: totalWeeks,
  );

  if (courses.isEmpty) {
    return ScheduleWidgetSnapshot(
      currentWeek: currentWeek,
      todayCourses: const [],
      nextClass: const NextClassWidgetState(
        status: NextClassWidgetStatus.noCache,
      ),
    );
  }

  final todayCourses = _occurrencesForDay(
    courses: courses,
    week: currentWeek,
    date: _startOfDay(now),
    totalWeeks: totalWeeks,
  );

  final current = todayCourses.where((o) => o.isCurrentAt(now)).toList();
  if (current.isNotEmpty) {
    return ScheduleWidgetSnapshot(
      currentWeek: currentWeek,
      todayCourses: todayCourses,
      nextClass: NextClassWidgetState(
        status: NextClassWidgetStatus.current,
        occurrence: current.first,
      ),
    );
  }

  final upcomingToday = todayCourses.where((o) => o.startAt.isAfter(now));
  if (upcomingToday.isNotEmpty) {
    return ScheduleWidgetSnapshot(
      currentWeek: currentWeek,
      todayCourses: todayCourses,
      nextClass: NextClassWidgetState(
        status: NextClassWidgetStatus.next,
        occurrence: upcomingToday.first,
      ),
    );
  }

  final futureOccurrences = _futureOccurrences(
    courses: courses,
    semesterStart: semesterStart,
    now: now,
    totalWeeks: totalWeeks,
  );
  final nextOccurrence =
      futureOccurrences.isEmpty ? null : futureOccurrences.first;

  final status = currentWeek == 0 && nextOccurrence != null
      ? NextClassWidgetStatus.next
      : currentWeek == 0
          ? NextClassWidgetStatus.beforeSemester
          : currentWeek > totalWeeks
              ? NextClassWidgetStatus.semesterDone
              : todayCourses.isEmpty
                  ? NextClassWidgetStatus.todayEmpty
                  : NextClassWidgetStatus.todayDone;

  return ScheduleWidgetSnapshot(
    currentWeek: currentWeek,
    todayCourses: todayCourses,
    nextClass: NextClassWidgetState(
      status: status,
      occurrence: status == NextClassWidgetStatus.next ? nextOccurrence : null,
    ),
  );
}

List<ScheduleWidgetOccurrence> _futureOccurrences({
  required List<Course> courses,
  required DateTime semesterStart,
  required DateTime now,
  required int totalWeeks,
}) {
  final currentWeek = calculateScheduleWidgetWeek(
    semesterStart,
    now,
    totalWeeks: totalWeeks,
  );
  final firstWeek = currentWeek <= 0 ? 1 : currentWeek;
  final occurrences = <ScheduleWidgetOccurrence>[];

  for (var week = firstWeek; week <= totalWeeks; week++) {
    final weekStart = _weekStartOf(semesterStart, week);
    for (var offset = 0; offset < 7; offset++) {
      occurrences.addAll(
        _occurrencesForDay(
          courses: courses,
          week: week,
          date: weekStart.add(Duration(days: offset)),
          totalWeeks: totalWeeks,
        ).where((o) => o.startAt.isAfter(now)),
      );
    }
  }

  occurrences.sort(_compareOccurrences);
  return occurrences;
}

List<ScheduleWidgetOccurrence> _occurrencesForDay({
  required List<Course> courses,
  required int week,
  required DateTime date,
  int totalWeeks = 20,
}) {
  if (week < 1 || week > totalWeeks) return const [];

  final weekday = date.weekday;
  final occurrences = courses
      .where((c) => c.dayOfWeek == weekday && c.isActiveInWeek(week))
      .map((course) => _occurrenceForCourse(course, week, date))
      .whereType<ScheduleWidgetOccurrence>()
      .toList()
    ..sort(_compareOccurrences);
  return occurrences;
}

ScheduleWidgetOccurrence? _occurrenceForCourse(
  Course course,
  int week,
  DateTime date,
) {
  final start = scheduleWidgetSlotTimes[course.timeSlot];
  final end = scheduleWidgetSlotTimes[course.endTimeSlot]?.$2;
  if (start == null || end == null) return null;

  final startAt = _dateWithTime(date, start.$1);
  final endAt = _dateWithTime(date, end);
  return ScheduleWidgetOccurrence(
    course: course,
    week: week,
    startAt: startAt,
    endAt: endAt,
    startText: start.$1,
    endText: end,
  );
}

DateTime _weekStartOf(DateTime semesterStart, int week) {
  final semesterMonday = _startOfDay(
    semesterStart,
  ).subtract(Duration(days: semesterStart.weekday - 1));
  return semesterMonday.add(Duration(days: (week - 1) * 7));
}

DateTime _dateWithTime(DateTime date, String text) {
  final parts = text.split(':');
  return DateTime(
    date.year,
    date.month,
    date.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
}

DateTime _startOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

int _compareOccurrences(
  ScheduleWidgetOccurrence a,
  ScheduleWidgetOccurrence b,
) {
  final startCompare = a.startAt.compareTo(b.startAt);
  if (startCompare != 0) return startCompare;

  final endCompare = a.endAt.compareTo(b.endAt);
  if (endCompare != 0) return endCompare;

  final nameCompare = a.course.name.compareTo(b.course.name);
  if (nameCompare != 0) return nameCompare;

  return a.course.classroom.compareTo(b.course.classroom);
}
