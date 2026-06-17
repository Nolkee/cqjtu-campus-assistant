class Course {
  final String name;
  final String teacher;
  final String timeStr;
  final String classroom;
  final int dayOfWeek;
  final bool isExam;
  final bool isCustom;
  final String seatNumber;

  /// 起始小节（1-13，对应作息时间表中的第 N 小节）
  final int timeSlot;

  /// 结束小节（含），默认等于 timeSlot（即只占 1 小节）
  final int endTimeSlot;

  /// ✅ 新增：该课程的所有上课周数集合（替换原来的 startWeek 和 endWeek）
  final List<int> weekList;

  const Course({
    required this.name,
    required this.teacher,
    required this.timeStr,
    required this.classroom,
    required this.dayOfWeek,
    required this.timeSlot,
    int? endTimeSlot,
    this.weekList = const [], // 默认给个空数组
    this.isExam = false,
    this.isCustom = false,
    this.seatNumber = '',
  }) : endTimeSlot = endTimeSlot ?? timeSlot;

  /// 该课程占据的小节数
  int get slotSpan => endTimeSlot - timeSlot + 1;

  /// 🎉 核心减负：极简的当前周判断逻辑！
  /// 因为后端已经把诸如单双周、跳跃周全都算好塞进了 weekList，
  /// 前端只需要一个 contains 就搞定了，不仅性能好而且 100% 准确！
  bool isActiveInWeek(int week) {
    return weekList.contains(week);
  }

  bool get hasSeatNumber {
    final normalized = seatNumber.trim();
    return normalized.isNotEmpty && normalized != '-';
  }

  String get placeText {
    if (isExam && hasSeatNumber) {
      return classroom.trim().isEmpty
          ? '座位号：$seatNumber'
          : '${classroom.trim()} · 座位号：$seatNumber';
    }
    return classroom;
  }

  Course copyWith({
    String? name,
    String? teacher,
    String? timeStr,
    String? classroom,
    int? dayOfWeek,
    int? timeSlot,
    int? endTimeSlot,
    List<int>? weekList,
    bool? isExam,
    bool? isCustom,
    String? seatNumber,
  }) {
    return Course(
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      timeStr: timeStr ?? this.timeStr,
      classroom: classroom ?? this.classroom,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      timeSlot: timeSlot ?? this.timeSlot,
      endTimeSlot: endTimeSlot ?? this.endTimeSlot,
      weekList: weekList ?? this.weekList,
      isExam: isExam ?? this.isExam,
      isCustom: isCustom ?? this.isCustom,
      seatNumber: seatNumber ?? this.seatNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'teacher': teacher,
      'timeStr': timeStr,
      'classroom': classroom,
      'dayOfWeek': dayOfWeek,
      'timeSlot': timeSlot,
      'endTimeSlot': endTimeSlot,
      'weekList': weekList,
      'isExam': isExam,
      'isCustom': isCustom,
      'seatNumber': seatNumber,
    };
  }

  /// 适配新的 JSON 结构解析
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      name: json['name'] ?? '',
      teacher: json['teacher'] ?? '',
      timeStr: json['timeStr'] ?? '',
      classroom: json['classroom'] ?? '',
      dayOfWeek: json['dayOfWeek'] ?? 1,
      timeSlot: json['timeSlot'] ?? 1,
      endTimeSlot: json['endTimeSlot'],
      // 关键：将后端传过来的 JSON 数组强转为 List<int>
      weekList:
          (json['weekList'] as List<dynamic>?)?.map((e) => e as int).toList() ??
              [],
      isExam: _boolValue(json['isExam']),
      isCustom: _boolValue(json['isCustom']),
      seatNumber: json['seatNumber']?.toString() ?? '',
    );
  }
}

bool _boolValue(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}
