import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:core/models/dorm_room.dart';

final dormServiceProvider =
    Provider<DormService>((ref) => DormService());

class DormService {
  static const _keys = [
    'dorm_campus',
    'dorm_garden',
    'dorm_number',
    'dorm_roomid',
  ];

  Future<void> save(DormRoom room) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in room.toPrefsMap().entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  Future<DormRoom?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {for (final k in _keys) k: prefs.getString(k)};
    return DormRoom.fromPrefsMap(map);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _keys) {
      await prefs.remove(k);
    }
    // 也清除旧版本的字段（兼容旧存档）
    for (final k in ['dorm_building', 'dorm_buildid', 'dorm_sysid', 'dorm_areaid']) {
      await prefs.remove(k);
    }
  }
}