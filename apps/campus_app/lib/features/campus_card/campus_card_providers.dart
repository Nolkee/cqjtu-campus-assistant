import 'dart:async';

import 'package:campus_platform/services/schedule_widget_service.dart';
import 'package:core/utils/polling_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/shared.dart';
import '../auth/auth_providers.dart';

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

final campusCardBalanceProvider = FutureProvider<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final interval = pollingInterval();
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  ensureCredentialPassword(creds);

  final gateway = ref.watch(campusGatewayProvider);
  debugPrint(
    '[FG] getCampusCardBalance request username=${_redactIdentifier(creds.username)} passwordLen=${creds.password.length}',
  );
  final balance = await gateway.getCampusCardBalance(
    creds.username,
    creds.password,
  );
  unawaited(ScheduleWidgetService.updateBalances(campusCardBalance: balance));
  return balance;
});

final payCodeProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(sessionUpdateProvider);
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('Not logged in');
  ensureCredentialPassword(creds);

  final gateway = ref.watch(campusGatewayProvider);
  debugPrint(
    '[FG] getPayCodeToken request username=${_redactIdentifier(creds.username)} passwordLen=${creds.password.length}',
  );
  return gateway.getPayCodeToken(creds.username, password: creds.password);
});
