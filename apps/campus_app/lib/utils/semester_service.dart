import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final semesterServiceProvider = Provider<SemesterService>(
  (ref) => SemesterService(),
);

class SemesterService {
  SemesterService({SemesterCacheSnapshot? initialCache})
    : _cache = initialCache ?? const SemesterCacheSnapshot(),
      _cacheReady = initialCache != null;

  static const _key = 'semester_start_date';
  static const _semesterStartForKeyPrefix = 'semester_start_key_';
  static const _selectedSemesterKey = 'selected_semester_str';

  SemesterCacheSnapshot _cache;
  bool _cacheReady;

  bool get cacheReady => _cacheReady;

  static Future<SemesterCacheSnapshot> restoreSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final startsBySemester = <String, DateTime>{};

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_semesterStartForKeyPrefix)) continue;
      final semester = key.substring(_semesterStartForKeyPrefix.length);
      final date = DateTime.tryParse(prefs.getString(key) ?? '');
      if (semester.isNotEmpty && date != null) {
        startsBySemester[semester] = date;
      }
    }

    return SemesterCacheSnapshot(
      defaultStart: DateTime.tryParse(prefs.getString(_key) ?? ''),
      selectedSemester: prefs.getString(_selectedSemesterKey),
      startsBySemester: startsBySemester,
    );
  }

  /// 保存学期开始日期（当前/默认学期）
  Future<void> save(DateTime date) async {
    _cacheReady = true;
    _cache = _cache.copyWith(defaultStart: date);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, date.toIso8601String());
  }

  /// 读取学期开始日期（当前/默认学期），未设置返回 null
  Future<DateTime?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key);
    final date = DateTime.tryParse(str ?? '');
    _cacheReady = true;
    _cache = _cache.copyWith(defaultStart: date);
    return date;
  }

  DateTime? loadSync() => _cache.defaultStart;

  // ── 按学期 key 存取（用于非当前学期）────────────────────────
  // key 格式与成绩/考试的 semester 字符串一致，如 "2024-2025-1"
  // 存储的 SharedPreferences key 为 "semester_start_key_{semesterStr}"

  /// 保存指定学期的开学日期
  Future<void> saveForKey(String semesterKey, DateTime date) async {
    _cacheReady = true;
    final nextStarts = {..._cache.startsBySemester, semesterKey: date};
    _cache = _cache.copyWith(startsBySemester: nextStarts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_semesterStartForKeyPrefix$semesterKey',
      date.toIso8601String(),
    );
  }

  /// 读取指定学期的开学日期，未设置返回 null
  Future<DateTime?> loadForKey(String semesterKey) async {
    if (semesterKey.isEmpty) return load(); // 空字符串 = 当前学期
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('$_semesterStartForKeyPrefix$semesterKey');
    final date = DateTime.tryParse(str ?? '');
    _cacheReady = true;
    if (date != null) {
      _cache = _cache.copyWith(
        startsBySemester: {..._cache.startsBySemester, semesterKey: date},
      );
    }
    return date;
  }

  DateTime? loadForKeySync(String semesterKey) {
    if (semesterKey.isEmpty) return loadSync();
    return _cache.startsBySemester[semesterKey];
  }

  /// 持久化用户选中的学期字符串（如 "2024-2025-1"），null 表示恢复默认
  Future<void> saveSelectedSemester(String? value) async {
    _cacheReady = true;
    _cache = _cache.copyWith(selectedSemester: value);
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
    final value = prefs.getString(_selectedSemesterKey);
    _cacheReady = true;
    _cache = _cache.copyWith(selectedSemester: value);
    return value;
  }

  String? loadSelectedSemesterSync() => _cache.selectedSemester;
}

const Object _unset = Object();

class SemesterCacheSnapshot {
  const SemesterCacheSnapshot({
    this.defaultStart,
    this.selectedSemester,
    this.startsBySemester = const {},
  });

  final DateTime? defaultStart;
  final String? selectedSemester;
  final Map<String, DateTime> startsBySemester;

  SemesterCacheSnapshot copyWith({
    Object? defaultStart = _unset,
    Object? selectedSemester = _unset,
    Map<String, DateTime>? startsBySemester,
  }) {
    return SemesterCacheSnapshot(
      defaultStart: identical(defaultStart, _unset)
          ? this.defaultStart
          : defaultStart as DateTime?,
      selectedSemester: identical(selectedSemester, _unset)
          ? this.selectedSemester
          : selectedSemester as String?,
      startsBySemester: startsBySemester ?? this.startsBySemester,
    );
  }
}
