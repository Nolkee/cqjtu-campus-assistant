
import 'dart:io';
import 'package:data/data.dart';

Future<void> main() async {
  final localEnv = _loadLocalEnv();
  final username = _readSecret('CAMPUS_TEST_USERNAME', localEnv);
  final password = _readSecret('CAMPUS_TEST_PASSWORD', localEnv);
  if (username.isEmpty || password.isEmpty) {
    stderr.writeln('missing credentials');
    exitCode = 64;
    return;
  }
  final g = DirectSchoolCampusGateway();
  Future<void> step(String name, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      stdout.writeln('$name FAILED: $e');
    }
  }

  await step('schedule', () async {
    final r = await g.getSchedule(username, password, forceRefresh: true);
    stdout.writeln('schedule OK courses=${r.courses.length}');
  });
  await step('grades', () async {
    final r = await g.getGrades(username, password, forceRefresh: true);
    stdout.writeln('grades OK count=${r.grades.length} summary=${r.summary}');
  });
  await step('exams', () async {
    final r = await g.getExams(username, password, forceRefresh: true);
    stdout.writeln('exams OK count=${r.length}');
  });
  await step('card', () async {
    final r = await g.getCampusCardBalance(username, password, forceRefresh: true);
    stdout.writeln('card OK balance=$r');
  });
  await step('payCode', () async {
    final r = await g.getPayCodeToken(username, password: password);
    final preview = r.length <= 24 ? r : '${r.substring(0, 24)}...';
    stdout.writeln('payCode OK len=${r.length} preview=$preview');
  });
  await step('studyProgress', () async {
    final r = await g.getStudyProgress(username, password, forceRefresh: true);
    stdout.writeln('studyProgress OK type=${r.runtimeType} $r');
  });
  await step('elec', () async {
    final r = await g.getElecBalance(username, password, forceRefresh: true);
    stdout.writeln('elec OK balance=$r');
  });
}

Map<String, String> _loadLocalEnv() {
  final candidates = <File>[
    File('.env.local'),
    File('../.env.local'),
    File('../../.env.local'),
  ];
  final env = <String, String>{};
  for (final file in candidates) {
    if (!file.existsSync()) continue;
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
  }
  return env;
}

String _readSecret(String key, Map<String, String> localEnv) {
  final fromEnv = Platform.environment[key]?.trim() ?? '';
  if (fromEnv.isNotEmpty) return fromEnv;
  return localEnv[key]?.trim() ?? '';
}
