import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/battery_optimization_service.dart';
import 'utils/providers.dart';
import 'package:campus_platform/services/background_task.dart';
import 'pages/login_page.dart';
import 'pages/schedule_page.dart';
import 'pages/campus_card_page.dart';
import 'pages/profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();

  await Workmanager().initialize(
    backgroundCallbackDispatcher,
    isInDebugMode: false,
  );

  await Workmanager().registerPeriodicTask(
    kBgTaskTag,
    kBgTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  runApp(const ProviderScope(child: CampusApp()));
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CQJTU Hub',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CH')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    // 关键修复：将 Future 缓存起来，确保生命周期内只执行一次本地读取
    // 这样后续路由返回触发 build 时，就不会再出现加载圈和销毁状态了
    _initFuture = ref
        .read(credentialsProvider.notifier)
        .load(ref.read(credentialServiceProvider));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final creds = ref.watch(credentialsProvider);
        return creds != null ? const _MainShell() : const LoginPage();
      },
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell>
    with WidgetsBindingObserver {
  int _index = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showBatteryGuideIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trySchedule();
    }
  }

  void _trySchedule() {
    // scheduleProvider 现在返回 ScheduleResult，从中取 .courses
    final result = ref.read(scheduleProvider(null)).valueOrNull;
    final semesterStart = ref.read(semesterStartProvider).valueOrNull;
    if (result != null && semesterStart != null) {
      NotificationService.scheduleClassReminders(result.courses, semesterStart);
    }
  }

  Future<void> _showBatteryGuideIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool('battery_guide_shown') ?? false;
    if (alreadyShown) return;

    final isIgnoring =
        await BatteryOptimizationService.isIgnoringBatteryOptimizations();
    if (isIgnoring) {
      await prefs.setBool('battery_guide_shown', true);
      return;
    }

    if (mounted) {
      await prefs.setBool('battery_guide_shown', true);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _FirstRunBatteryGuideDialog(),
      );
    }
  }

  static const _pages = [SchedulePage(), CampusCardPage(), ProfilePage()];

  static const _items = [
    BottomNavigationBarItem(
      icon: Icon(Icons.calendar_today_outlined),
      activeIcon: Icon(Icons.calendar_today),
      label: '课程表',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.credit_card_outlined),
      activeIcon: Icon(Icons.credit_card),
      label: '校园卡',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person_outline),
      activeIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(electricityProvider);
    ref.watch(campusCardBalanceProvider);

    ref.listen(scheduleProvider(null), (prev, next) {
      if (next.hasValue) _trySchedule();
    });
    ref.listen(semesterStartProvider, (prev, next) {
      if (next.hasValue) _trySchedule();
    });

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) {
          setState(() => _index = i);
          _pageController.jumpToPage(i);
        },
        type: BottomNavigationBarType.fixed,
        items: _items,
      ),
    );
  }
}

// ── 首次启动电池优化引导对话框 ──────────────────────────────────
class _FirstRunBatteryGuideDialog extends StatefulWidget {
  const _FirstRunBatteryGuideDialog();

  @override
  State<_FirstRunBatteryGuideDialog> createState() =>
      _FirstRunBatteryGuideDialogState();
}

class _FirstRunBatteryGuideDialogState
    extends State<_FirstRunBatteryGuideDialog>
    with WidgetsBindingObserver {
  bool? _step1Done;
  bool? _step2AppOps;
  bool _step2Opened = false;
  bool _step3Confirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _loadStep2Flag();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final ignoring =
        await BatteryOptimizationService.isIgnoringBatteryOptimizations();
    final autostart = await BatteryOptimizationService.checkMiuiAutostart();
    if (!mounted) return;
    setState(() {
      _step1Done = ignoring;
      _step2AppOps = autostart;
    });
  }

  Future<void> _loadStep2Flag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _step2Opened = prefs.getBool('autostart_page_opened') ?? false;
    });
  }

  Future<void> _markStep2Opened() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autostart_page_opened', true);
    if (mounted) setState(() => _step2Opened = true);
  }

  bool get _step2Done => _step2AppOps == true || _step2Opened;
  bool get _allDone => _step1Done == true && _step2Done && _step3Confirmed;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Text('开启后台通知'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '为了在电费/校园卡余额不足时及时提醒你，请完成以下设置：',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            _StepRow(
              icon: Icons.battery_saver_outlined,
              color: Colors.green,
              title: '第 1 步：关闭电池优化',
              desc: '允许 App 不受限地在后台运行',
              statusWidget: _step1Done == null
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _step1Done!
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    )
                  : FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await BatteryOptimizationService.requestIgnoreBatteryOptimizations();
                      },
                      child: const Text('去设置', style: TextStyle(fontSize: 12)),
                    ),
            ),
            const SizedBox(height: 14),
            _StepRow(
              icon: Icons.autorenew_outlined,
              color: Colors.blue,
              title: '第 2 步：开启自启动',
              desc: _step2AppOps == true
                  ? '已通过系统检测'
                  : _step2Opened
                  ? '已进入设置页，请确认已开启'
                  : '允许 App 开机自启，后台轮询不中断',
              statusWidget: _step2AppOps == true
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    )
                  : _step2Opened
                  ? const Icon(
                      Icons.check_circle_outline,
                      color: Colors.orange,
                      size: 20,
                    )
                  : FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await _markStep2Opened();
                        await BatteryOptimizationService.openMiuiAutostart();
                      },
                      child: const Text('去设置', style: TextStyle(fontSize: 12)),
                    ),
            ),
            const SizedBox(height: 14),
            _StepRow(
              icon: Icons.lock_outline,
              color: Colors.purple,
              title: '第 3 步：锁定后台任务',
              desc: '最近任务界面 → 长按本应用 → 锁定',
              statusWidget: _step3Confirmed
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _step3Confirmed = true),
                      child: const Text('已完成', style: TextStyle(fontSize: 12)),
                    ),
            ),
            if (_allDone) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '所有步骤已完成，后台通知已就绪！',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后再说'),
        ),
        if (_allDone)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final Widget statusWidget;

  const _StepRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.statusWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        statusWidget,
      ],
    );
  }
}
