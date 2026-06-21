class AppConfig {
  /// Self-hosted backend URL.
  ///
  /// Only used when `ENV=selfHosted` or another self-hosted alias is enabled.
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  /// Runtime mode flag.
  ///
  /// Defaults to the Android local direct-school runtime. Use
  /// `--dart-define=ENV=selfHosted` to switch to the self-hosted backend.
  static const String env = String.fromEnvironment(
    'ENV',
    defaultValue: 'localAndroid',
  ); // localAndroid | selfHosted
}
