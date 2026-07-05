import 'dart:async';

import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/schedule_widget_service.dart';
import 'package:core/models/dorm_room.dart';
import 'package:core/utils/polling_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../auth/auth_providers.dart';
import '../settings/settings_providers.dart';
import '../shared/cached_resource.dart';

class NoDormSetException implements Exception {
  @override
  String toString() => '请先设置宿舍';
}

final electricityProvider =
    NotifierProvider<ElectricityNotifier, CachedResource<String>>(
      ElectricityNotifier.new,
    );

class ElectricityNotifier extends SimpleCachedResourceNotifier<String> {
  @override
  String get emptyData => '';

  @override
  String get cacheNamespace => 'electricity_balance';

  @override
  String? get cacheScope {
    final dorm = ref.read(dormRoomProvider).valueOrNull;
    if (dorm == null) return 'no_dorm';
    final params = dorm.toQueryParams();
    return '${params['buildid'] ?? ''}:${params['roomid'] ?? ''}';
  }

  @override
  Duration get automaticRefreshInterval => pollingInterval();

  @override
  Object? encode(String data) => data;

  @override
  String decode(Object? json) => json?.toString() ?? '';

  @override
  void listenDependencies() {
    ref.listen<AsyncValue<DormRoom?>>(dormRoomProvider, (_, next) {
      unawaited(restoreCachedThenRefresh());
    });
  }

  @override
  Future<String> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) async {
    ensureCredentialPassword(credentials);

    final dormAsync = ref.read(dormRoomProvider);
    final dorm = await dormAsync.when(
      loading: () => ref.read(dormRoomProvider.future),
      error: (e, _) => Future<DormRoom?>.error(e),
      data: (d) => Future.value(d),
    );

    if (dorm == null) throw NoDormSetException();

    debugPrint('[FG] query electricity: ${dorm.displayName}');
    return ref
        .read(campusGatewayProvider)
        .getElecBalance(
          credentials.username,
          credentials.password,
          forceRefresh: forceRefresh,
          dormParams: dorm.toQueryParams(),
        );
  }

  @override
  Future<void> onData(String data, {required bool changed}) async {
    NotificationService.checkAndNotify(data);
    await ScheduleWidgetService.updateBalances(electricityBalance: data);
  }
}
