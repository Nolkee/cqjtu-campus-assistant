const daytimePollingInterval = Duration(minutes: 15);
const nighttimePollingInterval = Duration(hours: 3);

bool isNightPollingWindow([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  return hour >= 23 || hour < 6;
}

Duration pollingInterval([DateTime? now]) {
  return isNightPollingWindow(now)
      ? nighttimePollingInterval
      : daytimePollingInterval;
}

bool shouldRunPolling({DateTime? now, int? lastRunAtMs}) {
  if (lastRunAtMs == null || lastRunAtMs <= 0) return true;
  final current = now ?? DateTime.now();
  final elapsed = current.millisecondsSinceEpoch - lastRunAtMs;
  return elapsed >= pollingInterval(current).inMilliseconds;
}
