// packages/core/test/models/course_test.dart

import 'package:test/test.dart';
import 'package:core/models/course.dart';

void main() {
  group('Course.isActiveInWeek', () {
    const course = Course(
      name: '高等数学',
      teacher: '张老师',
      timeStr: '周一 1-2节',
      classroom: 'A101',
      dayOfWeek: 1,
      timeSlot: 1,
      weekList: [1, 2, 3, 5, 7], // 跳跃周
    );

    test('包含在 weekList 中的周返回 true', () {
      expect(course.isActiveInWeek(1), isTrue);
      expect(course.isActiveInWeek(3), isTrue);
      expect(course.isActiveInWeek(7), isTrue);
    });

    test('不在 weekList 中的周返回 false', () {
      expect(course.isActiveInWeek(4), isFalse);
      expect(course.isActiveInWeek(6), isFalse);
      expect(course.isActiveInWeek(8), isFalse);
    });

    test('weekList 为空时任意周均返回 false', () {
      const emptyCourse = Course(
        name: '体育',
        teacher: '李老师',
        timeStr: '',
        classroom: '',
        dayOfWeek: 3,
        timeSlot: 9,
        weekList: [],
      );
      expect(emptyCourse.isActiveInWeek(1), isFalse);
      expect(emptyCourse.isActiveInWeek(99), isFalse);
    });
  });

  group('Course.slotSpan', () {
    test('默认 endTimeSlot == timeSlot 时 slotSpan == 1', () {
      const c = Course(
        name: 'x',
        teacher: '',
        timeStr: '',
        classroom: '',
        dayOfWeek: 1,
        timeSlot: 3,
        weekList: [],
      );
      expect(c.slotSpan, equals(1));
    });

    test('endTimeSlot > timeSlot 时 slotSpan 正确计算', () {
      const c = Course(
        name: 'x',
        teacher: '',
        timeStr: '',
        classroom: '',
        dayOfWeek: 2,
        timeSlot: 1,
        endTimeSlot: 4,
        weekList: [],
      );
      expect(c.slotSpan, equals(4));
    });
  });

  group('Course.fromJson', () {
    test('正常 JSON 全字段解析', () {
      final json = {
        'name': '线性代数',
        'teacher': '王老师',
        'timeStr': '周三 3-4节',
        'classroom': 'B202',
        'dayOfWeek': 3,
        'timeSlot': 3,
        'endTimeSlot': 4,
        'weekList': [1, 2, 4, 6, 8],
      };
      final c = Course.fromJson(json);
      expect(c.name, '线性代数');
      expect(c.teacher, '王老师');
      expect(c.dayOfWeek, 3);
      expect(c.timeSlot, 3);
      expect(c.endTimeSlot, 4);
      expect(c.weekList, [1, 2, 4, 6, 8]);
    });

    test('缺少可选字段时使用默认值', () {
      final c = Course.fromJson({});
      expect(c.name, '');
      expect(c.dayOfWeek, 1);
      expect(c.timeSlot, 1);
      expect(c.weekList, isEmpty);
      expect(c.slotSpan, 1); // endTimeSlot 默认 == timeSlot
    });

    test('weekList 缺失时返回空列表', () {
      final c =
          Course.fromJson({'name': 'test', 'dayOfWeek': 1, 'timeSlot': 1});
      expect(c.weekList, isEmpty);
    });
  });
}
