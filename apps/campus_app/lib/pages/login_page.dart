import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// 移除报错的 import 'package:data/src/api_service.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_app/config/app_config.dart';
import '../utils/providers.dart';
import 'webview_login_page.dart'; // 确保你的同级目录下有这个文件

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  String _formatLoginError(Object error) {
    if (error is DioException) {
      final uri = error.requestOptions.uri;
      final host = uri.host.toLowerCase();
      final isLoopback =
          host == '127.0.0.1' || host == 'localhost' || host == '::1';
      if (error.type == DioExceptionType.connectionError && isLoopback) {
        return '当前后端地址是 ${uri.origin}，在 iPhone 上它指向“手机本机”，因此连接被拒绝。\n'
            '请点击下方「体验模式（Mock 数据）」进入应用，或重新打包并设置可访问的 BASE_URL。';
      }
    }
    return error.toString();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── 补全漏掉的保存凭据方法 ─────────────────────────────────────
  Future<void> _saveCredentialsAndFinish(
    String username,
    String password,
  ) async {
    debugPrint(
      '[LoginPage] save credentials username=$username passwordLen=${password.length}',
    );
    await ref.read(credentialServiceProvider).save(username, password);
    ref.read(credentialsProvider.notifier).set(username, password);
  }

  // ── 静默登录流程 ───────────────────────────────────────────
  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (!RegExp(r'^\d{12}$').hasMatch(username)) {
      setState(() => _error = '学号格式不正确（12位数字）');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 尝试静默获取课表来验证
      final sessionManager = ref.read(sessionManagerProvider);
      final sessionId = await sessionManager.refreshSessionId(username);
      debugPrint(
        '[LoginPage] silent login username=$username passwordLen=${password.length} sessionId=$sessionId',
      );
      await ref
          .read(apiServiceProvider)
          .getSchedule(
            username,
            password,
            sessionId: sessionId,
            forceRefresh: true,
          );
      // 成功则保存凭证并进入 App
      await _saveCredentialsAndFinish(username, password);
    } catch (e) {
      // 捕获异常，如果错误信息包含特定的关键字（比如验证码拦截或449状态码）
      final errorStr = e.toString();
      if (errorStr.contains('449') ||
          errorStr.contains('验证码') ||
          errorStr.contains('HTML') ||
          errorStr.contains('CAS')) {
        setState(() {
          _error = '系统要求安全验证，请点击下方「遇到验证码？点击此处使用网页登录」继续。';
          _loading = false;
        });
        return;
      } else {
        setState(() => _error = _formatLoginError(e));
      }
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<String> _bindWebLoginResult({
    required String username,
    required Map<String, dynamic> result,
  }) async {
    final api = ref.read(apiServiceProvider);
    final sessionManager = ref.read(sessionManagerProvider);
    // Explicit login should always bind web auth artifacts to a fresh
    // device-local session instead of reusing a cached one.
    var sessionId = await sessionManager.refreshSessionId(username);

    final ticket = result['ticket']?.toString() ?? '';
    final casCookies = result['casCookies']?.toString() ?? '';
    final jwgCookies = result['jwgCookies']?.toString() ?? '';
    final ecardCookies = result['ecardCookies']?.toString() ?? '';
    final zoveToken = result['zoveToken']?.toString() ?? '';

    Future<void> bindWithSession(String currentSessionId) async {
      await sessionManager.saveWebLoginArtifacts(
        username,
        ticket: ticket,
        casCookies: casCookies,
        jwgCookies: jwgCookies,
        ecardCookies: ecardCookies,
        zoveToken: zoveToken,
      );

      if (ticket.isNotEmpty) {
        await api.loginWithTicket(
          username,
          ticket,
          sessionId: currentSessionId,
        );
      }

      if (casCookies.isNotEmpty) {
        await api.injectCookies(
          username,
          'ids.cqjtu.edu.cn',
          casCookies,
          sessionId: currentSessionId,
        );
      }
      if (jwgCookies.isNotEmpty) {
        await api.injectCookies(
          username,
          'jwgln.cqjtu.edu.cn',
          jwgCookies,
          sessionId: currentSessionId,
        );
      }
      if (ecardCookies.isNotEmpty) {
        await api.injectCookies(
          username,
          'ecard.cqjtu.edu.cn',
          ecardCookies,
          sessionId: currentSessionId,
        );
      }
    }

    try {
      await bindWithSession(sessionId);
    } catch (error) {
      if (!sessionManager.isSessionExpiredError(error)) rethrow;
      sessionId = await sessionManager.refreshSessionId(username);
      await bindWithSession(sessionId);
    }

    ref.read(sessionUpdateProvider.notifier).triggerRefresh();
    return sessionId;
  }

  // ── WebView 介入流程 ───────────────────────────────────
  Future<void> _openWebViewLogin(String username, [String? password]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        // 【修改点】：把账号密码传给 WebView
        builder: (_) =>
            WebViewLoginPage(username: username, password: password ?? ""),
      ),
    );

    if (result == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sessionId = await _bindWebLoginResult(
        username: username,
        result: result,
      );

      final webPassword = result['password']?.toString() ?? '';
      debugPrint(
        '[LoginPage] webview result username=$username webPasswordLen=${webPassword.length} inputPasswordLen=${(password ?? '').length}',
      );
      var passwordToSave = webPassword.trim().isNotEmpty
          ? webPassword
          : (password ?? '');
      if (passwordToSave.trim().isEmpty) {
        final existing = await ref.read(credentialServiceProvider).load();
        if (existing != null &&
            existing.username == username &&
            existing.password.trim().isNotEmpty) {
          passwordToSave = existing.password;
        }
      }

      if (passwordToSave.trim().isEmpty) {
        setState(() {
          _error = '登录成功，但未获取到教务密码。请返回输入密码后重新登录一次（用于电费/校园卡）。';
        });
        return;
      }

      debugPrint(
        '[LoginPage] webview password resolved username=$username passwordLen=${passwordToSave.length} sessionId=$sessionId',
      );
      await _saveCredentialsAndFinish(username, passwordToSave);
      try {
        await ref
            .read(apiServiceProvider)
            .getSchedule(
              username,
              passwordToSave,
              sessionId: sessionId,
              forceRefresh: true,
            );
      } catch (_) {
        // Keep login successful even if this warm-up request fails.
      }
    } catch (e) {
      setState(() => _error = 'WebView 会话注入失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Mock 模式 ───────────────────────────────────────────
  Future<void> _enterMockMode() async {
    setState(() => _loading = true);
    try {
      const mockUser = 'mock_user';
      const mockPass = 'mock_pass';
      await _saveCredentialsAndFinish(mockUser, mockPass);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCredentialNoticeDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('账号与隐私说明'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 账号和密码仅用于向学校教务系统发起登录请求。'),
            SizedBox(height: 8),
            Text('2. 不会上传到开发者服务器，也不会用于与教务无关的数据处理。'),
            SizedBox(height: 8),
            Text('3. 为了免登录，凭据会使用系统加密能力保存在本机。'),
            SizedBox(height: 8),
            Text('4. 你可以在「我的 > 退出登录」随时清除本机保存的凭据。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school, size: 80, color: Colors.blue),
                const SizedBox(height: 12),
                Text(
                  'CQJTU Hub',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('使用教务网账号登录', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: Color(0xFF1D4ED8),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '账号密码仅用于教务登录，不会上传到开发者服务器。',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E3A8A),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _showCredentialNoticeDialog,
                          child: const Text(
                            '查看详情',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _usernameCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: '学号',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('登录', style: TextStyle(fontSize: 16)),
                  ),
                ),

                // ── 手动触发网页登录的备用入口（修复了之前的参数报错） ─────────────
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          final username = _usernameCtrl.text.trim();
                          if (!RegExp(r'^\d{12}$').hasMatch(username)) {
                            setState(() => _error = '请先输入正确的学号，再使用网页登录');
                            return;
                          }
                          _openWebViewLogin(username, _passwordCtrl.text);
                        },
                  child: const Text('遇到验证码？点击此处使用网页登录'),
                ),

                if (AppConfig.env == 'mock' || kDebugMode) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('体验模式（Mock 数据）'),
                      onPressed: _loading ? null : _enterMockMode,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '体验模式使用模拟数据，无需真实账号',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
