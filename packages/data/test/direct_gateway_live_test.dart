import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final credentials = _LiveCampusCredentials.load();
  final dormParams = _LiveDormParams.load();
  final skipReason = credentials.isComplete
      ? null
      : 'Set CAMPUS_TEST_USERNAME and CAMPUS_TEST_PASSWORD in the process '
          'environment or a local .env.local file to run live direct-school tests.';
  final dormSkipReason = dormParams.isComplete
      ? skipReason
      : 'Set CAMPUS_TEST_ELEC_BUILDID and CAMPUS_TEST_ELEC_ROOMID in the '
          'process environment or a local .env.local file to run live electricity tests.';

  group('DirectSchoolCampusGateway live', () {
    final gateway = DirectSchoolCampusGateway();

    test('queries schedule with real school data', () async {
      await _runLiveStep('schedule', () async {
        final result = await gateway.getSchedule(
          credentials.username,
          credentials.password,
        );
        expect(result.courses, isA<List>());
        expect(result.remark, isA<String>());
      });
    }, skip: skipReason);

    test('queries grades with real school data', () async {
      await _runLiveStep('grades', () async {
        final result = await gateway.getGrades(
          credentials.username,
          credentials.password,
        );
        expect(result.summary, isA<Map<String, String>>());
        expect(result.grades, isA<List>());
      });
    }, skip: skipReason);

    test('queries exams with real school data', () async {
      await _runLiveStep('exams', () async {
        final exams = await gateway.getExams(
          credentials.username,
          credentials.password,
        );
        expect(exams, isA<List>());
      });
    }, skip: skipReason);

    test('queries campus card balance with real school data', () async {
      await _runLiveStep('campus card balance', () async {
        final balance = await gateway.getCampusCardBalance(
          credentials.username,
          credentials.password,
        );
        _expectSuccessfulBalanceText(balance);
      });
    }, skip: skipReason);

    test('queries electricity balance with real school data', () async {
      await _runLiveStep('electricity balance', () async {
        final balance = await gateway.getElecBalance(
          credentials.username,
          credentials.password,
          dormParams: dormParams.toQueryParams(),
        );
        _expectSuccessfulBalanceText(balance);
      });
    }, skip: dormSkipReason);
  });
}

Future<void> _runLiveStep(
  String step,
  Future<void> Function() body,
) async {
  try {
    await body();
  } on CaptchaRequiredFailure {
    fail('$step requires captcha or manual security verification.');
  } on AuthInvalidFailure {
    fail('$step failed because the account, password, or ticket is invalid.');
  } on CampusFailure catch (error) {
    fail('$step failed with ${error.runtimeType}: ${error.message}');
  }
}

void _expectSuccessfulBalanceText(String value) {
  expect(value.trim(), isNotEmpty);
  expect(value, isNot(contains('失败')));
  expect(value, isNot(contains('授权失败')));
  expect(value, isNot(contains('未配置')));
}

class _LiveCampusCredentials {
  const _LiveCampusCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  bool get isComplete => username.isNotEmpty && password.isNotEmpty;

  static _LiveCampusCredentials load() {
    final localEnv = _loadLocalEnv();
    return _LiveCampusCredentials(
      username: _readSecret('CAMPUS_TEST_USERNAME', localEnv),
      password: _readSecret('CAMPUS_TEST_PASSWORD', localEnv),
    );
  }
}

class _LiveDormParams {
  const _LiveDormParams({
    required this.sysid,
    required this.areaid,
    required this.buildid,
    required this.roomid,
  });

  final String sysid;
  final String areaid;
  final String buildid;
  final String roomid;

  bool get isComplete => buildid.isNotEmpty && roomid.isNotEmpty;

  Map<String, String> toQueryParams() => {
        'sysid': sysid.isEmpty ? '1' : sysid,
        'areaid': areaid.isEmpty ? '1' : areaid,
        'buildid': buildid,
        'roomid': roomid,
      };

  static _LiveDormParams load() {
    final localEnv = _loadLocalEnv();
    return _LiveDormParams(
      sysid: _readSecret('CAMPUS_TEST_ELEC_SYSID', localEnv),
      areaid: _readSecret('CAMPUS_TEST_ELEC_AREAID', localEnv),
      buildid: _readSecret('CAMPUS_TEST_ELEC_BUILDID', localEnv),
      roomid: _readSecret('CAMPUS_TEST_ELEC_ROOMID', localEnv),
    );
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
