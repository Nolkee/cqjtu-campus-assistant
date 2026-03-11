import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum WebViewLoginMode { jwgSession, zoveTokenOnly }

class WebViewLoginPage extends StatefulWidget {
  final String username;
  final String password;
  final WebViewLoginMode mode;

  const WebViewLoginPage({
    super.key,
    required this.username,
    required this.password,
    this.mode = WebViewLoginMode.jwgSession,
  });

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  static const _loginUrl =
      'https://ids.cqjtu.edu.cn/authserver/login?service=http%3A%2F%2Fjwgln.cqjtu.edu.cn%2Fjsxsd%2Fsso.jsp';
  static const _ecardEntryUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/payele';
  static const _studentIndexUrl =
      'https://zhxg.cqjtu.edu.cn/mobile/stuhall/studentindex';
  static const _cookieChannel = MethodChannel('campus_app/cookie_manager');

  late final WebViewController _controller;
  bool _isHandled = false;
  bool _isLoading = true;
  String? _latestTicket;
  String? _capturedPassword;
  Completer<void>? _pageLoadedCompleter;
  Completer<String>? _tokenCompleter;
  String? _capturedZoveToken;
  bool _autoSubmitLogin = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LoginCredential',
        onMessageReceived: (msg) {
          final password = msg.message;
          if (password.isEmpty) return;
          _capturedPassword = password;
          debugPrint(
            '[WebViewLoginPage] captured password len=${password.length}',
          );
        },
      )
      ..addJavaScriptChannel(
        'ZoveToken',
        onMessageReceived: (msg) {
          final token = msg.message.trim();
          if (token.isEmpty) return;
          _capturedZoveToken = token;
          debugPrint(
            '[WebViewLoginPage] captured zoveToken len=${token.length}',
          );
          if (!(_tokenCompleter?.isCompleted ?? true)) {
            _tokenCompleter?.complete(token);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _captureTicket(url);
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            _captureTicket(url);
            if (!(_pageLoadedCompleter?.isCompleted ?? true)) {
              _pageLoadedCompleter?.complete();
            }
            if (mounted) setState(() => _isLoading = false);

            if (url.contains('authserver/login')) {
              await _installCredentialBridge();
              await _autofillCredentials();
              if (_autoSubmitLogin) {
                await _submitLoginForm();
              }
            }

            if (widget.mode == WebViewLoginMode.zoveTokenOnly) {
              await _controller.runJavaScript(_hookScript);
            }

            final isJwgln =
                url.startsWith('http://jwgln.cqjtu.edu.cn') ||
                url.startsWith('https://jwgln.cqjtu.edu.cn');
            final isZhxgMobile = url.startsWith(
              'https://zhxg.cqjtu.edu.cn/mobile/',
            );

            final shouldHandle = widget.mode == WebViewLoginMode.jwgSession
                ? isJwgln
                : isZhxgMobile;

            if (!_isHandled && shouldHandle) {
              _isHandled = true;
              await _extractAndReturnArtifacts();
            }
          },
        ),
      );

    _clearCookiesAndLoad();
  }

  void _captureTicket(String url) {
    final ticket = Uri.tryParse(url)?.queryParameters['ticket'];
    if (ticket != null && ticket.isNotEmpty) {
      _latestTicket = ticket;
    }
  }

  Future<void> _autofillCredentials() async {
    await _controller.runJavaScript('''
      setTimeout(function () {
        var u = document.getElementById('username');
        var p = document.getElementById('password');
        if (u && p) {
          u.value = '${widget.username}';
          p.value = '${widget.password}';
          u.dispatchEvent(new Event('input', { bubbles: true }));
          p.dispatchEvent(new Event('input', { bubbles: true }));
        }
      }, 300);
    ''');
  }

  Future<void> _clearCookiesAndLoad() async {
    try {
      await WebViewCookieManager().clearCookies();
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    } catch (_) {}

    if (mounted) {
      final url = widget.mode == WebViewLoginMode.jwgSession
          ? _loginUrl
          : _studentIndexUrl;
      await _controller.loadRequest(Uri.parse(url));
    }
  }

  Future<void> _extractAndReturnArtifacts() async {
    try {
      final casCookies = await _readCookiesWithRetry(
        'https://ids.cqjtu.edu.cn/authserver/',
      );
      String jwgCookies = '';
      String ecardCookies = '';
      if (widget.mode == WebViewLoginMode.jwgSession) {
        jwgCookies = await _readCookiesWithRetry(
          'https://jwgln.cqjtu.edu.cn/jsxsd/',
        );
        ecardCookies = await _captureEcardCookies();
      }

      if (casCookies.isEmpty) {
        _fail('未能获取到统一认证 Cookie，请重试');
        return;
      }

      final zoveToken = widget.mode == WebViewLoginMode.zoveTokenOnly
          ? await _captureZoveToken()
          : '';
      final ticket = widget.mode == WebViewLoginMode.jwgSession
          ? (_latestTicket ?? '')
          : '';

      if (mounted) {
        final casNames = _cookieNamesSummary(casCookies);
        final jwgNames = _cookieNamesSummary(jwgCookies);
        final ecardNames = _cookieNamesSummary(ecardCookies);
        debugPrint(
          '[WebViewLoginPage] return result mode=${widget.mode} ticketLen=${ticket.length} casCookieLen=${casCookies.length} casNames=$casNames jwgCookieLen=${jwgCookies.length} jwgNames=$jwgNames ecardCookieLen=${ecardCookies.length} ecardNames=$ecardNames zoveTokenLen=${zoveToken.length} passwordLen=${(_capturedPassword ?? widget.password).length}',
        );
        Navigator.of(context).pop({
          'ticket': ticket,
          'casCookies': casCookies,
          'jwgCookies': jwgCookies,
          'ecardCookies': ecardCookies,
          'zoveToken': zoveToken,
          'password': _capturedPassword ?? widget.password,
        });
      }
    } catch (e) {
      _fail('WebView 会话提取异常: $e');
    }
  }

  Future<String> _captureZoveToken() async {
    try {
      _capturedZoveToken = null;
      _tokenCompleter = Completer<String>();
      await _loadAndWait(_studentIndexUrl);
      await _controller.runJavaScript(_hookScript);
      await _loadAndWait(_studentIndexUrl);

      final byChannel = await _waitTokenFromChannel(
        timeout: const Duration(seconds: 8),
      );
      if (byChannel != null && byChannel.isNotEmpty) return byChannel;

      return _capturedZoveToken ?? await _readZoveToken() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> _captureEcardCookies() async {
    try {
      _autoSubmitLogin = true;
      const probeUrls = <String>[
        _ecardEntryUrl,
        'https://ecard.cqjtu.edu.cn/epay/h5/',
        'https://ecard.cqjtu.edu.cn/epay/',
        'https://ecard.cqjtu.edu.cn/',
      ];
      String bestEffortCookies = '';
      for (final url in probeUrls) {
        await _loadAndWait(url);
        await Future.delayed(const Duration(milliseconds: 600));
        final cookies = await _readCookiesWithRetry(
          url,
          maxAttempts: 6,
          baseDelayMs: 300,
        );
        if (cookies.isNotEmpty) {
          debugPrint(
            '[WebViewLoginPage] captured ecard cookies url=$url len=${cookies.length}',
          );
          bestEffortCookies = cookies;
          if (_hasLikelySessionCookie(cookies)) {
            return cookies;
          }
        }
      }
      return bestEffortCookies;
    } catch (_) {
      return '';
    } finally {
      _autoSubmitLogin = false;
    }
  }

  Future<String> _readCookiesWithRetry(
    String url, {
    int maxAttempts = 3,
    int baseDelayMs = 250,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final cookies =
          await _cookieChannel.invokeMethod<String>('getCookies', {
            'url': url,
          }) ??
          '';
      if (cookies.isNotEmpty) return cookies;
      await Future.delayed(Duration(milliseconds: baseDelayMs * (i + 1)));
    }
    return '';
  }

  Future<String?> _waitTokenFromChannel({required Duration timeout}) async {
    final completer = _tokenCompleter;
    if (completer == null) return null;
    final token = await completer.future.timeout(timeout, onTimeout: () => '');
    return token.isEmpty ? null : token;
  }

  Future<void> _loadAndWait(String url) async {
    _pageLoadedCompleter = Completer<void>();
    await _controller.loadRequest(Uri.parse(url));
    await _pageLoadedCompleter!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  Future<String?> _readZoveToken() async {
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

  Future<void> _installCredentialBridge() async {
    await _controller.runJavaScript('''
      (function () {
        if (window.__credential_bridge_installed__) return;
        window.__credential_bridge_installed__ = true;

        var pwdInput = document.getElementById('password');
        var form = document.querySelector('form');

        function reportPassword() {
          try {
            var v = pwdInput && pwdInput.value ? pwdInput.value : "";
            if (v) LoginCredential.postMessage(v);
          } catch (_) {}
        }

        if (pwdInput) {
          pwdInput.addEventListener('input', reportPassword);
          pwdInput.addEventListener('change', reportPassword);
          reportPassword();
        }
        if (form) {
          form.addEventListener('submit', reportPassword);
        }
      })();
    ''');
  }

  Future<void> _submitLoginForm() async {
    await _controller.runJavaScript('''
      (function () {
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

  bool _hasLikelySessionCookie(String cookies) {
    final lower = cookies.toLowerCase();
    return lower.contains('jsessionid=') ||
        lower.contains('sessionid=') ||
        lower.contains('mod_auth_cas=');
  }

  String _cookieNamesSummary(String cookies) {
    if (cookies.trim().isEmpty) return '[]';
    final names =
        cookies
            .split(';')
            .map((part) => part.trim())
            .where((part) => part.contains('='))
            .map((part) => part.split('=').first.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (names.isEmpty) return '[]';
    return '[${names.join(',')}]';
  }

  void _fail(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('安全验证'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

const String _hookScript = r'''
(() => {
  if (window.__zove_hooked__) return;
  window.__zove_hooked__ = true;

  function report(t) {
    if (!t) return;
    localStorage.setItem("zoveToken", t);
    window.__zoveToken = t;
    try { ZoveToken.postMessage(t); } catch (_) {}
  }

  const oldFetch = window.fetch;
  const oldSetHeader = XMLHttpRequest.prototype.setRequestHeader;

  window.fetch = function (input, init) {
    try {
      const req = input instanceof Request ? input : new Request(input, init);
      report(req.headers.get("h-zove-token"));
    } catch (_) {}
    return oldFetch.apply(this, arguments);
  };

  XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
    if (String(k).toLowerCase() === "h-zove-token") report(v);
    return oldSetHeader.apply(this, arguments);
  };
})();
''';
