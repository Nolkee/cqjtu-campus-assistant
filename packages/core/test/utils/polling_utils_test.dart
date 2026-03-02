// packages/core/test/utils/polling_utils_test.dart

import 'package:test/test.dart';
import 'package:core/utils/polling_utils.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/exam.dart';

void main() {
  // ── pollingInterval ──────────────────────────────────────────
  group('pollingInterval', () {
    Duration interval(int hour) =>
        pollingInterval(DateTime(2025, 9, 1, hour, 0));

    test('凌晨 0 点 → 3 小时（夜间降频）', () {
      expect(interval(0), const Duration(hours: 3));
    });

    test('凌晨 5 点 → 3 小时（夜间降频）', () {
      expect(interval(5), const Duration(hours: 3));
    });

    test('早上 6 点 → 30 分钟（正常频率）', () {
      expect(interval(6), const Duration(minutes: 30));
    });

    test('正午 12 点 → 30 分钟', () {
      expect(interval(12), const Duration(minutes: 30));
    });

    test('深夜 23 点 → 30 分钟', () {
      expect(interval(23), const Duration(minutes: 30));
    });
  });

  // ── Grade.fromJson ───────────────────────────────────────────
  group('Grade.fromJson', () {
    test('正常 JSON 全字段解析', () {
      final g = Grade.fromJson({
        'semester': '2024-2025-1',
        'courseCode': 'MATH001',
        'courseName': '高等数学',
        'score': '92',
        'credits': '4.0',
        'gradePoint': '3.7',
        'courseAttribute': '必修',
        'courseNature': '考试',
      });
      expect(g.semester, '2024-2025-1');
      expect(g.courseName, '高等数学');
      expect(g.score, '92');
      expect(g.credits, '4.0');
      expect(g.gradePoint, '3.7');
    });

    test('缺失字段使用 "-" 默认值', () {
      final g = Grade.fromJson({});
      expect(g.score, '-');
      expect(g.credits, '-');
      expect(g.gradePoint, '-');
    });

    test('字符串字段缺失时使用空字符串', () {
      final g = Grade.fromJson({});
      expect(g.semester, '');
      expect(g.courseCode, '');
      expect(g.courseName, '');
      expect(g.courseAttribute, '');
      expect(g.courseNature, '');
    });
  });

  // ── Exam.fromJson ────────────────────────────────────────────
  group('Exam.fromJson', () {
    test('正常 JSON 全字段解析', () {
      final e = Exam.fromJson({
        'courseName': '操作系统',
        'teacher': '陈老师',
        'examTime': '2025-01-10 09:00-11:00',
        'examRoom': 'C301',
        'seatNumber': '42',
        'campus': '科学城校区',
        'ticketNumber': '20230001',
      });
      expect(e.courseName, '操作系统');
      expect(e.examTime, '2025-01-10 09:00-11:00');
      expect(e.seatNumber, '42');
      expect(e.ticketNumber, '20230001');
    });

    test('seatNumber / ticketNumber 缺失时使用 "-" 默认值', () {
      final e = Exam.fromJson({'courseName': '英语'});
      expect(e.seatNumber, '-');
      expect(e.ticketNumber, '-');
    });

    test('缺失字段时其他字符串为空字符串', () {
      final e = Exam.fromJson({});
      expect(e.courseName, '');
      expect(e.teacher, '');
      expect(e.examTime, '');
      expect(e.examRoom, '');
      expect(e.campus, '');
    });
  });
}
