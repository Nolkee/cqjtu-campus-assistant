import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/providers.dart';

class CampusServiceWebViewPage extends ConsumerStatefulWidget {
  const CampusServiceWebViewPage({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  final String title;
  final String initialUrl;

  @override
  ConsumerState<CampusServiceWebViewPage> createState() =>
      _CampusServiceWebViewPageState();
}

class _CampusServiceWebViewPageState
    extends ConsumerState<CampusServiceWebViewPage> {
  late final WebViewController _controller;
  var _loadingProgress = 0;
  var _canGoBack = false;
  var _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Safari/537.36',
      )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _loadingProgress = progress);
          },
          onPageStarted: (_) => _refreshNavigationState(),
          onPageFinished: (url) async {
            await _refreshNavigationState();
            if (_shouldAutofill(url)) {
              await _autofillKnownCredentials();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _refreshNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  bool _shouldAutofill(String url) {
    return url.contains('ids.cqjtu.edu.cn/authserver/login') ||
        url.contains('jwgln.cqjtu.edu.cn/sjd') ||
        url.contains('jwzlapp.cqjtu.edu.cn');
  }

  Future<void> _autofillKnownCredentials() async {
    final credentials = ref.read(credentialsProvider);
    if (credentials == null || credentials.password.trim().isEmpty) return;

    final username = jsonEncode(credentials.username);
    final password = jsonEncode(credentials.password);
    await _controller.runJavaScript('''
      setTimeout(function () {
        var p = document.getElementById('password') ||
          document.querySelector('input[type="password"]');
        var u = document.getElementById('username') ||
          document.querySelector('input[name="username"]') ||
          document.querySelector('input[name="userNo"]') ||
          document.querySelector('input[type="text"]');
        if (u && p) {
          u.value = $username;
          p.value = $password;
          u.dispatchEvent(new Event('input', { bubbles: true }));
          p.dispatchEvent(new Event('input', { bubbles: true }));
          u.dispatchEvent(new Event('change', { bubbles: true }));
          p.dispatchEvent(new Event('change', { bubbles: true }));
        }
      }, 300);
    ''');
  }

  Future<void> _openExternal() async {
    final currentUrl = await _controller.currentUrl() ?? widget.initialUrl;
    final uri = Uri.tryParse(currentUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBack ? () => _controller.goBack() : null,
          ),
          IconButton(
            tooltip: '前进',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward ? () => _controller.goForward() : null,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            tooltip: '外部打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: _openExternal,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loadingProgress > 0 && _loadingProgress < 100)
            LinearProgressIndicator(value: _loadingProgress / 100),
        ],
      ),
    );
  }
}
