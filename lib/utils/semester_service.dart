import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final semesterServiceProvider =
    Provider<SemesterService>((ref) => SemesterService());

class SemesterService {
  static const _key = 'semester_start_date';

  /// 保存学期开始日期（当前/默认学期）
  Future<void> save(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, date.toIso8601String());
  }

  /// 读取学期开始日期（当前/默认学期），未设置返回 null
  Future<DateTime?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  // ── 按学期 key 存取（用于非当前学期）────────────────────────
  // key 格式与成绩/考试的 semester 字符串一致，如 "2024-2025-1"
  // 存储的 SharedPreferences key 为 "semester_start_key_{semesterStr}"

  /// 保存指定学期的开学日期
  Future<void> saveForKey(String semesterKey, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'semester_start_key_$semesterKey', date.toIso8601String());
  }

  /// 读取指定学期的开学日期，未设置返回 null
  Future<DateTime?> loadForKey(String semesterKey) async {
    if (semesterKey.isEmpty) return load(); // 空字符串 = 当前学期
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('semester_start_key_$semesterKey');
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  // ── 当前选中的学期字符串持久化（用于 App 重启后恢复状态）─────────
  static const _selectedSemesterKey = 'selected_semester_str';

  /// 持久化用户选中的学期字符串（如 "2024-2025-1"），null 表示恢复默认
  Future<void> saveSelectedSemester(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_selectedSemesterKey);
    } else {
      await prefs.setString(_selectedSemesterKey, value);
    }
  }

  /// 读取持久化的学期字符串，未设置返回 null
  Future<String?> loadSelectedSemester() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedSemesterKey);
  }
}