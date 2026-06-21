import 'dart:async';
import 'dart:developer' as dev;

import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';

import '../api_service.dart';
import '../campus_gateway.dart';
import 'self_hosted_session_manager.dart';

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

/// 自部署后端数据源。
///
/// 通过用户自部署的 Spring Boot 后端访问学校系统。
/// 使用 sessionId 隔离会话，由后端负责学校系统的
/// 登录、cookie 管理、HTML 解析和缓存。
///
/// 仅在 [CampusRuntimeMode.selfHosted] 模式下使用。
class SelfHostedCampusGateway implements CampusGateway {
  SelfHostedCampusGateway(this._api, this._sessionManager);

  final ApiService _api;
  final SelfHostedSessionManager _sessionManager;

  // ---- 内部辅助 ----

  bool _isSessionExpiredError(Object error) {
    if (error is! ApiException) return false;
    return error.code == 403 &&
        error.message.toLowerCase().contains('sessionid');
  }

  bool _isOneCardAuthFailure(Object error) {
    if (error is! ApiException) return false;
    if (error.code == 401) return true;
    if (error.code == 403 &&
        error.message.toLowerCase().contains('sessionid')) {
      return true;
    }
    if (error.code != 500) return false;
    final msg = error.message.toLowerCase();
    return msg.contains('auth') ||
        msg.contains('login') ||
        msg.contains('token') ||
        msg.contains('ecard') ||
        msg.contains('electric');
  }

  /// 带自动恢复的执行包装。
  ///
  /// 检测 session 过期，自动刷新 sessionId 并重试一次。
  Future<T> _withRecovery<T>({
    required String username,
    required Future<T> Function(String sessionId) request,
    Future<T> Function(String sessionId)? retryRequest,
    bool Function(Object error)? shouldRecoverOnError,
  }) async {
    var sessionId = await _sessionManager.ensureSessionId(username);
    try {
      return await request(sessionId);
    } catch (error) {
      final recoverable = _isSessionExpiredError(error) ||
          (shouldRecoverOnError?.call(error) ?? false);
      if (!recoverable) rethrow;

      dev.log(
        '[SelfHostedGateway] recovering session for ${_redactIdentifier(username)}: ${error.runtimeType}',
        name: 'SelfHostedGateway',
      );

      sessionId = await _sessionManager.refreshSessionId(username);
      await _sessionManager.restoreLoginState(username, sessionId);

      final retry = retryRequest ?? request;
      return await retry(sessionId);
    }
  }

  // ---- CampusGateway 实现 ----

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) => _api.getSchedule(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) => _api.getGrades(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) => _api.getExams(
        username,
        password,
        sessionId: sessionId,
        semester: semester,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) => _api.getElecBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
        dormParams: dormParams,
      ),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) => _api.getCampusCardBalance(
        username,
        password,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
      ),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    String? password,
    Map<String, String>? dormParams,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) => _api.rechargeElec(
        username,
        amount,
        sessionId: sessionId,
        dormParams: dormParams,
      ),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<String> getPayCodeToken(String username, {String? password}) {
    return _withRecovery(
      username: username,
      request: (sessionId) =>
          _api.getPayCodeToken(username, sessionId: sessionId),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }

  @override
  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    String? password,
  }) {
    return _withRecovery(
      username: username,
      request: (sessionId) =>
          _api.getCampusCardAlipayUrl(username, amount, sessionId: sessionId),
      shouldRecoverOnError: _isOneCardAuthFailure,
    );
  }
}
