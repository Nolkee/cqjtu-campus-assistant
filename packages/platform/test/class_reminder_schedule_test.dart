import 'package:campus_platform/src/class_reminder_schedule.dart';
import 'package:core/models/course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildClassReminders', () {
    test('builds current and next week reminders within seven days', () {
      final reminders = buildClassReminders(
        courses: const [
          Course(
            name: '高等数学',
            teacher: '张老师',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
          Course(
            name: '大学英语',
            teacher: '李老师',
            timeStr: '',
            classroom: 'B202',
            dayOfWeek: DateTime.tuesday,
            timeSlot: 1,
            weekList: [2],
          ),
          Course(
            name: '超过七天的课',
            teacher: '',
            timeStr: '',
            classroom: 'C303',
            dayOfWeek: DateTime.thursday,
            timeSlot: 1,
            weekList: [2],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 12),
        reminderMinutes: 15,
      );

      expect(reminders.map((r) => r.courseName), ['高等数学', '大学英语']);
      expect(reminders.first.remindAt, DateTime(2026, 6, 3, 13, 45));
      expect(reminders.first.classStartAt, DateTime(2026, 6, 3, 14));
      expect(reminders.last.remindAt, DateTime(2026, 6, 9, 8, 5));
    });

    test('skips reminders whose reminder time already passed', () {
      final reminders = buildClassReminders(
        courses: const [
          Course(
            name: '高等数学',
            teacher: '张老师',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 13, 50),
        reminderMinutes: 15,
      );

      expect(reminders, isEmpty);
    });

    test('uses exact exam minutes instead of slot start time', () {
      final reminders = buildClassReminders(
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
        now: DateTime(2026, 6, 3, 14),
        reminderMinutes: 15,
      );

      expect(reminders, hasLength(1));
      expect(reminders.first.timeText, '14:30');
      expect(reminders.first.remindAt, DateTime(2026, 6, 3, 14, 15));
      expect(reminders.first.classStartAt, DateTime(2026, 6, 3, 14, 30));
    });

    test('keeps active Android reminders until class starts', () {
      final reminders = buildClassReminders(
        courses: const [
          Course(
            name: '高等数学',
            teacher: '张老师',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 13, 50),
        reminderMinutes: 15,
        includeActiveReminders: true,
      );

      expect(reminders, hasLength(1));
      expect(reminders.first.remindAt, DateTime(2026, 6, 3, 13, 45));
      expect(reminders.first.classStartAt, DateTime(2026, 6, 3, 14));
    });

    test('uses unique ids for multiple courses in the same slot', () {
      final reminders = buildClassReminders(
        courses: const [
          Course(
            name: '高等数学',
            teacher: '张老师',
            timeStr: '',
            classroom: 'A101',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
          Course(
            name: '线性代数',
            teacher: '王老师',
            timeStr: '',
            classroom: 'A102',
            dayOfWeek: DateTime.wednesday,
            timeSlot: 6,
            weekList: [1],
          ),
        ],
        semesterStart: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 3, 12),
        reminderMinutes: 15,
      );

      expect(reminders, hasLength(2));
      expect(reminders.map((r) => r.id).toSet(), hasLength(2));
    });
  });
}
