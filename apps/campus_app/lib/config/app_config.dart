class AppConfig {
  /// 可选：环境标记（后面做 mock adapter 会用到）
  static const String env = String.fromEnvironment(
    'ENV',
    defaultValue: 'mock',
  ); // mock | prod

  static const String _definedBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );
  static const String _prodDefaultBaseUrl = 'http://47.109.25.240:8080';
  static const String _localDefaultBaseUrl = 'http://127.0.0.1:8080';

  /// prod 默认使用线上后端；mock/本地开发默认回落到 127.0.0.1。
  static String get baseUrl {
    final defined = _definedBaseUrl.trim();
    if (defined.isNotEmpty) return defined;
    return env == 'prod' ? _prodDefaultBaseUrl : _localDefaultBaseUrl;
  }
}
