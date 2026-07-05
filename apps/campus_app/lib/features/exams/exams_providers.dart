import 'package:core/models/exam.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../auth/auth_providers.dart';
import '../shared/cached_resource.dart';

final examsProvider =
    NotifierProvider.family<ExamsNotifier, CachedResource<List<Exam>>, String?>(
      ExamsNotifier.new,
    );

class ExamsNotifier extends CachedResourceNotifier<List<Exam>, String?> {
  @override
  List<Exam> get emptyData => const [];

  @override
  String get cacheNamespace => 'exams';

  @override
  String? cacheScopeForArg(String? arg) => arg;

  @override
  Object? encode(List<Exam> data) => data.map((exam) => exam.toJson()).toList();

  @override
  List<Exam> decode(Object? json) {
    if (json is! List) return const [];
    return json
        .whereType<Map>()
        .map((item) => Exam.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<List<Exam>> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) {
    ensureCredentialPassword(credentials);
    return ref
        .read(campusGatewayProvider)
        .getExams(
          credentials.username,
          credentials.password,
          semester: resourceArg,
          forceRefresh: forceRefresh,
        );
  }
}
