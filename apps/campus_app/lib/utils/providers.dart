import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_service.dart';
import 'package:core/models/course.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/dorm_room.dart';
import '../utils/credential_service.dart';
import '../utils/notification_service.dart';
import '../utils/semester_service.dart';
import '../utils/dorm_service.dart';

// ── 凭据状态 ─────────────────────────────────────────────────
class CredentialsNotifier
    extends Notifier<({String username, String password})?> {
  @override
  ({String username, String password})? build() => null;

  Future<void> load(CredentialService svc) async {
    state = await svc.load();
  }

  void set(String username, String password) {
    state = (username: username, password: password);
  }

  void clear() => state = null;
}

final credentialsProvider =
    NotifierProvider<CredentialsNotifier, ({String username, String password})?>(
        CredentialsNotifier.new);

// ── 未设置宿舍时抛出的专用异常（供 UI 区分显示）────────────────
class NoDormSetException implements Exception {
  @override
  String toString() => '请先设置宿舍';
}

// ── 已选宿舍状态 ──────────────────────────────────────────────
class DormRoomNotifier extends AsyncNotifier<DormRoom?> {
  @override
  Future<DormRoom?> build() async {
    return ref.read(dormServiceProvider).load();
  }

  /// 保存宿舍后更新状态。
  /// electricityProvider 通过 ref.watch(dormRoomProvider) 建立了依赖，
  /// state 改变时 Riverpod 会自动使其失效并重新执行，触发新的电费请求。
  Future<void> set(DormRoom room) async {
    await ref.read(dormServiceProvider).save(room);
    state = AsyncData(room);
  }

  Future<void> clear() async {
    await ref.read(dormServiceProvider).clear();
    state = const AsyncData(null);
  }
}

final dormRoomProvider =
    AsyncNotifierProvider<DormRoomNotifier, DormRoom?>(DormRoomNotifier.new);

// ── 学期开始日期（当前/默认学期）────────────────────────────────
class SemesterStartNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    return ref.read(semesterServiceProvider).load();
  }

  Future<void> set(DateTime date) async {
    await ref.read(semesterServiceProvider).save(date);
    state = AsyncData(date);
  }
}

final semesterStartProvider =
    AsyncNotifierProvider<SemesterStartNotifier, DateTime?>(
        SemesterStartNotifier.new);

// ── 学期开始日期（按学期 key 存取，用于非当前学期）───────────────
class SemesterStartForKeyNotifier
    extends FamilyAsyncNotifier<DateTime?, String> {
  @override
  Future<DateTime?> build(String arg) async {
    return ref.read(semesterServiceProvider).loadForKey(arg);
  }

  Future<void> set(DateTime date) async {
    await ref.read(semesterServiceProvider).saveForKey(arg, date);
    state = AsyncData(date);
  }
}

final semesterStartForKeyProvider = AsyncNotifierProvider.family<
    SemesterStartForKeyNotifier, DateTime?, String>(
  SemesterStartForKeyNotifier.new,
);

// ── 课程表页当前选中的学期（null = 当前学期，持久化到 SharedPreferences）──
// 使用 NotifierProvider 替换原来的 StateProvider，使其能在 App 重启后恢复。
// build() 先返回 null（保持启动时无闪烁），再通过 microtask 异步恢复持久化值。
class SelectedSemesterNotifier extends Notifier<String?> {
  @override
  String? build() {
    // 立即返回 null，再在后台异步恢复持久化的学期字符串
    Future.microtask(() async {
      final saved =
          await ref.read(semesterServiceProvider).loadSelectedSemester();
      if (saved != null && state == null) {
        state = saved;
      }
    });
    return null;
  }

  /// 更新选中学期并持久化
  Future<void> set(String? value) async {
    state = value;
    await ref.read(semesterServiceProvider).saveSelectedSemester(value);
  }
}

final selectedScheduleSemesterProvider =
    NotifierProvider<SelectedSemesterNotifier, String?>(
        SelectedSemesterNotifier.new);

// ── 生效的学期开始日期 ────────────────────────────────────────
final activeSemesterStartProvider = Provider<AsyncValue<DateTime?>>((ref) {
  final selected = ref.watch(selectedScheduleSemesterProvider);
  if (selected == null) return ref.watch(semesterStartProvider);
  return ref.watch(semesterStartForKeyProvider(selected));
});

// ── 已选周（独立状态，默认第 1 周）───────────────────────────────
final selectedWeekProvider = StateProvider<int>((ref) => 1);

// ── 课程表返回类型 ────────────────────────────────────────────
typedef ScheduleResult = ({List<Course> courses, String remark});

// ── 课程表（按学期 family，null = 当前学期）──────────────────────
final scheduleProvider =
    FutureProvider.autoDispose.family<ScheduleResult, String?>(
        (ref, semester) async {
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');
  return ref
      .watch(apiServiceProvider)
      .getSchedule(creds.username, creds.password, semester: semester);
});

// ── 根据当前时间返回轮询间隔 ─────────────────────────────────────
Duration _pollingInterval() {
  final hour = DateTime.now().hour;
  if (hour >= 0 && hour < 6) return const Duration(hours: 3);
  return const Duration(minutes: 30);
}

// ── 电费（时间感知轮询）──────────────────────────────────────────
// 通过 ref.watch(dormRoomProvider) 建立依赖：
//   · 宿舍从「未设置」→「已设置」时，provider 自动重建并发起真正的请求
//   · 宿舍更换时同理自动刷新
// 若宿舍未设置，抛出 NoDormSetException，UI 显示「去设置」引导而非错误。
final electricityProvider = FutureProvider<String>((ref) async {
  final interval = _pollingInterval();
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');

  // 监听宿舍状态——这是触发自动刷新的关键 watch
  final dormAsync = ref.watch(dormRoomProvider);

  // 宿舍数据还在从 SharedPreferences 加载中，等待完成
  final dorm = await dormAsync.when(
    loading: () => ref.read(dormRoomProvider.future),
    error: (e, _) => Future<DormRoom?>.error(e),
    data: (d) => Future.value(d),
  );

  if (dorm == null) throw NoDormSetException();

  debugPrint('[FG] 查询电费，宿舍=${dorm.displayName}');
  final balance = await ref
      .watch(apiServiceProvider)
      .getElecBalance(creds.username, creds.password, dormParams: dorm.toQueryParams());
  debugPrint('[FG] 电费余额获取成功：$balance');
  NotificationService.checkAndNotify(balance);
  return balance;
});

// ── 校园卡余额（时间感知轮询）────────────────────────────────────
final campusCardBalanceProvider = FutureProvider<String>((ref) async {
  final interval = _pollingInterval();
  debugPrint('[FG] 校园卡 Timer 启动，${interval.inMinutes}min 后自动刷新');
  final timer = Timer(interval, () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);

  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');

  final balance = await ref
      .watch(apiServiceProvider)
      .getCampusCardBalance(creds.username, creds.password);
  debugPrint('[FG] 校园卡余额获取成功：$balance');
  return balance;
});

// ── 消费二维码 ────────────────────────────────────────────────
final payCodeProvider = FutureProvider.autoDispose<String>((ref) async {
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');
  return ref.watch(apiServiceProvider).getPayCodeToken(creds.username);
});

// ── 成绩 ─────────────────────────────────────────────────────
typedef GradeResult = ({Map<String, String> summary, List<Grade> grades});

final gradesProvider = FutureProvider.autoDispose
    .family<GradeResult, String>((ref, semester) async {
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');
  return ref
      .watch(apiServiceProvider)
      .getGrades(creds.username, creds.password, semester: semester);
});

// ── 考试安排 ─────────────────────────────────────────────────
final examsProvider =
    FutureProvider.autoDispose.family<List<Exam>, String?>((ref, semester) async {
  final creds = ref.watch(credentialsProvider);
  if (creds == null) throw Exception('未登录');
  return ref
      .watch(apiServiceProvider)
      .getExams(creds.username, creds.password, semester: semester);
});