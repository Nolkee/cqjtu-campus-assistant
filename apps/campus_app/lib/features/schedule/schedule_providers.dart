import 'dart:async';
import 'dart:convert';

import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/utils/exam_time_utils.dart';
import 'package:core/utils/schedule_time_utils.dart';
import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/shared.dart';
import '../../utils/semester_service.dart';
import '../auth/auth_providers.dart';

typedef ScheduleResult = ({List<Course> courses, String remark});

final scheduleProvider = FutureProvider.family<ScheduleResult, String?>((
  ref,
  semester,
) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  ensureCredentialPassword(creds);

  final gateway = ref.watch(campusGatewayProvider);
  final selectedSemester = await ref.watch(
    selectedScheduleSemesterProvider.future,
  );
  final semesterKey = semester ?? selectedSemester;
  final customCourses = await ref.watch(
    customCoursesProvider(semesterKey).future,
  );
  final totalWeeks = await ref.watch(
    semesterTotalWeeksProvider(semesterKey).future,
  );
  final scheduleResult = await gateway.getSchedule(
    creds.username,
    creds.password,
    semester: semester,
  );

  final semesterStart = await _resolveSemesterStart(ref, semesterKey);
  final examCourses = semesterStart == null
      ? <Course>[]
      : await _loadExamCourses(
          gateway: gateway,
          username: creds.username,
          password: creds.password,
          semester: semester,
          semesterStart: semesterStart,
          totalWeeks: totalWeeks,
        );

  return (
    courses: [...scheduleResult.courses, ...customCourses, ...examCourses],
    remark: scheduleResult.remark,
  );
});

Future<DateTime?> _resolveSemesterStart(Ref ref, String? semesterKey) async {
  if (semesterKey != null && semesterKey.isNotEmpty) {
    return ref.watch(semesterStartForKeyProvider(semesterKey).future);
  }
  return ref.watch(semesterStartProvider.future);
}

Future<List<Course>> _loadExamCourses({
  required CampusGateway gateway,
  required String username,
  required String password,
  required String? semester,
  required DateTime semesterStart,
  required int totalWeeks,
}) async {
  try {
    final exams = await gateway.getExams(
      username,
      password,
      semester: semester,
    );
    return examsToCourses(
      exams: exams,
      semesterStart: semesterStart,
      totalWeeks: totalWeeks,
    );
  } catch (error) {
    debugPrint('[Schedule] 考试安排同步到课表失败: $error');
    return const [];
  }
}

/// 将考试列表转换为课表课程。
List<Course> examsToCourses({
  required List<Exam> exams,
  required DateTime semesterStart,
  required int totalWeeks,
}) {
  return exams
      .map((exam) {
        final parsed = parseExamTime(exam.examTime);
        if (parsed == null) return null;

        final week = weekOfDate(semesterStart, parsed.start);
        if (week < 1 || week > totalWeeks) return null;

        final name = exam.courseName.trim().isEmpty
            ? '考试'
            : '考试：${exam.courseName.trim()}';
        final seat = exam.seatNumber.trim() == '-'
            ? ''
            : exam.seatNumber.trim();
        return Course(
          name: name,
          teacher: '',
          timeStr: exam.examTime.trim(),
          classroom: exam.examRoom.trim(),
          dayOfWeek: parsed.start.weekday,
          timeSlot: nearestStartSlot(parsed.start),
          endTimeSlot: endSlotFor(parsed.end),
          weekList: [week],
          isExam: true,
          seatNumber: seat,
        );
      })
      .whereType<Course>()
      .toList();
}

// ── Semester / Week / Course Settings ─────────────────────────

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

class SemesterStartForKeyNotifier
    extends FamilyAsyncNotifier<DateTime?, String> {
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
    AsyncNotifierProvider.family<
      SemesterStartForKeyNotifier,
      DateTime?,
      String
    >(SemesterStartForKeyNotifier.new);

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

const int defaultSemesterTotalWeeks = 20;
const int minSemesterTotalWeeks = 12;
const int maxSemesterTotalWeeks = 30;

const _semesterTotalWeeksPrefix = 'schedule_total_weeks_';
const _customCoursesPrefix = 'schedule_custom_courses_';

String _semesterScopedKey(String prefix, String? semester) {
  final safeSemester = semester?.trim();
  return '$prefix${safeSemester == null || safeSemester.isEmpty ? 'default' : safeSemester}';
}

int _normalizeTotalWeeks(int value) {
  return value.clamp(minSemesterTotalWeeks, maxSemesterTotalWeeks).toInt();
}

class SemesterTotalWeeksNotifier extends FamilyAsyncNotifier<int, String?> {
  @override
  Future<int> build(String? arg) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(
      _semesterScopedKey(_semesterTotalWeeksPrefix, arg),
    );
    return _normalizeTotalWeeks(stored ?? defaultSemesterTotalWeeks);
  }

  Future<void> setWeeks(int value) async {
    final safeValue = _normalizeTotalWeeks(value);
    state = AsyncValue.data(safeValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _semesterScopedKey(_semesterTotalWeeksPrefix, arg),
      safeValue,
    );
  }
}

final semesterTotalWeeksProvider =
    AsyncNotifierProvider.family<SemesterTotalWeeksNotifier, int, String?>(
      SemesterTotalWeeksNotifier.new,
    );

class CustomCoursesNotifier extends FamilyAsyncNotifier<List<Course>, String?> {
  @override
  Future<List<Course>> build(String? arg) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_semesterScopedKey(_customCoursesPrefix, arg));
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Course.fromJson(Map<String, dynamic>.from(item)))
          .map((course) => course.copyWith(isCustom: true))
          .toList();
    } catch (error) {
      debugPrint('[Schedule] 自定义课程读取失败: $error');
      return const [];
    }
  }

  Future<void> addCourse(Course course) async {
    final current = state.valueOrNull ?? await future;
    final next = [...current, course.copyWith(isCustom: true, isExam: false)];
    await _save(next);
  }

  Future<void> removeCourse(Course course) async {
    final current = state.valueOrNull ?? await future;
    var removed = false;
    final next = <Course>[];
    for (final item in current) {
      if (!removed &&
          _courseStorageIdentity(item) == _courseStorageIdentity(course)) {
        removed = true;
        continue;
      }
      next.add(item);
    }
    await _save(next);
  }

  Future<void> clearCourses() => _save(const []);

  Future<void> _save(List<Course> courses) async {
    state = AsyncValue.data(courses);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _semesterScopedKey(_customCoursesPrefix, arg),
      jsonEncode(courses.map((course) => course.toJson()).toList()),
    );
  }

  String _courseStorageIdentity(Course course) {
    return jsonEncode(course.copyWith(isCustom: true, isExam: false).toJson());
  }
}

final customCoursesProvider =
    AsyncNotifierProvider.family<CustomCoursesNotifier, List<Course>, String?>(
      CustomCoursesNotifier.new,
    );

class SelectedWeekNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void setWeek(int week) => state = week;
}

final selectedWeekProvider = NotifierProvider<SelectedWeekNotifier, int>(
  SelectedWeekNotifier.new,
);

const _scheduleSundayFirstKey = 'schedule_sunday_first';
const _scheduleShowInactiveCoursesKey = 'schedule_show_inactive_courses';

class ScheduleSundayFirstNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scheduleSundayFirstKey) ?? false;
  }

  Future<void> setSundayFirst(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scheduleSundayFirstKey, value);
  }
}

final scheduleSundayFirstProvider =
    AsyncNotifierProvider<ScheduleSundayFirstNotifier, bool>(
      ScheduleSundayFirstNotifier.new,
    );

class ScheduleShowInactiveCoursesNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scheduleShowInactiveCoursesKey) ?? true;
  }

  Future<void> setShowInactiveCourses(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scheduleShowInactiveCoursesKey, value);
  }
}

final scheduleShowInactiveCoursesProvider =
    AsyncNotifierProvider<ScheduleShowInactiveCoursesNotifier, bool>(
      ScheduleShowInactiveCoursesNotifier.new,
    );
