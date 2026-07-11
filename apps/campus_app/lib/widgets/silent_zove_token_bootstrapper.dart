import 'dart:async';

import 'package:campus_platform/services/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/providers.dart';

/// Silently warms up h-zove-token in background after user login.
/// It stays hidden in widget tree and does not block entering main pages.
class SilentZoveTokenBootstrapper extends ConsumerStatefulWidget {
  const SilentZoveTokenBootstrapper({super.key});

  @override
  ConsumerState<SilentZoveTokenBootstrapper> createState() =>
      _SilentZoveTokenBootstrapperState();
}

class _SilentZoveTokenBootstrapperState
    extends ConsumerState<SilentZoveTokenBootstrapper> {
  static const _studentIndexUrl =
      'https://zhxg.cqjtu.edu.cn/mobile/stuhall/studentindex';

  late final WebViewController _controller;
  Completer<void>? _pageLoadCompleter;
  Completer<String>? _tokenCompleter;
  String? _capturedZoveToken;

  bool _running = false;
  String? _runningUser;

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
          onPageFinished: (url) async {
            if (!(_pageLoadCompleter?.isCompleted ?? true)) {
              _pageLoadCompleter?.complete();
            }
            await _controller.runJavaScript(_hookScript);
            if (!mounted) return;
            if (url.contains('ids.cqjtu.edu.cn/authserver/login')) {
              final creds = ref.read(credentialsProvider);
              if (creds != null) {
                await _autofillAndSubmit(creds.username, creds.password);
              }
            }
          },
        ),
      );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeStart();
    });
  }

  Future<void> _maybeStart() async {
    if (!mounted) return;
    if (_running) return;
    final creds = ref.read(credentialsProvider);
    if (creds == null) return;

    final sessionService = ref.read(sessionServiceProvider);
    final cached = (await sessionService.loadZoveToken(creds.username))?.trim();
    if (cached != null && cached.isNotEmpty) return;

    _running = true;
    _runningUser = creds.username;
    unawaited(_bootstrap(creds.username, creds.password, sessionService));
  }

  Future<void> _bootstrap(
    String username,
    String password,
    SessionService sessionService,
  ) async {
    try {
      _capturedZoveToken = null;
      _tokenCompleter = Completer<String>();
      await _loadAndWait(_studentIndexUrl);
      await _controller.runJavaScript(_hookScript);
      await _reloadAndWait();

      final token = await _waitForToken(timeout: const Duration(seconds: 8));
      if (token != null && token.isNotEmpty) {
        await sessionService.saveZoveToken(username, token);
        if (!mounted) return;
        ref.read(sessionUpdateProvider.notifier).triggerRefresh();
      }
    } catch (_) {
      // Silent mode: ignore errors and let leave page handle fallback.
    } finally {
      _running = false;
    }
  }

  Future<void> _autofillAndSubmit(String username, String password) async {
    await _controller.runJavaScript('''
      (function () {
        var u = document.getElementById('username');
        var p = document.getElementById('password');
        if (u && p) {
          u.value = '${_escapeJs(username)}';
          p.value = '${_escapeJs(password)}';
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

  String _escapeJs(String input) {
    return input
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
  }

  Future<void> _loadAndWait(String url) async {
    _pageLoadCompleter = Completer<void>();
    await _controller.loadRequest(Uri.parse(url));
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

  Future<String?> _waitForToken({required Duration timeout}) async {
    final completer = _tokenCompleter;
    if (completer != null) {
      final token = await completer.future.timeout(
        timeout,
        onTimeout: () => '',
      );
      if (token.isNotEmpty) return token;
    }
    return _capturedZoveToken ?? _readToken();
  }

  Future<String?> _readToken() async {
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
    final creds = ref.watch(credentialsProvider);
    if (creds != null &&
        !_running &&
        (_runningUser == null || _runningUser != creds.username)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeStart();
      });
    }

    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: _controller),
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
