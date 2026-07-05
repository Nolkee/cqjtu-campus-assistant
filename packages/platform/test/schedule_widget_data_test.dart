import 'package:campus_platform/src/schedule_widget_data.dart';
import 'package:core/models/course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateScheduleWidgetWeek', () {
    test('calculates current week from semester Monday', () {
      expect(
        calculateScheduleWidgetWeek(
          DateTime(2026, 6, 1),
          DateTime(2026, 6, 3, 12),
        ),
        1,
      );
      expect(
        calculateScheduleWidgetWeek(
          DateTime(2026, 6, 3),
          DateTime(2026, 6, 2, 12),
        ),
        1,
      );
      expect(
        calculateScheduleWidgetWeek(
          DateTime(2026, 6, 8),
          DateTime(2026, 6, 7, 12),
        ),
        0,
      );
      expect(
        calculateScheduleWidgetWeek(
          DateTime(2026, 6, 1),
          DateTime(2026, 10, 20, 12),
        ),
        21,
      );
    });
  });

  group('buildScheduleWidgetSnapshot', () {
    test('returns no cache state when course list is empty', () {
      final snapshot = buildScheduleWidgetSnapshot(
        courses: const [],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 12),
      );

      expect(snapshot.nextClass.status, NextClassWidgetStatus.noCache);
      expect(snapshot.todayCourses, isEmpty);
    });

    test("filters today's active courses by current week", () {
      final snapshot = buildScheduleWidgetSnapshot(
        courses: const [
          Course(
            name: '高等数学',
            teacher: '张老师',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 1,
            weekList: [1],
          ),
          Course(
            name: '大学英语',
            teacher: '李老师',
            timeStr: '',
            classroom: 'B202',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 2,
            weekList: [2],
          ),
          Course(
            name: '线性代数',
            teacher: '王老师',
            timeStr: '',
            classroom: 'C303',
            dayOfWeek: DateTime.thursday,
            timeSlot: 3,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 7),
      );

      expect(snapshot.todayCourses.map((o) => o.course.name), ['高等数学']);
      expect(snapshot.nextClass.status, NextClassWidgetStatus.next);
      expect(snapshot.nextClass.occurrence?.course.name, '高等数学');
    });

    test('detects current class', () {
      final snapshot = buildScheduleWidgetSnapshot(
        courses: const [
          Course(
            name: '概率论与数理统计B',
            teacher: '杨老师',
            timeStr: '',
            classroom: 'A01231',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            endTimeSlot: 7,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 14, 30),
      );

      expect(snapshot.nextClass.status, NextClassWidgetStatus.current);
      expect(snapshot.nextClass.occurrence?.timeRange, '14:00-15:25');
    });

    test('uses exact exam minutes instead of slot start time', () {
      final snapshot = buildScheduleWidgetSnapshot(
        courses: const [
          Course(
            name: 'Exam',
            teacher: '',
            timeStr: '2026-06-03 14:30-16:30',
            classroom: 'A01128',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 7,
            endTimeSlot: 9,
            weekList: [1],
            isExam: true,
            exactStartMinutes: 14 * 60 + 30,
            exactEndMinutes: 16 * 60 + 30,
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 14, 31),
      );

      expect(snapshot.nextClass.status, NextClassWidgetStatus.current);
      expect(snapshot.nextClass.occurrence?.timeRange, '14:30-16:30');
    });

    test('detects today done and today empty states', () {
      final done = buildScheduleWidgetSnapshot(
        courses: const [
          Course(
            name: '高等数学',
            teacher: '张老师',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 1,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 12),
      );
      expect(done.nextClass.status, NextClassWidgetStatus.todayDone);
      expect(done.nextClass.occurrence, isNull);

      final empty = buildScheduleWidgetSnapshot(
        courses: const [
          Course(
            name: '线性代数',
            teacher: '王老师',
            timeStr: '',
            classroom: 'C303',
            dayOfWeek: DateTime.thursday,
            timeSlot: 3,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 12),
      );
      expect(empty.nextClass.status, NextClassWidgetStatus.todayEmpty);
      expect(empty.nextClass.occurrence, isNull);
    });

    test('sorts multiple courses in the same slot consistently', () {
      final snapshot = buildScheduleWidgetSnapshot(
        courses: const [
          Course(
            name: 'B课程',
            teacher: '',
            timeStr: '',
            classroom: 'A102',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
          Course(
            name: 'A课程',
            teacher: '',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 12),
      );

      expect(snapshot.todayCourses.map((o) => o.course.name), ['A课程', 'B课程']);
    });
  });
}
