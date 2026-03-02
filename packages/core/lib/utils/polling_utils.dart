/// 根据当前小时数返回轮询间隔。
///
/// - 凌晨 0–5 点（夜间）→ 3 小时（降频省电）
/// - 其他时间 → 30 分钟
///
/// 将此函数放在 [packages/core/lib/utils/polling_utils.dart]，
/// 方便 providers.dart 和单测共同引用。
Duration pollingInterval([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour >= 0 && hour < 6) return const Duration(hours: 3);
  return const Duration(minutes: 30);
}
