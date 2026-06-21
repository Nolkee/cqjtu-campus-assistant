import 'package:core/models/exam.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/shared.dart';
import '../auth/auth_providers.dart';

final examsProvider = FutureProvider.autoDispose.family<List<Exam>, String?>((
  ref,
  semester,
) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  ensureCredentialPassword(creds);

  final gateway = ref.watch(campusGatewayProvider);
  return gateway.getExams(creds.username, creds.password, semester: semester);
});
