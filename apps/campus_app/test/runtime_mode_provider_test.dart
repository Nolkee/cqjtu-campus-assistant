import 'package:campus_app/providers/runtime_mode.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('resolveCampusRuntimeMode', () {
    test('defaults unknown or empty env values to localAndroid', () {
      expect(resolveCampusRuntimeMode(''), CampusRuntimeMode.localAndroid);
      expect(resolveCampusRuntimeMode('prod'), CampusRuntimeMode.localAndroid);
      expect(
        resolveCampusRuntimeMode('localAndroid'),
        CampusRuntimeMode.localAndroid,
      );
    });

    test('supports explicit self-hosted mode aliases', () {
      expect(
        resolveCampusRuntimeMode('selfHosted'),
        CampusRuntimeMode.selfHosted,
      );
      expect(
        resolveCampusRuntimeMode('self-hosted'),
        CampusRuntimeMode.selfHosted,
      );
      expect(
        resolveCampusRuntimeMode('remote_backend'),
        CampusRuntimeMode.selfHosted,
      );
      expect(resolveCampusRuntimeMode('backend'), CampusRuntimeMode.selfHosted);
    });
  });

  test('campusRuntimeModeProvider default is localAndroid', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(campusRuntimeModeProvider),
      CampusRuntimeMode.localAndroid,
    );
  });
}
