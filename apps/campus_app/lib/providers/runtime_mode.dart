import 'package:campus_app/config/app_config.dart';
import 'package:campus_platform/services/session_service.dart';
import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(baseUrl: AppConfig.baseUrl);
});

/// Current campus runtime mode.
///
/// The ordinary release path must default to [CampusRuntimeMode.localAndroid]:
/// - `selfHosted` / `remoteBackend` / `backend` -> [CampusRuntimeMode.selfHosted]
/// - everything else -> [CampusRuntimeMode.localAndroid]
final campusRuntimeModeProvider = Provider<CampusRuntimeMode>((ref) {
  return resolveCampusRuntimeMode(AppConfig.env);
});

CampusRuntimeMode resolveCampusRuntimeMode(String env) {
  final normalized = env.trim().toLowerCase().replaceAll(RegExp(r'[-_]'), '');
  return switch (normalized) {
    'selfhosted' ||
    'remotebackend' ||
    'backend' => CampusRuntimeMode.selfHosted,
    _ => CampusRuntimeMode.localAndroid,
  };
}

/// Unified campus data source.
final campusGatewayProvider = Provider<CampusGateway>((ref) {
  final mode = ref.watch(campusRuntimeModeProvider);
  switch (mode) {
    case CampusRuntimeMode.selfHosted:
      final api = ref.read(apiServiceProvider);
      final sessionService = ref.read(sessionServiceProvider);
      final sessionManager = SelfHostedSessionManager(api, sessionService);
      return SelfHostedCampusGateway(api, sessionManager);
    case CampusRuntimeMode.localAndroid:
      final sessionService = ref.read(sessionServiceProvider);
      return DirectSchoolCampusGateway(sessionStore: sessionService);
  }
});
