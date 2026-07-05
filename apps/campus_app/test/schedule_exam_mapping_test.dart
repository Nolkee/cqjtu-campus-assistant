import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:core/models/exam.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'examsToCourses keeps exact minutes and avoids nearest-slot snapping',
    () {
      final courses = examsToCourses(
        exams: const [
          Exam(
            courseName: 'Marxism',
            teacher: '',
            examTime: '2026-06-30 14:30-16:30',
            examRoom: 'A01128',
            seatNumber: '23',
            campus: '',
            ticketNumber: '',
          ),
        ],
        semesterStart: DateTime(2026, 2, 23),
        totalWeeks: 20,
      );

      expect(courses, hasLength(1));
      final course = courses.single;
      expect(course.timeSlot, 6);
      expect(course.endTimeSlot, 9);
      expect(course.exactStartMinutes, 14 * 60 + 30);
      expect(course.exactEndMinutes, 16 * 60 + 30);
    },
  );
}
