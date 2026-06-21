import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:data/data.dart';

import '../utils/providers.dart';
import 'webview_login_page.dart';

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

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCredentialsAndFinish(
    String username,
    String password,
  ) async {
    await ref.read(credentialServiceProvider).save(username, password);
    ref.read(credentialsProvider.notifier).set(username, password);
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (!RegExp(r'^\d{12}$').hasMatch(username)) {
      setState(() => _error = '请输入12位学号');
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
      await _verifyLoginForCurrentMode(username, password);
      await _saveCredentialsAndFinish(username, password);
    } catch (error) {
      final errorText = error.toString();
      if (_requiresSecurityVerification(error)) {
        setState(() {
          _error = '需要安全验证，正在打开网页登录...';
          _loading = false;
        });
        await _openWebViewLogin(username, password);
      } else {
        setState(() => _error = errorText.replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyLoginForCurrentMode(
    String username,
    String password,
  ) async {
    final mode = ref.read(campusRuntimeModeProvider);
    if (mode == CampusRuntimeMode.selfHosted) {
      final sessionManager = ref.read(sessionManagerProvider);
      await sessionManager.verifyScheduleReady(username, password);
      return;
    }

    final gateway = ref.read(campusGatewayProvider);
    await gateway.getSchedule(username, password, forceRefresh: true);
  }

  bool _requiresSecurityVerification(Object error) {
    if (error is CaptchaRequiredFailure) return true;

    final sessionManager = ref.read(sessionManagerProvider);
    final errorText = error.toString();
    final lowerError = errorText.toLowerCase();
    return sessionManager.isSecurityVerificationError(error) ||
        sessionManager.isManualVerificationRequired(
          error,
          domain: SystemDomain.schedule,
        ) ||
        errorText.contains('449') ||
        lowerError.contains('captcha') ||
        lowerError.contains('cas') ||
        lowerError.contains('authserver/login') ||
        lowerError.contains('security');
  }

  Future<void> _openWebViewLogin(String username, [String? password]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            WebViewLoginPage(username: username, password: password ?? ''),
      ),
    );

    if (result == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(webLoginBinderProvider)
          .bind(username: username, result: result);

      final webPassword = result['password']?.toString() ?? '';
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
          _error = '网页登录成功，但未获取到密码，请手动输入后再试一次。';
        });
        return;
      }

      // Do not enter home until schedule domain is confirmed healthy.
      await _verifyLoginForCurrentMode(username, passwordToSave);
      await _saveCredentialsAndFinish(username, passwordToSave);
    } catch (error) {
      setState(() {
        _error = '网页登录处理失败: ${error.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school, size: 72, color: Colors.blue),
                const SizedBox(height: 12),
                Text(
                  'CQJTU Hub',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('使用教务账号登录'),
                const SizedBox(height: 24),
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
                const SizedBox(height: 14),
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
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
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
                        : const Text('登录'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          final username = _usernameCtrl.text.trim();
                          if (!RegExp(r'^\d{12}$').hasMatch(username)) {
                            setState(() => _error = '请先输入正确学号再使用网页登录');
                            return;
                          }
                          _openWebViewLogin(username, _passwordCtrl.text);
                        },
                  child: const Text('遇到验证问题？使用网页登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
