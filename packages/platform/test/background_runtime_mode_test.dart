import 'package:campus_platform/services/background_task.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBackgroundRuntimeMode', () {
    test('defaults unknown or empty values to localAndroid', () {
      expect(resolveBackgroundRuntimeMode(''), CampusRuntimeMode.localAndroid);
      expect(
        resolveBackgroundRuntimeMode('prod'),
        CampusRuntimeMode.localAndroid,
      );
      expect(
        resolveBackgroundRuntimeMode('localAndroid'),
        CampusRuntimeMode.localAndroid,
      );
    });

    test('supports self-hosted aliases', () {
      expect(
        resolveBackgroundRuntimeMode('selfHosted'),
        CampusRuntimeMode.selfHosted,
      );
      expect(
        resolveBackgroundRuntimeMode('self-hosted'),
        CampusRuntimeMode.selfHosted,
      );
      expect(
        resolveBackgroundRuntimeMode('remote_backend'),
        CampusRuntimeMode.selfHosted,
      );
    });
  });
}
