class Grade {
  final String semester;
  final String courseCode;
  final String courseName;
  final String score;
  final String credits;
  final String gradePoint;
  final String courseAttribute;
  final String courseNature;

  const Grade({
    required this.semester,
    required this.courseCode,
    required this.courseName,
    required this.score,
    required this.credits,
    required this.gradePoint,
    required this.courseAttribute,
    required this.courseNature,
  });

  factory Grade.fromJson(Map<String, dynamic> json) => Grade(
        semester: json['semester'] as String? ?? '',
        courseCode: json['courseCode'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        score: json['score'] as String? ?? '-',
        credits: json['credits'] as String? ?? '-',
        gradePoint: json['gradePoint'] as String? ?? '-',
        courseAttribute: json['courseAttribute'] as String? ?? '',
        courseNature: json['courseNature'] as String? ?? '',
      );
}
