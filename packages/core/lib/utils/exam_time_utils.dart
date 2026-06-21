/// 考试时间解析工具。
///
/// 将学校系统返回的考试时间字符串（如 "2026年6月19日 08:20-10:00"）
/// 解析为结构化起止时间。

({DateTime start, DateTime end})? parseExamTime(String raw) {
  final text = raw.replaceAll('：', ':').trim();
  if (text.isEmpty) return null;

  final dateMatch = RegExp(
    r'(\d{4})\s*(?:年|-|/|\.)\s*(\d{1,2})\s*(?:月|-|/|\.)\s*(\d{1,2})\s*(?:日)?',
  ).firstMatch(text);
  final timeMatch = RegExp(
    r'(\d{1,2}):(\d{2})\s*(?:-|~|—|–|至|到)\s*(\d{1,2}):(\d{2})',
  ).firstMatch(text);
  if (dateMatch == null || timeMatch == null) return null;

  final year = int.tryParse(dateMatch.group(1)!);
  final month = int.tryParse(dateMatch.group(2)!);
  final day = int.tryParse(dateMatch.group(3)!);
  final startHour = int.tryParse(timeMatch.group(1)!);
  final startMinute = int.tryParse(timeMatch.group(2)!);
  final endHour = int.tryParse(timeMatch.group(3)!);
  final endMinute = int.tryParse(timeMatch.group(4)!);
  if (year == null ||
      month == null ||
      day == null ||
      startHour == null ||
      startMinute == null ||
      endHour == null ||
      endMinute == null) {
    return null;
  }

  final start = DateTime(year, month, day, startHour, startMinute);
  var end = DateTime(year, month, day, endHour, endMinute);
  if (!end.isAfter(start)) end = start.add(const Duration(hours: 2));
  return (start: start, end: end);
}

/// 计算 [date] 相对于学期开始 [semesterStart] 的周次（从 1 开始）。
/// 如果 [date] 在学期开始之前，返回 0。
int weekOfDate(DateTime semesterStart, DateTime date) {
  final semesterMonday = DateTime(
    semesterStart.year,
    semesterStart.month,
    semesterStart.day,
  ).subtract(Duration(days: semesterStart.weekday - 1));
  final targetDay = DateTime(date.year, date.month, date.day);
  if (targetDay.isBefore(semesterMonday)) return 0;
  return targetDay.difference(semesterMonday).inDays ~/ 7 + 1;
}
