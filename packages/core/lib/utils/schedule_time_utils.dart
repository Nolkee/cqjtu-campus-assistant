/// 课表节次时间工具。
///
/// 重庆交通大学作息时间表。
/// 用于将考试时间映射到课表节次。

/// 每小节的起止分钟数（从 00:00 开始计算）。
const Map<int, ({int start, int end})> slotMinuteRanges = {
  1: (start: 8 * 60 + 20, end: 9 * 60),
  2: (start: 9 * 60 + 5, end: 9 * 60 + 45),
  3: (start: 10 * 60, end: 10 * 60 + 40),
  4: (start: 10 * 60 + 45, end: 11 * 60 + 25),
  5: (start: 11 * 60 + 30, end: 12 * 60 + 10),
  6: (start: 14 * 60, end: 14 * 60 + 40),
  7: (start: 14 * 60 + 45, end: 15 * 60 + 25),
  8: (start: 15 * 60 + 40, end: 16 * 60 + 20),
  9: (start: 16 * 60 + 25, end: 17 * 60 + 5),
  10: (start: 17 * 60 + 10, end: 17 * 60 + 50),
  11: (start: 19 * 60, end: 19 * 60 + 40),
  12: (start: 19 * 60 + 45, end: 20 * 60 + 25),
  13: (start: 20 * 60 + 30, end: 21 * 60 + 10),
};

int _minutesOfDay(DateTime value) => value.hour * 60 + value.minute;

/// 找到最接近 [start] 时间的起始节次。
int nearestStartSlot(DateTime start) {
  final minutes = _minutesOfDay(start);
  return slotMinuteRanges.entries.reduce((best, next) {
    final bestDiff = (best.value.start - minutes).abs();
    final nextDiff = (next.value.start - minutes).abs();
    return nextDiff < bestDiff ? next : best;
  }).key;
}

/// 找到 [end] 时间对应的结束节次。
int endSlotFor(DateTime end) {
  final minutes = _minutesOfDay(end);
  for (final entry in slotMinuteRanges.entries) {
    if (entry.value.end >= minutes) return entry.key;
  }
  return slotMinuteRanges.keys.last;
}
