import 'package:core/models/grade.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/shared.dart';
import '../auth/auth_providers.dart';

typedef GradeResult = ({Map<String, String> summary, List<Grade> grades});

final gradesProvider = FutureProvider.autoDispose.family<GradeResult, String>((
  ref,
  semester,
) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  ensureCredentialPassword(creds);

  final gateway = ref.watch(campusGatewayProvider);
  return gateway.getGrades(creds.username, creds.password, semester: semester);
});
