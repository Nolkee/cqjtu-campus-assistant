import 'dart:io';

import 'package:data/src/direct_school/direct_school_campus_gateway.dart';

/// Manual live smoke test for DirectSchoolCampusGateway.
///
/// This is intentionally outside `test/` so normal test runs never hit the
/// real school systems and never require real credentials. Run only when doing
/// manual verification:
///
/// ```powershell
/// # Option A: process environment variables
/// $env:CAMPUS_TEST_USERNAME='...'
/// $env:CAMPUS_TEST_PASSWORD='...'
///
/// # Option B: local .env.local file ignored by Git
/// CAMPUS_TEST_USERNAME=...
/// CAMPUS_TEST_PASSWORD=...
///
/// dart run tool/direct_gateway_e2e.dart
/// ```
Future<void> main() async {
  final localEnv = _loadLocalEnv();
  final username = _readSecret('CAMPUS_TEST_USERNAME', localEnv);
  final password = _readSecret('CAMPUS_TEST_PASSWORD', localEnv);

  if (username.isEmpty || password.isEmpty) {
    stderr.writeln(
      'Set CAMPUS_TEST_USERNAME and CAMPUS_TEST_PASSWORD in the process '
      'environment or a local .env.local file to run this live test.',
    );
    exitCode = 64;
    return;
  }

  final gateway = DirectSchoolCampusGateway();

  stdout.writeln('DirectSchoolCampusGateway live smoke test');

  await _runStep('schedule', () async {
    final result = await gateway.getSchedule(username, password);
    stdout.writeln('courses=${result.courses.length}');
    stdout.writeln('remarkLength=${result.remark.length}');
  });

  await _runStep('grades', () async {
    final result = await gateway.getGrades(username, password);
    stdout.writeln('grades=${result.grades.length}');
    stdout.writeln('summaryKeys=${result.summary.keys.join(',')}');
  });

  await _runStep('exams', () async {
    final exams = await gateway.getExams(username, password);
    stdout.writeln('exams=${exams.length}');
  });
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

Future<void> _runStep(String name, Future<void> Function() body) async {
  stdout.writeln('[$name] start');
  try {
    await body();
    stdout.writeln('[$name] ok');
  } catch (error) {
    stdout.writeln('[$name] failed: ${error.runtimeType}');
  }
}
