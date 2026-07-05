import 'dart:io';

import 'package:data/data.dart';

Future<void> main(List<String> args) async {
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

  final semesters = args.isEmpty
      ? const ['', '2025-2026-2', '2025-2026-1', '2024-2025-2', '2024-2025-1']
      : args;
  final gateway = DirectSchoolCampusGateway();

  for (final semester in semesters) {
    final label = semester.isEmpty ? '<default/all>' : semester;
    stdout.writeln('semester=$label');

    await _run('schedule', () async {
      final result = await gateway.getSchedule(
        username,
        password,
        semester: semester.isEmpty ? null : semester,
        forceRefresh: true,
      );
      stdout.writeln(
        '  courses=${result.courses.length} remarkLength=${result.remark.length}',
      );
    });

    await _run('grades', () async {
      final result = await gateway.getGrades(
        username,
        password,
        semester: semester,
        forceRefresh: true,
      );
      stdout.writeln(
        '  grades=${result.grades.length} summary=${result.summary}',
      );
      final detailGrade =
          result.grades.where((grade) => grade.hasDetail).firstOrNull;
      if (detailGrade != null) {
        final detail = await gateway.getGradeDetail(
          username,
          password,
          grade: detailGrade,
          forceRefresh: true,
        );
        stdout.writeln(
          '  gradeDetail course=${detailGrade.courseName} items=${detail.items.length} total=${detail.totalScore}',
        );
      }
    });

    await _run('exams', () async {
      final exams = await gateway.getExams(
        username,
        password,
        semester: semester.isEmpty ? null : semester,
        forceRefresh: true,
      );
      stdout.writeln('  exams=${exams.length}');
    });
  }
}

Future<void> _run(String name, Future<void> Function() body) async {
  try {
    await body();
  } catch (error) {
    stdout.writeln('  $name failed: ${error.runtimeType}');
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
