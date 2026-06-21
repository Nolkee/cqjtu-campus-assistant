/// 校园助手统一异常模型。
///
/// 所有数据源（直连学校系统、自部署后端）都应使用
/// 此异常分类，UI 层只处理这些业务异常，不直接处理
/// Dio、OkHttp、HTML 解析等底层异常。
sealed class CampusFailure implements Exception {
  const CampusFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 账号密码错误或 ticket 无效。
class AuthInvalidFailure extends CampusFailure {
  const AuthInvalidFailure([super.message = '账号或密码错误']);
}

/// 学校会话过期。
class SessionExpiredFailure extends CampusFailure {
  const SessionExpiredFailure([super.message = '登录会话已过期']);
}

/// 需要验证码或安全验证。
class CaptchaRequiredFailure extends CampusFailure {
  const CaptchaRequiredFailure([super.message = '需要验证码或安全验证']);
}

/// 网络异常（超时、连接失败等）。
class NetworkFailure extends CampusFailure {
  const NetworkFailure(super.message, {super.cause});
}

/// 学校系统页面结构或接口结构变化。
class SchoolSystemChangedFailure extends CampusFailure {
  const SchoolSystemChangedFailure([super.message = '学校系统页面结构已变化']);
}

/// 访问频率受限。
class RateLimitedFailure extends CampusFailure {
  const RateLimitedFailure([super.message = '访问频率受限，请稍后再试']);
}

/// 宿舍参数未配置。
class DormNotConfiguredFailure extends CampusFailure {
  const DormNotConfiguredFailure([super.message = '请先设置宿舍']);
}

/// 当前模式不支持该能力。
class UnsupportedModeFailure extends CampusFailure {
  const UnsupportedModeFailure(String feature) : super('当前模式不支持：$feature');
}
