import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewLoginPage extends StatefulWidget {
  // 接收传进来的账号和密码
  final String username;
  final String password;

  const WebViewLoginPage({
    super.key,
    required this.username,
    required this.password,
  });

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  static const _loginUrl =
      'https://ids.cqjtu.edu.cn/authserver/login?service=http%3A%2F%2Fjwgln.cqjtu.edu.cn%2Fjsxsd%2Fsso.jsp';
  static const _cookieChannel = MethodChannel('campus_app/cookie_manager');

  late final WebViewController _controller;
  bool _isHandled = false;
  bool _isLoading = true;
  String? _latestTicket;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _captureTicket(url);
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            _captureTicket(url);
            if (mounted) setState(() => _isLoading = false);

            // 1. 【新增】：如果停留在 CAS 登录页，自动注入 JS 填充账号密码！
            // 这样你再也不用输入第二次密码，只需要手动滑一下验证码即可。
            if (url.contains('authserver/login')) {
              await _controller.runJavaScript('''
                setTimeout(function() {
                    var u = document.getElementById('username');
                    var p = document.getElementById('password');
                    if(u && p) {
                        u.value = '${widget.username}';
                        p.value = '${widget.password}';
                        // 触发前端框架的事件，让网页知道内容已改变
                        u.dispatchEvent(new Event('input', { bubbles: true }));
                        p.dispatchEvent(new Event('input', { bubbles: true }));
                    }
                }, 300); // 稍微延迟确保 DOM 加载完毕
              ''');
            }

            // 2. 判断是否登录成功（必须用 startsWith 确保是真的跳回了教务系统）
            final isJwgln =
                url.startsWith('http://jwgln.cqjtu.edu.cn') ||
                url.startsWith('https://jwgln.cqjtu.edu.cn');
            if (!_isHandled && isJwgln) {
              _isHandled = true;
              await _extractAndReturnAllCookies();
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

  Future<void> _clearCookiesAndLoad() async {
    try {
      // 不仅清空 Cookie，还要清空 WebView 的本地缓存和 LocalStorage，做到 100% 干净
      await WebViewCookieManager().clearCookies();
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    } catch (_) {}

    if (mounted) {
      await _controller.loadRequest(Uri.parse(_loginUrl));
    }
  }

  Future<void> _extractAndReturnAllCookies() async {
    try {
      final casCookies = await _cookieChannel.invokeMethod<String>(
        'getCookies',
        {'url': 'https://ids.cqjtu.edu.cn/authserver/'},
      );
      final jwgCookies = await _cookieChannel.invokeMethod<String>(
        'getCookies',
        {'url': 'https://jwgln.cqjtu.edu.cn/jsxsd/'},
      );

      if (casCookies == null || casCookies.isEmpty) {
        _fail('未能获取到全局授权凭证，请重试');
        return;
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop({
          'ticket': _latestTicket ?? '',
          'casCookies': casCookies,
          'jwgCookies': jwgCookies ?? '',
        });
      }
    } catch (e) {
      _fail('Cookie 提取异常: $e');
    }
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
