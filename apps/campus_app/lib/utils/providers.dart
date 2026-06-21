/// 向后兼容的 Provider 聚合导出。
///
/// 所有新代码应直接 import 对应的 feature provider 文件：
/// - `features/auth/auth_providers.dart`
/// - `features/schedule/schedule_providers.dart`
/// - `features/electricity/electricity_providers.dart`
/// - `features/campus_card/campus_card_providers.dart`
/// - `features/grades/grades_providers.dart`
/// - `features/exams/exams_providers.dart`
/// - `features/settings/settings_providers.dart`
/// - `providers/runtime_mode.dart`
/// - `providers/session.dart`
library;

export '../features/auth/auth_providers.dart';
export '../features/auth/web_login_binder.dart';
export '../features/schedule/schedule_providers.dart';
export '../features/electricity/electricity_providers.dart';
export '../features/campus_card/campus_card_providers.dart';
export '../features/grades/grades_providers.dart';
export '../features/exams/exams_providers.dart';
export '../features/settings/settings_providers.dart';
export '../providers/runtime_mode.dart';
export '../providers/session.dart';
export '../providers/shared.dart';
