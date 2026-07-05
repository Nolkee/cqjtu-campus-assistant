import 'package:core/models/grade.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../auth/auth_providers.dart';
import '../shared/cached_resource.dart';

typedef GradeResult = ({Map<String, String> summary, List<Grade> grades});

typedef GradeDetailArg = ({Grade grade});

final gradesProvider =
    NotifierProvider.family<
      GradesNotifier,
      CachedResource<GradeResult>,
      String
    >(GradesNotifier.new);

class GradesNotifier extends CachedResourceNotifier<GradeResult, String> {
  @override
  GradeResult get emptyData => (summary: const {}, grades: const []);

  @override
  String get cacheNamespace => 'grades';

  @override
  String? cacheScopeForArg(String arg) => arg;

  @override
  Object? encode(GradeResult data) => {
    'summary': data.summary,
    'grades': data.grades.map((grade) => grade.toJson()).toList(),
  };

  @override
  GradeResult decode(Object? json) {
    if (json is! Map) return emptyData;
    final summaryRaw = json['summary'];
    final gradesRaw = json['grades'];
    return (
      summary: summaryRaw is Map
          ? summaryRaw.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
      grades: gradesRaw is List
          ? gradesRaw
                .whereType<Map>()
                .map((item) => Grade.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : const <Grade>[],
    );
  }

  @override
  Future<GradeResult> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) {
    ensureCredentialPassword(credentials);
    return ref
        .read(campusGatewayProvider)
        .getGrades(
          credentials.username,
          credentials.password,
          semester: resourceArg,
          forceRefresh: forceRefresh,
        );
  }
}

final gradeDetailProvider =
    NotifierProvider.family<
      GradeDetailNotifier,
      CachedResource<GradeDetail>,
      GradeDetailArg
    >(GradeDetailNotifier.new);

class GradeDetailNotifier
    extends CachedResourceNotifier<GradeDetail, GradeDetailArg> {
  @override
  GradeDetail get emptyData => const GradeDetail(items: [], totalScore: '');

  @override
  String get cacheNamespace => 'grade_detail';

  @override
  String? cacheScopeForArg(GradeDetailArg arg) {
    final grade = arg.grade;
    return [
      grade.semester,
      grade.courseCode,
      grade.courseName,
      grade.studentId,
      grade.teachingClassId,
      grade.gradeRecordId,
      grade.score,
    ].join('|');
  }

  @override
  Object? encode(GradeDetail data) => data.toJson();

  @override
  GradeDetail decode(Object? json) {
    if (json is! Map) return emptyData;
    return GradeDetail.fromJson(Map<String, dynamic>.from(json));
  }

  @override
  Future<GradeDetail> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) {
    ensureCredentialPassword(credentials);
    return ref
        .read(campusGatewayProvider)
        .getGradeDetail(
          credentials.username,
          credentials.password,
          grade: resourceArg.grade,
          forceRefresh: forceRefresh,
        );
  }
}
