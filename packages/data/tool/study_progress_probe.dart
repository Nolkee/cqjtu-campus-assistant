import 'dart:io';

import 'package:data/data.dart';

Future<void> main() async {
  final localEnv = _loadLocalEnv();
  final username = _readSecret('CAMPUS_TEST_USERNAME', localEnv);
  final password = _readSecret('CAMPUS_TEST_PASSWORD', localEnv);

  if (username.isEmpty || password.isEmpty) {
    stderr.writeln(
      'Set CAMPUS_TEST_USERNAME and CAMPUS_TEST_PASSWORD in a local env file.',
    );
    exitCode = 64;
    return;
  }

  final gateway = DirectSchoolCampusGateway();
  await _probe('default', gateway, username, password);
  await _probe(
    'root-student',
    DirectSchoolCampusGateway(
      config: const SchoolSystemConfig(
        studyProgressUrl: 'https://jwgln.cqjtu.edu.cn/student/zxxywcqk',
        studentExecutionPlanUrl:
            'https://jwgln.cqjtu.edu.cn/student/executionPlan',
      ),
    ),
    username,
    password,
  );
  await _probe(
    'jsxsd-student',
    DirectSchoolCampusGateway(
      config: const SchoolSystemConfig(
        studyProgressUrl: 'https://jwgln.cqjtu.edu.cn/jsxsd/student/zxxywcqk',
        studentExecutionPlanUrl:
            'https://jwgln.cqjtu.edu.cn/jsxsd/student/executionPlan',
      ),
    ),
    username,
    password,
  );
  await _probe(
    'njwhd-student',
    DirectSchoolCampusGateway(
      config: const SchoolSystemConfig(
        studyProgressUrl: 'https://jwgln.cqjtu.edu.cn/njwhd/student/zxxywcqk',
        studentExecutionPlanUrl:
            'https://jwgln.cqjtu.edu.cn/njwhd/student/executionPlan',
      ),
    ),
    username,
    password,
  );
}

Future<void> _probe(
  String label,
  DirectSchoolCampusGateway gateway,
  String username,
  String password,
) async {
  stdout.writeln('probe=$label');
  final progress = await gateway.getStudyProgress(
    username,
    password,
    forceRefresh: true,
  );

  stdout.writeln('currentSemester=${progress.currentSemester}');
  stdout.writeln('groups=${progress.groups.length}');
  stdout.writeln(
    'currentSemesterCourses=${progress.currentSemesterCourses.length}',
  );

  for (final group in progress.groups.take(3)) {
    stdout.writeln(
      '[group] ${group.title} required=${group.requiredCredits} courses=${group.courses.length}',
    );
    for (final course in group.courses.take(2)) {
      stdout.writeln(
        '  - ${course.code} ${course.name} ${course.credits} ${course.attribute} '
        'semester=${course.semester} status=${course.status} score=${course.score}',
      );
    }
  }
}

String _readSecret(String key, Map<String, String> localEnv) {
  return (Platform.environment[key] ?? localEnv[key] ?? '').trim();
}

Map<String, String> _loadLocalEnv() {
  final values = <String, String>{};
  var dir = Directory.current;

  while (true) {
    final file = File('${dir.path}${Platform.pathSeparator}.env.local');
    if (file.existsSync()) {
      values.addAll(_parseEnvFile(file));
    }

    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  return values;
}

Map<String, String> _parseEnvFile(File file) {
  final values = <String, String>{};

  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final separator = line.indexOf('=');
    if (separator <= 0) continue;

    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        value = value.substring(1, value.length - 1);
      }
    }

    values[key] = value;
  }

  return values;
}
