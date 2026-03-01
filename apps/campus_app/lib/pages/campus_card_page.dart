import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_service.dart';
import '../utils/providers.dart';

class CampusCardPage extends ConsumerWidget {
  const CampusCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园卡'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _BalanceCard(),
          SizedBox(height: 16),
          _QrCard(),
          SizedBox(height: 16),
          _RechargeCard(),
        ],
      ),
    );
  }
}

// ── 校园卡余额 ───────────────────────────────────────────────
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(campusCardBalanceProvider);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.blue.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                const Text(
                  '校园卡余额',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const Spacer(),
                // 刷新按钮
                GestureDetector(
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('正在刷新余额...'), duration: Duration(seconds: 1)),
                    );
                    try {
                      final creds = ref.read(credentialsProvider);
                      if (creds != null) {
                        // 先强制刷新后端缓存
                        await ref.read(apiServiceProvider).getCampusCardBalance(
                          creds.username, creds.password, forceRefresh: true,
                        );
                      }
                      ref.invalidate(campusCardBalanceProvider);
                      await ref.read(campusCardBalanceProvider.future);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('余额已更新')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('刷新失败：$e')),
                        );
                      }
                    }
                  },
                  child: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            balanceAsync.when(
              loading: () => const SizedBox(
                height: 42,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
              error: (e, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '获取失败',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.toString(),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
              data: (balance) => Text(
                balance,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '每 30 分钟自动刷新',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 消费二维码 ───────────────────────────────────────────────
class _QrCard extends ConsumerWidget {
  const _QrCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(payCodeProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Row(children: [
              Icon(Icons.qr_code_2, color: Colors.blue),
              SizedBox(width: 8),
              Text('消费二维码',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 20),
            tokenAsync.when(
              loading: () => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Column(children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text(e.toString(),
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => ref.invalidate(payCodeProvider),
                    child: const Text('重新获取')),
              ]),
              data: (token) => Column(children: [
                QrImageView(
                    data: token, size: 220, backgroundColor: Colors.white),
                const SizedBox(height: 12),
                const Text('二维码仅用于当次消费，请勿截图保存',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新二维码'),
                  onPressed: () => ref.invalidate(payCodeProvider),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 支付宝充值 ───────────────────────────────────────────────
class _RechargeCard extends ConsumerStatefulWidget {
  const _RechargeCard();

  @override
  ConsumerState<_RechargeCard> createState() => _RechargeCardState();
}

class _RechargeCardState extends ConsumerState<_RechargeCard>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _waitingForReturn = false;
  static const _quickAmounts = [20.0, 50.0, 100.0, 200.0];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForReturn && mounted) {
      _waitingForReturn = false;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('确认支付结果'),
          content: const Text('是否已完成支付宝付款？'),
          actions: [
            TextButton(
              onPressed: () async {
                // 1. 先关闭弹窗
                Navigator.pop(context);

                // 2. 静默触发刷新，去掉多余的“正在同步”提示
                try {
                  final creds = ref.read(credentialsProvider);
                  if (creds != null) {
                    await ref.read(apiServiceProvider).getCampusCardBalance(
                      creds.username,
                      creds.password,
                      forceRefresh: true,
                    );
                  }
                  
                  // 3. 击穿缓存后，令 Provider 失效，UI 自动获取最新余额
                  ref.invalidate(campusCardBalanceProvider);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('余额已更新')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('刷新余额失败，请稍后手动点击刷新图标')),
                    );
                  }
                }
              },
              child: const Text('已完成付款'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('还未付款'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount < 0.01 || amount > 500) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入正确的金额')));
      return;
    }

    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsProvider);
      if (creds == null) throw Exception('未登录');
      final responseData =
          await ref.read(apiServiceProvider).getCampusCardAlipayUrl(creds.username, amount);

      if (responseData.startsWith('alipays://') ||
          responseData.startsWith('alipay://')) {
        _waitingForReturn = true;
        await launchUrl(Uri.parse(responseData),
            mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _AlipayBridgePage(
              htmlData: responseData,
              onRealUrlReady: (realUrl) async {
                _waitingForReturn = true;
                await launchUrl(Uri.parse(realUrl),
                    mode: LaunchMode.externalApplication);
              },
            ),
          ));
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, color: Colors.green),
              SizedBox(width: 8),
              Text('校园卡充值（支付宝）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _quickAmounts
                  .map((a) => ActionChip(
                      label: Text('¥${a.toInt()}'),
                      onPressed: () => _ctrl.text = a.toStringAsFixed(0)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '充值金额（元）',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('跳转支付宝充值'),
                onPressed: _loading ? null : _pay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 隐形中转页：提交表单、拦截真实 URL、打开浏览器后自动关闭 ──────
class _AlipayBridgePage extends StatefulWidget {
  final String htmlData;
  final Future<void> Function(String realUrl) onRealUrlReady;

  const _AlipayBridgePage({
    required this.htmlData,
    required this.onRealUrlReady,
  });

  @override
  State<_AlipayBridgePage> createState() => _AlipayBridgePageState();
}

class _AlipayBridgePageState extends State<_AlipayBridgePage> {
  late final WebViewController controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) async {
          final url = request.url;

          if (url.startsWith('alipay') || url.startsWith('intent://')) {
            if (!_handled) {
              _handled = true;
              await widget.onRealUrlReady(url);
              if (mounted) Navigator.pop(context);
            }
            return NavigationDecision.prevent;
          }

          if (!url.contains('mapi.alipay.com') &&
              url.startsWith('https://') &&
              !_handled) {
            _handled = true;
            await widget.onRealUrlReady(url);
            if (mounted) Navigator.pop(context);
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(widget.htmlData, baseUrl: 'https://ecard.cqjtu.edu.cn');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('正在跳转支付宝...')),
      body: Stack(
        children: [
          // WebView 必须在 widget 树中才能真正加载 HTML 并触发导航拦截
          Offstage(
            offstage: true,
            child: WebViewWidget(controller: controller),
          ),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在准备支付，请稍候...'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}