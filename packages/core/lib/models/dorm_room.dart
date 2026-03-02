/// 园区类型（科学城校区）
enum DormGarden {
  deYuan('德园', '01'),
  liYuan('礼园', '05');

  final String label; // 显示名，如 "德园"
  final String suffix; // buildid 中间段，德园=01，礼园=05

  const DormGarden(this.label, this.suffix);
}

/// 根据园区 + 舍号生成 buildid
/// 规律：{舍号两位补零}00_{suffix}_C_{园区名}{舍号}舍
/// 示例：德园8舍 → "0800_01_C_德园8舍"
///        礼园6舍 → "0600_05_C_礼园6舍"
String buildDormId(DormGarden garden, int number) {
  final numStr = number.toString().padLeft(2, '0');
  return '${numStr}00_${garden.suffix}_C_${garden.label}${number}舍';
}

/// 楼栋名称，如 "德园8舍"
String buildingName(DormGarden garden, int number) =>
    '${garden.label}${number}舍';

// ── 可选舍号范围 ──────────────────────────────────────────────
const int kDormNumberMin = 1;
const int kDormNumberMax = 15;

/// 用户当前选中的宿舍（园区 + 舍号 + 房间号）
class DormRoom {
  final String campusName; // 如 "科学城校区"
  final DormGarden garden; // 德园 / 礼园
  final int buildingNumber; // 1-15
  final String roomNumber; // 4 位补零格式，如 "0305"

  const DormRoom({
    required this.campusName,
    required this.garden,
    required this.buildingNumber,
    required this.roomNumber,
  });

  /// 楼栋全名，如 "德园8舍"
  String get buildingFullName => buildingName(garden, buildingNumber);

  /// API 所需的 buildid
  String get buildid => buildDormId(garden, buildingNumber);

  /// 界面展示文字，如 "德园8舍 305室"
  String get displayName =>
      '$buildingFullName ${roomNumber.replaceFirst(RegExp(r'^0+'), '')}室';

  /// 拼接给 API 的查询参数
  Map<String, String> toQueryParams() => {
        'sysid': '1',
        'areaid': '1',
        'buildid': buildid,
        'roomid': roomNumber,
      };

  /// 序列化到 SharedPreferences
  Map<String, String> toPrefsMap() => {
        'dorm_campus': campusName,
        'dorm_garden': garden.name, // enum name，如 "deYuan"
        'dorm_number': buildingNumber.toString(),
        'dorm_roomid': roomNumber,
      };

  /// 从 SharedPreferences 反序列化，任意字段缺失或格式错误则返回 null
  static DormRoom? fromPrefsMap(Map<String, String?> map) {
    final campus = map['dorm_campus'];
    final gName = map['dorm_garden'];
    final numStr = map['dorm_number'];
    final roomid = map['dorm_roomid'];

    if (campus == null || gName == null || numStr == null || roomid == null) {
      return null;
    }

    DormGarden? garden;
    try {
      garden = DormGarden.values.byName(gName);
    } catch (_) {
      return null;
    }

    final number = int.tryParse(numStr);
    if (number == null || number < kDormNumberMin || number > kDormNumberMax) {
      return null;
    }

    return DormRoom(
      campusName: campus,
      garden: garden,
      buildingNumber: number,
      roomNumber: roomid,
    );
  }
}
