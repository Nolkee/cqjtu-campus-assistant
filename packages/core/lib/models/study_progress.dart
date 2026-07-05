class StudyProgressCourse {
  const StudyProgressCourse({
    required this.code,
    required this.name,
    required this.credits,
    required this.attribute,
    this.nature = '',
    this.semester = '',
    this.status = '',
    this.score = '',
    this.remark = '',
    this.isDegreeCourse = '',
    this.totalHours = '',
    this.isPlannedCourse = false,
  });

  final String code;
  final String name;
  final String credits;
  final String attribute;
  final String nature;
  final String semester;
  final String status;
  final String score;
  final String remark;
  final String isDegreeCourse;
  final String totalHours;
  final bool isPlannedCourse;

  factory StudyProgressCourse.fromJson(Map<String, dynamic> json) =>
      StudyProgressCourse(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        credits: json['credits'] as String? ?? '',
        attribute: json['attribute'] as String? ?? '',
        nature: json['nature'] as String? ?? '',
        semester: json['semester'] as String? ?? '',
        status: json['status'] as String? ?? '',
        score: json['score'] as String? ?? '',
        remark: json['remark'] as String? ?? '',
        isDegreeCourse: json['isDegreeCourse'] as String? ?? '',
        totalHours: json['totalHours'] as String? ?? '',
        isPlannedCourse: json['isPlannedCourse'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'credits': credits,
        'attribute': attribute,
        'nature': nature,
        'semester': semester,
        'status': status,
        'score': score,
        'remark': remark,
        'isDegreeCourse': isDegreeCourse,
        'totalHours': totalHours,
        'isPlannedCourse': isPlannedCourse,
      };
}

class StudyProgressGroup {
  const StudyProgressGroup({
    required this.id,
    required this.title,
    required this.requiredCredits,
    this.earnedCredits = '',
    this.remainingCredits = '',
    this.completionRate = '',
    this.courses = const [],
  });

  final String id;
  final String title;
  final String requiredCredits;
  final String earnedCredits;
  final String remainingCredits;
  final String completionRate;
  final List<StudyProgressCourse> courses;

  factory StudyProgressGroup.fromJson(Map<String, dynamic> json) =>
      StudyProgressGroup(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        requiredCredits: json['requiredCredits'] as String? ?? '',
        earnedCredits: json['earnedCredits'] as String? ?? '',
        remainingCredits: json['remainingCredits'] as String? ?? '',
        completionRate: json['completionRate'] as String? ?? '',
        courses: (json['courses'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  StudyProgressCourse.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'requiredCredits': requiredCredits,
        'earnedCredits': earnedCredits,
        'remainingCredits': remainingCredits,
        'completionRate': completionRate,
        'courses': courses.map((course) => course.toJson()).toList(),
      };
}

class ExecutionPlanCourse {
  const ExecutionPlanCourse({
    required this.code,
    required this.name,
  });

  final String code;
  final String name;

  factory ExecutionPlanCourse.fromJson(Map<String, dynamic> json) =>
      ExecutionPlanCourse(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
      };
}

class StudyProgressData {
  const StudyProgressData({
    required this.groups,
    required this.currentSemester,
    required this.currentSemesterCourses,
  });

  final List<StudyProgressGroup> groups;
  final String currentSemester;
  final List<ExecutionPlanCourse> currentSemesterCourses;

  factory StudyProgressData.fromJson(Map<String, dynamic> json) =>
      StudyProgressData(
        groups: (json['groups'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  StudyProgressGroup.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
        currentSemester: json['currentSemester'] as String? ?? '',
        currentSemesterCourses:
            (json['currentSemesterCourses'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (item) => ExecutionPlanCourse.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(),
      );

  Map<String, dynamic> toJson() => {
        'groups': groups.map((group) => group.toJson()).toList(),
        'currentSemester': currentSemester,
        'currentSemesterCourses':
            currentSemesterCourses.map((course) => course.toJson()).toList(),
      };
}
