class AppConfig {
  /// 默认走 mock/本地时可以不传；你自用时用 --dart-define 传
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  /// 可选：环境标记（后面做 mock adapter 会用到）
  static const String env = String.fromEnvironment(
    'ENV',
    defaultValue: 'mock',
  ); // mock | prod
}
