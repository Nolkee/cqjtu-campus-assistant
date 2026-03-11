import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'services/app_update_coordinator.dart';
import 'utils/providers.dart';
import 'package:campus_platform/services/background_task.dart';
import 'pages/login_page.dart';
import 'pages/schedule_page.dart';
import 'pages/campus_card_page.dart';
import 'pages/profile_page.dart';
import 'widgets/silent_zove_token_bootstrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();

  await Workmanager().initialize(
    backgroundCallbackDispatcher,
    //isInDebugMode: false,
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _trySchedule();
      if (!mounted) return;
      await AppUpdateCoordinator.checkAndPrompt(context);
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
    debugPrint('[生命周期] 状态改变: $state');
    if (state == AppLifecycleState.resumed) {
      _trySchedule();
    }
  }

  void _trySchedule() {
    // ✅ 核心修复 1：读取当前真正选中的学期，而不是写死 null
    final selectedSemester = ref
        .read(selectedScheduleSemesterProvider)
        .valueOrNull;

    // ✅ 核心修复 2：使用统一的 Provider 实例
    final scheduleState = ref.read(scheduleProvider(selectedSemester));
    final semesterState = ref.read(activeSemesterStartProvider);

    final result = scheduleState.valueOrNull;
    final semesterStart = semesterState.valueOrNull;

    debugPrint('----------------------------------------');
    debugPrint('[调度器] 准备检查课表提醒注册条件...');

    if (scheduleState.hasError) {
      debugPrint('[调度器] ❌ 课表加载失败，原因: ${scheduleState.error}');
    }

    debugPrint(
      '[调度器] 课表状态(${selectedSemester ?? "默认"}): ${scheduleState.runtimeType} -> ${result != null ? "有数据" : "无数据"}',
    );
    debugPrint(
      '[调度器] 开学时间: ${semesterState.runtimeType} -> ${semesterStart != null ? "有数据" : "无数据"}',
    );

    if (result != null && semesterStart != null) {
      debugPrint('[调度器] ✅ 两大数据已就绪，准备下发给系统注册！');
      NotificationService.scheduleClassReminders(result.courses, semesterStart);
    } else {
      debugPrint('[调度器] ❌ 拦截：数据不完整，放弃本次注册。');
    }
    debugPrint('----------------------------------------');
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
    // ✅ 核心修复 3：在 build 中也监听真正选中的学期
    final selectedSemester = ref
        .watch(selectedScheduleSemesterProvider)
        .valueOrNull;

    ref.listen(scheduleProvider(selectedSemester), (prev, next) {
      if (next.hasValue) _trySchedule();
    });

    ref.listen(activeSemesterStartProvider, (prev, next) {
      if (next.hasValue) _trySchedule();
    });

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _pages,
          ),
          const SilentZoveTokenBootstrapper(),
        ],
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
