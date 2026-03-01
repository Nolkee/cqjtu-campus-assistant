import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_service.dart';
import '../utils/providers.dart';
import 'package:campus_platform/services/notification_service.dart';
import '../widgets/error_view.dart';

class ElectricityPage extends ConsumerWidget {
  const ElectricityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(electricityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('电费监控'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '预警设置',
            onPressed: () => showDialog(
                context: context,
                builder: (_) => const _ThresholdDialog()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('正在获取最新电量...'), duration: Duration(seconds: 1)),
              );
      
              try {
                final creds = ref.read(credentialsProvider);
                if (creds != null) {
                  final dorm = ref.read(dormRoomProvider).valueOrNull;
                  await ref.read(apiServiceProvider)
                      .getElecBalance(creds.username, creds.password,
                          forceRefresh: true,
                          dormParams: dorm?.toQueryParams());
                }
                ref.invalidate(electricityProvider);
                await ref.read(electricityProvider.future);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('电量已更新')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('刷新失败，请检查网络')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          balanceAsync.when(
            loading: () => const _BalanceSkeleton(),
            error: (e, _) => ErrorView(
              message: e.toString(),
              onRetry: () => ref.invalidate(electricityProvider),
            ),
            data: (balance) => _BalanceCard(balance: balance),
          ),
          const SizedBox(height: 16),
          const _RechargeCard(),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(children: [
          const Icon(Icons.bolt, size: 52, color: Colors.amber),
          const SizedBox(height: 8),
          const Text('当前剩余电量',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            balance,
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('每 30 分钟自动刷新',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) => const Card(
        child: SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator())),
      );
}

class _RechargeCard extends ConsumerStatefulWidget {
  const _RechargeCard();

  @override
  ConsumerState<_RechargeCard> createState() => _RechargeCardState();
}

class _RechargeCardState extends ConsumerState<_RechargeCard> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  static const _quickAmounts = [10.0, 20.0, 50.0, 100.0];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _recharge() async {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount < 0.01 || amount > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入正确的金额（0.01 ~ 200 元）')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认充值'),
        content:
            Text('即将为寝室充值电费 ¥${amount.toStringAsFixed(2)}，确认扣款吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsProvider);
      if (creds == null) throw Exception('未登录');
      final msg = await ref.read(apiServiceProvider).rechargeElec(creds.username, amount);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        ref.invalidate(electricityProvider);
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.electric_bolt, color: Colors.amber),
            SizedBox(width: 8),
            Text('电费充值（校园卡扣款）',
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
              icon: const Icon(Icons.payment, size: 18),
              label: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('立即充值'),
              onPressed: _loading ? null : _recharge,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ThresholdDialog extends StatefulWidget {
  const _ThresholdDialog();

  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  double _elecValue = NotificationService.defaultElecThreshold;
  double _cardValue = NotificationService.defaultCardThreshold;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      NotificationService.getElecThreshold(),
      NotificationService.getCardThreshold(),
    ]).then((values) {
      if (mounted) {
        setState(() {
          _elecValue = values[0];
          _cardValue = values[1];
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('余额预警设置'),
      content: _loaded
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              // 电费阈值
              const Row(children: [
                Icon(Icons.electric_bolt, size: 16, color: Colors.amber),
                SizedBox(width: 6),
                Text('电费预警', style: TextStyle(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(_elecValue == 0 ? '预警已关闭' : '低于 ${_elecValue.toStringAsFixed(0)} 块时发送提醒',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Slider(
                value: _elecValue,
                min: 0,         
                max: 50,
                divisions: 50,
                label: _elecValue == 0 ? '已关闭' : '${_elecValue.toInt()} ',
                onChanged: (v) => setState(() => _elecValue = v),
              ),
              const SizedBox(height: 8),
              // 校园卡阈值
              const Row(children: [
                Icon(Icons.credit_card, size: 16, color: Colors.blue),
                SizedBox(width: 6),
                Text('校园卡预警', style: TextStyle(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(_cardValue == 0 ? '预警已关闭' : '低于 ¥${_cardValue.toStringAsFixed(0)} 时发送提醒',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Slider(
                value: _cardValue,
                min: 0,       
                max: 100,
                divisions: 20, 
                label: _cardValue == 0 ? '已关闭' : '¥${_cardValue.toInt()}',
                onChanged: (v) => setState(() => _cardValue = v),
              ),
              const SizedBox(height: 4),
              const Text(
                '后台每 15 分钟自动检查一次，低于阈值时推送通知\n（同一类型 6 小时内最多提醒一次）',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ])
          : const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator())),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            await Future.wait([
              NotificationService.setElecThreshold(_elecValue),
              NotificationService.setCardThreshold(_cardValue),
            ]);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}