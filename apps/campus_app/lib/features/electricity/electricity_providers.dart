import 'dart:async';

import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/schedule_widget_service.dart';
import 'package:core/models/dorm_room.dart';
import 'package:core/utils/polling_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/shared.dart';
import '../auth/auth_providers.dart';
import '../settings/settings_providers.dart';

class NoDormSetException implements Exception {
  @override
  String toString() => '请先设置宿舍';
}

final electricityProvider = FutureProvider<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final interval = pollingInterval();
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  ensureCredentialPassword(creds);

  final gateway = ref.watch(campusGatewayProvider);
  final dormAsync = ref.watch(dormRoomProvider);
  final dorm = await dormAsync.when(
    loading: () => ref.read(dormRoomProvider.future),
    error: (e, _) => Future<DormRoom?>.error(e),
    data: (d) => Future.value(d),
  );

  if (dorm == null) throw NoDormSetException();

  debugPrint('[FG] 查询电费: ${dorm.displayName}');
  final balance = await gateway.getElecBalance(
    creds.username,
    creds.password,
    dormParams: dorm.toQueryParams(),
  );
  debugPrint('[FG] 电费余额获取成功: $balance');
  NotificationService.checkAndNotify(balance);
  unawaited(ScheduleWidgetService.updateBalances(electricityBalance: balance));
  return balance;
});
