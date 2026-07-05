class Grade {
  final String semester;
  final String courseCode;
  final String courseName;
  final String score;
  final String credits;
  final String gradePoint;
  final String courseAttribute;
  final String courseNature;
  final String studentId;
  final String teachingClassId;
  final String gradeRecordId;

  const Grade({
    required this.semester,
    required this.courseCode,
    required this.courseName,
    required this.score,
    required this.credits,
    required this.gradePoint,
    required this.courseAttribute,
    required this.courseNature,
    this.studentId = '',
    this.teachingClassId = '',
    this.gradeRecordId = '',
  });

  bool get hasDetail => detailQueryParameters != null;

  Map<String, String>? get detailQueryParameters {
    if (studentId.isEmpty || teachingClassId.isEmpty || gradeRecordId.isEmpty) {
      return null;
    }
    return {
      'xs0101id': studentId,
      'jx0404id': teachingClassId,
      'cj0708id': gradeRecordId,
      'zcj': score,
    };
  }

  factory Grade.fromJson(Map<String, dynamic> json) => Grade(
        semester: json['semester'] as String? ?? '',
        courseCode: json['courseCode'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        score: json['score'] as String? ?? '-',
        credits: json['credits'] as String? ?? '-',
        gradePoint: json['gradePoint'] as String? ?? '-',
        courseAttribute: json['courseAttribute'] as String? ?? '',
        courseNature: json['courseNature'] as String? ?? '',
        studentId: json['studentId'] as String? ?? '',
        teachingClassId: json['teachingClassId'] as String? ?? '',
        gradeRecordId: json['gradeRecordId'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'semester': semester,
        'courseCode': courseCode,
        'courseName': courseName,
        'score': score,
        'credits': credits,
        'gradePoint': gradePoint,
        'courseAttribute': courseAttribute,
        'courseNature': courseNature,
        'studentId': studentId,
        'teachingClassId': teachingClassId,
        'gradeRecordId': gradeRecordId,
      };
}

class GradeDetail {
  final List<GradeDetailItem> items;
  final String totalScore;

  const GradeDetail({
    required this.items,
    required this.totalScore,
  });

  bool get isEmpty => items.isEmpty;

  factory GradeDetail.fromJson(Map<String, dynamic> json) => GradeDetail(
        items: (json['items'] as List? ?? [])
            .whereType<Map>()
            .map((item) => GradeDetailItem.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(),
        totalScore: json['totalScore'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'items': items.map((item) => item.toJson()).toList(),
        'totalScore': totalScore,
      };
}

class GradeDetailItem {
  final String name;
  final String score;
  final String ratio;

  const GradeDetailItem({
    required this.name,
    required this.score,
    required this.ratio,
  });

  factory GradeDetailItem.fromJson(Map<String, dynamic> json) =>
      GradeDetailItem(
        name: json['name'] as String? ?? '',
        score: json['score'] as String? ?? '',
        ratio: json['ratio'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'score': score,
        'ratio': ratio,
      };
}
