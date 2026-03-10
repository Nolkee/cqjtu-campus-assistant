import 'dart:async';

import 'package:campus_platform/services/session_service.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/providers.dart';

class LeaveApplyPage extends ConsumerStatefulWidget {
  const LeaveApplyPage({super.key});

  @override
  ConsumerState<LeaveApplyPage> createState() => _LeaveApplyPageState();
}

class _LeaveApplyPageState extends ConsumerState<LeaveApplyPage> {
  static const _studentIndexUrl =
      'https://zhxg.cqjtu.edu.cn/mobile/stuhall/studentindex';
  static const _mobileLeaveUrl =
      'https://zhxg.cqjtu.edu.cn/mobile/leave/applyList';

  late final WebViewController _controller;
  Completer<void>? _pageLoadCompleter;
  String _lastUrl = '';
  Completer<String>? _tokenCompleter;
  String? _capturedZoveToken;

  bool _booting = true;
  bool _loadingPage = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ZoveToken',
        onMessageReceived: (msg) {
          final token = msg.message.trim();
          if (token.isEmpty) return;
          _capturedZoveToken = token;
          if (!(_tokenCompleter?.isCompleted ?? true)) {
            _tokenCompleter?.complete(token);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _lastUrl = url;
            if (mounted) setState(() => _loadingPage = true);
          },
          onPageFinished: (url) async {
            _lastUrl = url;
            if (!(_pageLoadCompleter?.isCompleted ?? true)) {
              _pageLoadCompleter?.complete();
            }
            await _controller.runJavaScript(_tokenHookScript);
            if (mounted) setState(() => _loadingPage = false);
          },
        ),
      );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openLeaveSite();
    });
  }

  Future<void> _openLeaveSite() async {
    if (mounted) {
      setState(() {
        _booting = true;
        _loadingPage = true;
        _error = null;
      });
    }

    try {
      final creds = ref.read(credentialsProvider);
      if (creds == null) throw Exception('Please login first.');

      final api = ref.read(apiServiceProvider);
      final sessionManager = ref.read(sessionManagerProvider);
      final sessionService = ref.read(sessionServiceProvider);
      final username = creds.username;

      var zoveToken = await _resolveZoveToken(
        username: username,
        sessionService: sessionService,
        forceRefresh: false,
      );
      if (zoveToken == null || zoveToken.isEmpty) {
        await _loadAndWait(_studentIndexUrl);
        return;
      }

      var opened = await _tryOpenLeaveDirect(zoveToken);
      if (!opened) {
        zoveToken = await _resolveZoveToken(
          username: username,
          sessionService: sessionService,
          forceRefresh: true,
        );
        if (zoveToken != null && zoveToken.isNotEmpty) {
          opened = await _tryOpenLeaveDirect(zoveToken);
        }
      }
      if (opened) return;

      // Fallback: keep backend entry flow as a compatibility path.
      var result = await sessionManager.runWithSessionRetry(
        username: username,
        request: (sessionId) => api.enterLeaveApplyList(
          username,
          sessionId: sessionId,
          zoveToken: zoveToken!,
        ),
      );

      if (result.tokenExpired) {
        zoveToken = await _resolveZoveToken(
          username: username,
          sessionService: sessionService,
          forceRefresh: true,
        );
        if (zoveToken == null || zoveToken.isEmpty) {
          await _loadAndWait(_studentIndexUrl);
          return;
        }

        result = await sessionManager.runWithSessionRetry(
          username: username,
          request: (sessionId) => api.enterLeaveApplyList(
            username,
            sessionId: sessionId,
            zoveToken: zoveToken!,
          ),
        );
      }

      if (!result.success) {
        throw Exception(
          result.msg.isEmpty ? 'Failed to enter leave module.' : result.msg,
        );
      }

      await _loadAndWait(
        _mobileLeaveUrl,
        headers: {'h-zove-token': zoveToken!},
      );
    } on ApiException catch (error) {
      _error = 'Request failed: ${error.message} (code=${error.code})';
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() {
          _booting = false;
          if (_error != null) _loadingPage = false;
        });
      }
    }
  }

  Future<String?> _resolveZoveToken({
    required String username,
    required SessionService sessionService,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = await sessionService.loadZoveToken(username);
      final token = cached?.trim() ?? '';
      if (token.isNotEmpty) return token;
    }

    final token = await _extractZoveTokenFromWebView();
    if (token != null && token.isNotEmpty) {
      await sessionService.saveZoveToken(username, token);
      return token;
    }
    return null;
  }

  Future<String?> _extractZoveTokenFromWebView() async {
    _capturedZoveToken = null;
    _tokenCompleter = Completer<String>();

    await _loadAndWait(_studentIndexUrl);
    if (_capturedZoveToken != null && _capturedZoveToken!.isNotEmpty) {
      return _capturedZoveToken;
    }
    final cached = await _readTokenFromPage();
    if (cached != null && cached.isNotEmpty) return cached;

    await _installTokenHook();

    // Reload once to trigger gateway requests after hook installation.
    await _reloadAndWait();
    final captured = await _waitForToken(timeout: const Duration(seconds: 6));
    if (captured != null && captured.isNotEmpty) {
      return captured;
    }

    final jsResult = await _controller.runJavaScriptReturningResult('''
      (function() {
        try {
          return localStorage.getItem("zoveToken") || window.__zoveToken || "";
        } catch (e) {
          return "";
        }
      })();
    ''');

    return _normalizeJsString(jsResult);
  }

  Future<bool> _tryOpenLeaveDirect(String zoveToken) async {
    await _loadAndWait(_mobileLeaveUrl, headers: {'h-zove-token': zoveToken});
    if (_isLeavePage(_lastUrl)) return true;
    if (_isAuthRedirect(_lastUrl)) return false;
    return _isLeavePage(_lastUrl);
  }

  bool _isLeavePage(String url) =>
      url.contains('zhxg.cqjtu.edu.cn/mobile/leave');

  bool _isAuthRedirect(String url) =>
      url.contains('ids.cqjtu.edu.cn/authserver/login') ||
      url.contains('zhxg.cqjtu.edu.cn/mobile/sso');

  Future<void> _installTokenHook() async {
    final creds = ref.read(credentialsProvider);
    if (creds != null && _isAuthRedirect(_lastUrl)) {
      await _controller.runJavaScript('''
        (function () {
          var u = document.getElementById('username');
          var p = document.getElementById('password');
          if (u && p) {
            u.value = '${_escapeJs(creds.username)}';
            p.value = '${_escapeJs(creds.password)}';
            u.dispatchEvent(new Event('input', { bubbles: true }));
            p.dispatchEvent(new Event('input', { bubbles: true }));
          }
          var btn =
            document.querySelector('#login_submit') ||
            document.querySelector('button[type="submit"]') ||
            document.querySelector('input[type="submit"]');
          if (btn && !btn.disabled) {
            btn.click();
          }
        })();
      ''');
    }

    await _controller.runJavaScript(_tokenHookScript);
  }

  String _escapeJs(String input) {
    return input
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
  }

  Future<String?> _waitForToken({required Duration timeout}) async {
    final completer = _tokenCompleter;
    if (completer != null) {
      final token = await completer.future.timeout(
        timeout,
        onTimeout: () => '',
      );
      if (token.isNotEmpty) return token;
    }
    return _capturedZoveToken ?? _readTokenFromPage();
  }

  Future<String?> _readTokenFromPage() async {
    final jsResult = await _controller.runJavaScriptReturningResult('''
      (function() {
        try {
          return localStorage.getItem("zoveToken") || window.__zoveToken || "";
        } catch (e) {
          return "";
        }
      })();
    ''');
    return _normalizeJsString(jsResult);
  }

  Future<void> _loadAndWait(String url, {Map<String, String>? headers}) async {
    _pageLoadCompleter = Completer<void>();
    await _controller.loadRequest(
      Uri.parse(url),
      headers: headers ?? const <String, String>{},
    );
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  Future<void> _reloadAndWait() async {
    _pageLoadCompleter = Completer<void>();
    await _controller.runJavaScript('location.reload();');
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  String? _normalizeJsString(Object? value) {
    if (value == null) return null;
    var text = value.toString().trim();
    if (text == 'null' || text == 'undefined') return null;
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    text = text.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('请假申请'),
        actions: [
          IconButton(
            onPressed: _booting ? null : _openLeaveSite,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 44,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _openLeaveSite,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_booting || _loadingPage)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

const String _tokenHookScript = r'''
(function () {
  if (window.__zove_hooked__) return;
  window.__zove_hooked__ = true;

  function report(t) {
    if (!t) return;
    localStorage.setItem("zoveToken", t);
    window.__zoveToken = t;
    try { ZoveToken.postMessage(t); } catch (_) {}
  }

  const oldFetch = window.fetch;
  window.fetch = function(input, init) {
    try {
      const req = input instanceof Request ? input : new Request(input, init);
      report(req.headers.get('h-zove-token'));
    } catch (_) {}
    return oldFetch.apply(this, arguments);
  };

  const oldSetHeader = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function(k, v) {
    if (String(k).toLowerCase() === 'h-zove-token') report(v);
    return oldSetHeader.apply(this, arguments);
  };
})();
''';
