// packages/core/test/models/dorm_room_test.dart

import 'package:test/test.dart';
import 'package:core/models/dorm_room.dart';

void main() {
  group('buildDormId', () {
    test('德园 8 舍生成正确的 buildid', () {
      expect(buildDormId(DormGarden.deYuan, 8), '0800_01_C_德园8舍');
    });

    test('礼园 6 舍生成正确的 buildid', () {
      expect(buildDormId(DormGarden.liYuan, 6), '0600_05_C_礼园6舍');
    });

    test('个位数宿舍号补零为两位', () {
      expect(buildDormId(DormGarden.deYuan, 1), '0100_01_C_德园1舍');
    });

    test('两位数宿舍号不额外补零', () {
      expect(buildDormId(DormGarden.liYuan, 15), '1500_05_C_礼园15舍');
    });
  });

  group('DormRoom.toPrefsMap / fromPrefsMap 往返', () {
    final room = DormRoom(
      campusName: '科学城校区',
      garden: DormGarden.deYuan,
      buildingNumber: 8,
      roomNumber: '0305',
    );

    test('序列化后反序列化得到等价对象', () {
      final map = room.toPrefsMap();
      final restored = DormRoom.fromPrefsMap(map);
      expect(restored, isNotNull);
      expect(restored!.campusName, room.campusName);
      expect(restored.garden, room.garden);
      expect(restored.buildingNumber, room.buildingNumber);
      expect(restored.roomNumber, room.roomNumber);
    });

    test('displayName 格式正确（去掉前导 0）', () {
      expect(room.displayName, '德园8舍 305室');
    });

    test('buildid 与直接调用 buildDormId 一致', () {
      expect(room.buildid, buildDormId(room.garden, room.buildingNumber));
    });
  });

  group('DormRoom.fromPrefsMap 异常情况', () {
    test('缺失字段返回 null', () {
      expect(DormRoom.fromPrefsMap({}), isNull);
      expect(DormRoom.fromPrefsMap({'dorm_campus': '科学城校区'}), isNull);
    });

    test('非法 garden 名称返回 null', () {
      final bad = {
        'dorm_campus': '科学城校区',
        'dorm_garden': 'INVALID',
        'dorm_number': '8',
        'dorm_roomid': '0305',
      };
      expect(DormRoom.fromPrefsMap(bad), isNull);
    });

    test('宿舍号超出范围（>15）返回 null', () {
      final bad = {
        'dorm_campus': '科学城校区',
        'dorm_garden': 'deYuan',
        'dorm_number': '99',
        'dorm_roomid': '0305',
      };
      expect(DormRoom.fromPrefsMap(bad), isNull);
    });

    test('宿舍号为 0（<1）返回 null', () {
      final bad = {
        'dorm_campus': '科学城校区',
        'dorm_garden': 'deYuan',
        'dorm_number': '0',
        'dorm_roomid': '0305',
      };
      expect(DormRoom.fromPrefsMap(bad), isNull);
    });
  });
}
