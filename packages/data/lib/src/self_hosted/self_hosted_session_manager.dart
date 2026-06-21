import 'dart:developer' as dev;

import '../api_service.dart';

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

/// 自部署后端会话管理器。
///
/// 负责 sessionId 的创建、缓存、持久化，以及
/// 登录材料（ticket、cookie）的注入和恢复。
///
/// 仅在 [CampusRuntimeMode.selfHosted] 模式下使用。
class SelfHostedSessionManager {
  SelfHostedSessionManager(this._api, this._sessionService);

  final ApiService _api;
  final SelfHostedSessionStore _sessionService;
  final Map<String, String> _sessionIdCache = {};

  static const _casDomain = 'ids.cqjtu.edu.cn';
  static const _jwgDomain = 'jwgln.cqjtu.edu.cn';
  static const _ecardDomain = 'ecard.cqjtu.edu.cn';

  /// 获取有效的 sessionId，优先使用缓存和持久化存储。
  Future<String> ensureSessionId(String username) async {
    final cached = _sessionIdCache[username];
    if (cached != null && cached.isNotEmpty) return cached;
    final persisted = await _sessionService.loadSessionId(username);
    if (persisted != null && persisted.isNotEmpty) {
      _sessionIdCache[username] = persisted;
      return persisted;
    }
    return refreshSessionId(username);
  }

  /// 强制刷新 sessionId（创建新会话）。
  Future<String> refreshSessionId(String username) async {
    final sessionId = await _api.createSession(username);
    _sessionIdCache[username] = sessionId;
    await _sessionService.saveSessionId(username, sessionId);
    return sessionId;
  }

  /// 保存 WebView 登录产物。
  Future<void> saveWebLoginArtifacts(
    String username, {
    String? ticket,
    String? casCookies,
    String? jwgCookies,
    String? ecardCookies,
    String? zoveToken,
  }) async {
    if (ticket != null && ticket.isNotEmpty) {
      await _sessionService.saveTicket(username, ticket);
    }
    if (casCookies != null && casCookies.isNotEmpty) {
      await _sessionService.saveCasCookies(username, casCookies);
    }
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      await _sessionService.saveJwgCookies(username, jwgCookies);
    }
    if (ecardCookies != null && ecardCookies.isNotEmpty) {
      await _sessionService.saveEcardCookies(username, ecardCookies);
    }
    if (zoveToken != null && zoveToken.isNotEmpty) {
      await _sessionService.saveZoveToken(username, zoveToken);
    }
  }

  /// 恢复后端登录状态（注入 ticket 和 cookies）。
  Future<void> restoreLoginState(String username, String sessionId) async {
    final ticket = await _sessionService.loadTicket(username);
    if (ticket != null && ticket.isNotEmpty) {
      dev.log(
        '[SelfHostedSession] restoreLoginState use ticket username=${_redactIdentifier(username)}',
        name: 'SelfHostedSession',
      );
      await _api.loginWithTicket(username, ticket, sessionId: sessionId);
    }

    final casCookies = await _sessionService.loadCasCookies(username);
    if (casCookies != null && casCookies.isNotEmpty) {
      await _api.injectCookies(
        username,
        _casDomain,
        casCookies,
        sessionId: sessionId,
      );
    }

    final jwgCookies = await _sessionService.loadJwgCookies(username);
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      await _api.injectCookies(
        username,
        _jwgDomain,
        jwgCookies,
        sessionId: sessionId,
      );
    }

    final ecardCookies = await _sessionService.loadEcardCookies(username);
    if (ecardCookies != null && ecardCookies.isNotEmpty) {
      await _api.injectCookies(
        username,
        _ecardDomain,
        ecardCookies,
        sessionId: sessionId,
      );
    }
  }
}

/// 自部署后端会话存储接口。
///
/// 允许在 data 包中解耦平台特定的存储实现。
abstract class SelfHostedSessionStore {
  Future<String?> loadSessionId(String username);
  Future<void> saveSessionId(String username, String sessionId);

  Future<String?> loadTicket(String username);
  Future<void> saveTicket(String username, String ticket);

  Future<String?> loadCasCookies(String username);
  Future<void> saveCasCookies(String username, String cookies);

  Future<String?> loadJwgCookies(String username);
  Future<void> saveJwgCookies(String username, String cookies);

  Future<String?> loadEcardCookies(String username);
  Future<void> saveEcardCookies(String username, String cookies);

  Future<String?> loadZoveToken(String username);
  Future<void> saveZoveToken(String username, String token);
}
