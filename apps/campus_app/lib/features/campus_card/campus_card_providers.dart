import 'package:campus_platform/services/schedule_widget_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../auth/auth_providers.dart';
import '../shared/cached_resource.dart';

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

final campusCardBalanceProvider =
    NotifierProvider<CampusCardBalanceNotifier, CachedResource<String>>(
      CampusCardBalanceNotifier.new,
    );

class CampusCardBalanceNotifier extends SimpleCachedResourceNotifier<String> {
  @override
  String get emptyData => '';

  @override
  String get cacheNamespace => 'campus_card_balance';

  @override
  Object? encode(String data) => data;

  @override
  String decode(Object? json) => json?.toString() ?? '';

  @override
  Future<String> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) {
    ensureCredentialPassword(credentials);
    debugPrint(
      '[FG] getCampusCardBalance request username=${_redactIdentifier(credentials.username)} passwordLen=${credentials.password.length}',
    );
    return ref
        .read(campusGatewayProvider)
        .getCampusCardBalance(
          credentials.username,
          credentials.password,
          forceRefresh: forceRefresh,
        );
  }

  @override
  Future<void> onData(String data, {required bool changed}) {
    return ScheduleWidgetService.updateBalances(campusCardBalance: data);
  }
}

class PayCodeState {
  const PayCodeState({
    this.token = '',
    this.isRefreshing = false,
    this.error,
    this.stackTrace,
    this.consecutiveFailures = 0,
  });

  final String token;
  final bool isRefreshing;
  final Object? error;
  final StackTrace? stackTrace;
  final int consecutiveFailures;

  bool get hasToken => token.isNotEmpty;
  bool get hasError => error != null;
  bool get isLoading => isRefreshing && !hasToken;
  bool get hasValue => hasToken;
  bool get shouldOfferManualRefresh => consecutiveFailures >= 3;

  R when<R>({
    required R Function(String token) data,
    required R Function() loading,
    required R Function(Object error, StackTrace stackTrace) error,
    bool skipLoadingOnRefresh = false,
    bool skipLoadingOnReload = false,
  }) {
    if (hasToken) return data(token);
    if (hasError) return error(this.error!, stackTrace ?? StackTrace.current);
    if (isRefreshing) return loading();
    return data('');
  }

  PayCodeState copyWith({
    Object? token = _unsetToken,
    bool? isRefreshing,
    Object? error,
    StackTrace? stackTrace,
    bool clearError = false,
    int? consecutiveFailures,
  }) {
    return PayCodeState(
      token: identical(token, _unsetToken) ? this.token : token as String,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : error ?? this.error,
      stackTrace: clearError ? null : stackTrace ?? this.stackTrace,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    );
  }
}

final payCodeProvider = NotifierProvider<PayCodeNotifier, PayCodeState>(
  PayCodeNotifier.new,
);

const Object _unsetToken = Object();

class PayCodeNotifier extends Notifier<PayCodeState> {
  Future<void>? _inflight;

  @override
  PayCodeState build() => const PayCodeState();

  Future<void> refresh({bool forceRefresh = false, bool throwOnError = false}) {
    final existing = _inflight;
    if (existing != null && !forceRefresh) return existing;

    final task = _refreshInternal(
      forceRefresh: forceRefresh,
      throwOnError: throwOnError,
    );
    _inflight = task.whenComplete(() {
      if (identical(_inflight, task)) _inflight = null;
    });
    return task;
  }

  Future<void> _refreshInternal({
    required bool forceRefresh,
    required bool throwOnError,
  }) async {
    final creds = ref.read(credentialsProvider);
    if (creds == null) return;
    ensureCredentialPassword(creds);

    state = state.copyWith(
      token: forceRefresh ? '' : _unsetToken,
      isRefreshing: true,
      clearError: true,
    );
    try {
      debugPrint(
        '[FG] getPayCodeToken request username=${_redactIdentifier(creds.username)} passwordLen=${creds.password.length}',
      );
      final token = await ref
          .read(campusGatewayProvider)
          .getPayCodeToken(creds.username, password: creds.password);
      state = PayCodeState(token: token);
    } catch (error, stackTrace) {
      state = state.copyWith(
        isRefreshing: false,
        error: error,
        stackTrace: stackTrace,
        consecutiveFailures: state.consecutiveFailures + 1,
      );
      if (throwOnError) Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void clear() => state = const PayCodeState();
}
