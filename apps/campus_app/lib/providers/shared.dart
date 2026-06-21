import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 会话更新信号。
///
/// 调用 [triggerRefresh] 可触发所有 watch 此 provider 的
/// provider 重新加载（用于登录/退出/恢复后刷新数据）。
class SessionUpdateNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void triggerRefresh() => state++;
}

final sessionUpdateProvider = NotifierProvider<SessionUpdateNotifier, int>(
  SessionUpdateNotifier.new,
);

/// 校园卡页面二维码滚动信号。
final campusCardQrScrollSignalProvider = StateProvider<int>((ref) => 0);
