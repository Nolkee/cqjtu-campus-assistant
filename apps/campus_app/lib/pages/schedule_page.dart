import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/models/course.dart';
import 'package:campus_platform/services/notification_service.dart';
import '../utils/providers.dart';
import '../widgets/course_cell.dart';
import '../widgets/error_view.dart';

const int _kTotalWeeks = 20;
const int _kTotalSlots = 13;

/// 每小节高度（px）
const double _kSlotH = 64.0;

/// 每列（每天）宽度
const double _kDayW = 76.0;

/// 时间列宽度
const double _kTimeW = 52.0;

/// 备注行高度
const double _kRemarkH = 52.0;

/// 每小节的时间区间（重庆交通大学作息时间表）
const Map<int, (String, String)> _kSlotTimes = {
  1: ('08:20', '09:00'),
  2: ('09:05', '09:45'),
  3: ('10:00', '10:40'),
  4: ('10:45', '11:25'),
  5: ('11:30', '12:10'),
  6: ('14:00', '14:40'),
  7: ('14:45', '15:25'),
  8: ('15:40', '16:20'),
  9: ('16:25', '17:05'),
  10: ('17:10', '17:50'),
  11: ('19:00', '19:40'),
  12: ('19:45', '20:25'),
  13: ('20:30', '21:10'),
};

// ── 日期工具 ─────────────────────────────────────────────────
DateTime _semesterMonday(DateTime s) =>
    s.subtract(Duration(days: s.weekday - 1));

DateTime _mondayOfWeek(DateTime s, int week) =>
    _semesterMonday(s).add(Duration(days: (week - 1) * 7));

int _calcCurrentWeek(DateTime s) {
  final now = DateTime.now();
  final semesterMonday = _semesterMonday(s);

  // 早于开学那一周的周一，判定为放假中（第0周）
  if (now.isBefore(semesterMonday)) return 0;

  final diff = now.difference(semesterMonday).inDays;
  final week = diff ~/ 7 + 1;

  // 超过20周，判定为放假中（第21周）
  if (week > _kTotalWeeks) return 21;

  return week;
}

// ── 学期自动推算工具 ─────────────────────────────────────────────
/// 根据选定的日期，自动识别属于哪个学期
String _calculateSemester(DateTime date) {
  int year = date.year;
  int month = date.month;
  // 8月~12月 -> 当年-下一年-1 (上学期)
  if (month >= 8) {
    return '$year-${year + 1}-1';
  }
  // 1月 -> 去年-当年-1 (上学期)
  else if (month == 1) {
    return '${year - 1}-$year-1';
  }
  // 2月~7月 -> 去年-当年-2 (下学期)
  else {
    return '${year - 1}-$year-2';
  }
}

/// "2024-2025-1" → "24-25 第1学期"
String _semesterLabel(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return s;
  return '${parts[0].substring(2)}-${parts[1].substring(2)} 第${parts[2]}学期';
}

// ─────────────────────────────────────────────────────────────
class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // selectedScheduleSemesterProvider 已改为 AsyncNotifier，需要解包
    final selectedSemesterAsync = ref.watch(selectedScheduleSemesterProvider);
    final selectedSemester = selectedSemesterAsync.valueOrNull;
    final semesterAsync = ref.watch(activeSemesterStartProvider);

    // 开学日期变更时自动跳到对应当前周
    ref.listen<AsyncValue<DateTime?>>(activeSemesterStartProvider, (_, next) {
      final start = next.valueOrNull;
      if (start != null) {
        ref
            .read(selectedWeekProvider.notifier)
            .setWeek(_calcCurrentWeek(start));
      }
    });

    if (semesterAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final semesterStart = semesterAsync.valueOrNull;
    if (semesterStart == null) {
      return const _NoSemesterPage();
    }

    return _ScheduleBody(
      semesterStart: semesterStart,
      selectedSemester: selectedSemester,
    );
  }
}

// ── 未设置开学日期引导页 ─────────────────────────────────────
class _NoSemesterPage extends ConsumerWidget {
  const _NoSemesterPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('课程表')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              const Text(
                '尚未设置开学日期',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '设置开学日期后，将自动识别学期并获取课表。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('选择开学日期'),
                onPressed: () => _pickSemesterStart(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 课程表主体 ────────────────────────────────────────────────
class _ScheduleBody extends ConsumerWidget {
  final DateTime semesterStart;
  final String? selectedSemester;

  const _ScheduleBody({required this.semesterStart, this.selectedSemester});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider(selectedSemester));
    final selectedWeek = ref.watch(selectedWeekProvider);
    final currentWeek = _calcCurrentWeek(semesterStart);

    final semLabel = selectedSemester != null
        ? _semesterLabel(selectedSemester!)
        : '设置学期开学日期';

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程表'),
        actions: [
          // ── 统一的学期/日期切换按钮 ─────────────────────────────────
          TextButton.icon(
            icon: const Icon(Icons.edit_calendar, size: 16),
            label: Text(
              semLabel,
              style: TextStyle(
                fontSize: 12,
                color: selectedSemester != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _pickSemesterStart(context, ref),
          ),

          // ── 回本周 ───────────────────────────────────────
          if (selectedWeek != currentWeek)
            TextButton(
              onPressed: () =>
                  ref.read(selectedWeekProvider.notifier).setWeek(currentWeek),
              child: const Text('回本周'),
            ),

          // ── 刷新 ────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('正在同步最新课表...'),
                  duration: Duration(seconds: 1),
                ),
              );
              // 在第一个 await 前缓存所有需要用到的引用，
              // 避免 await 后 widget 销毁导致 StateError
              final creds = ref.read(credentialsProvider);
              final apiService = ref.read(apiServiceProvider);
              final semesterStart = ref
                  .read(activeSemesterStartProvider)
                  .valueOrNull;
              try {
                if (creds != null) {
                  await apiService.getSchedule(
                    creds.username,
                    creds.password,
                    semester: selectedSemester,
                    forceRefresh: true,
                  );
                }
                ref.invalidate(scheduleProvider(selectedSemester));
                final result = await ref.read(
                  scheduleProvider(selectedSemester).future,
                );

                // 课表拉取成功后，清空旧调度并重新注册通知
                if (semesterStart != null) {
                  debugPrint('[刷新] 课表已更新，重新调度课程通知...');
                  await NotificationService.scheduleClassReminders(
                    result.courses,
                    semesterStart,
                  );
                  debugPrint('[刷新] 课程通知调度完成');
                } else {
                  debugPrint('[刷新] 未设置开学日期，跳过通知调度');
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('课表已更新')));
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('刷新失败，请检查网络')));
                }
              }
            },
          ),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(scheduleProvider(selectedSemester)),
        ),
        data: (result) => Column(
          children: [
            _WeekNavigator(
              semesterStart: semesterStart,
              selectedWeek: selectedWeek,
              currentWeek: currentWeek,
            ),
            Expanded(
              child: _TimetableGrid(
                courses: result.courses,
                remark: result.remark,
                semesterStart: semesterStart,
                selectedWeek: selectedWeek,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 统一开学日期选择与学期推算逻辑 ─────────────────────────────────────────
Future<void> _pickSemesterStart(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final initial = ref.read(activeSemesterStartProvider).valueOrNull ?? now;

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 2),
    helpText: '选择开学第一天',
  );

  if (picked == null) return;

  // ✅ StateError 修复：在第一个 await 之前把所有 notifier 缓存为本地变量。
  //    showDatePicker await 返回后 widget 可能已被销毁，此时再调用
  //    ref.read() 会抛出 "Cannot use ref after widget was disposed"。
  //    notifier 对象本身是独立存活的，缓存后可安全在 async gap 后使用。
  final semesterStr = _calculateSemester(picked);
  final forKeyNotifier = ref.read(
    semesterStartForKeyProvider(semesterStr).notifier,
  );
  final semesterStartNotifier = ref.read(semesterStartProvider.notifier);
  final selectedSemesterNotifier = ref.read(
    selectedScheduleSemesterProvider.notifier,
  );
  final selectedWeekNotifier = ref.read(selectedWeekProvider.notifier);

  // 1. 存储选定日期的开学时间（按学期 key）
  await forKeyNotifier.set(picked);

  // 2. 同时写入默认 semesterStartProvider，作为 activeSemesterStartProvider 的 fallback。
  //    避免 selectedScheduleSemesterProvider 重建时短暂为 null 导致显示"未设置开学日期"。
  await semesterStartNotifier.set(picked);

  // 3. 切换当前学期，触发课表数据获取
  await selectedSemesterNotifier.set(semesterStr);

  // 4. 计算周次并跳转
  selectedWeekNotifier.setWeek(_calcCurrentWeek(picked));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已自动切换为 ${_semesterLabel(semesterStr)}')),
    );
  }
}

// ── 周次导航栏 ────────────────────────────────────────────────
class _WeekNavigator extends ConsumerWidget {
  final DateTime semesterStart;
  final int selectedWeek;
  final int currentWeek;

  const _WeekNavigator({
    required this.semesterStart,
    required this.selectedWeek,
    required this.currentWeek,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVacation = selectedWeek == 0 || selectedWeek == 21;
    // 如果是放假中，则直接用系统当前时间所在的周一作为顶部显示的日期区间
    final monday = isVacation
        ? _semesterMonday(DateTime.now())
        : _mondayOfWeek(semesterStart, selectedWeek);
    final sunday = monday.add(const Duration(days: 6));
    final isCur = selectedWeek == currentWeek;

    // 左箭头逻辑：放假（0周）不可再向左，第1周向左滑入放假（0周），第21周向左滑入第20周
    VoidCallback? onLeft;
    if (selectedWeek > 1 && selectedWeek <= _kTotalWeeks) {
      onLeft = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(selectedWeek - 1);
    } else if (selectedWeek == 21) {
      onLeft = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(_kTotalWeeks);
    } else if (selectedWeek == 1) {
      onLeft = () => ref.read(selectedWeekProvider.notifier).setWeek(0);
    }

    // 右箭头逻辑：放假（21周）不可再向右，第20周向右滑入放假（21周），第0周向右滑入第1周
    VoidCallback? onRight;
    if (selectedWeek >= 1 && selectedWeek < _kTotalWeeks) {
      onRight = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(selectedWeek + 1);
    } else if (selectedWeek == 0) {
      onRight = () => ref.read(selectedWeekProvider.notifier).setWeek(1);
    } else if (selectedWeek == _kTotalWeeks) {
      onRight = () => ref.read(selectedWeekProvider.notifier).setWeek(21);
    }

    return Container(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: onLeft,
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: () => _pickWeek(context, ref),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isVacation ? '放假中' : '第 $selectedWeek 周',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isCur && !isVacation
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      if (isCur && !isVacation) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '本周',
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${monday.month}/${monday.day} - '
                    '${sunday.month}/${sunday.day}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: onRight,
          ),
        ],
      ),
    );
  }

  void _pickWeek(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '选择周次',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1.6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _kTotalWeeks,
                itemBuilder: (_, i) {
                  final w = i + 1;
                  final isCur = w == currentWeek;
                  final isSel = w == selectedWeek;
                  return GestureDetector(
                    onTap: () {
                      ref.read(selectedWeekProvider.notifier).setWeek(w);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSel
                            ? Theme.of(context).colorScheme.primary
                            : isCur
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: isCur && !isSel
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '第$w周',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSel ? Colors.white : null,
                          fontWeight: isCur || isSel
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── 课程表网格（含备注行，随表格一起垂直滚动）──────────────────
class _TimetableGrid extends StatelessWidget {
  final List<Course> courses;
  final String remark;
  final DateTime semesterStart;
  final int selectedWeek;

  const _TimetableGrid({
    required this.courses,
    required this.remark,
    required this.semesterStart,
    required this.selectedWeek,
  });

  Map<int, List<Course>> _buildDayMap() {
    final map = <int, List<Course>>{};
    for (final c in courses) {
      map.putIfAbsent(c.dayOfWeek, () => []).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final dayMap = _buildDayMap();
    final isVacation = selectedWeek == 0 || selectedWeek == 21;
    // 如果放假中，顶部日期头按系统时间的周一来算，保持视觉正常
    final monday = isVacation
        ? _semesterMonday(DateTime.now())
        : _mondayOfWeek(semesterStart, selectedWeek);
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final gridH = _kTotalSlots * _kSlotH;

    // 总宽度 = 时间列 + 7 天列
    final totalWidth = _kTimeW + _kDayW * 7;

    const dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return SingleChildScrollView(
      // 垂直滚动：可以从上午一直滚到备注
      child: SingleChildScrollView(
        // 水平滚动
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 表头：星期 + 日期 ────────────────────────────
            Container(
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  SizedBox(width: _kTimeW, height: 44),
                  for (int d = 0; d < 7; d++)
                    _buildDayHeader(
                      context,
                      monday.add(Duration(days: d)),
                      dayLabels[d],
                      todayDay,
                      isVacation,
                    ),
                ],
              ),
            ),
            Container(height: 1, color: Colors.grey.shade300),

            // ── 网格主体 ────────────────────────────────────
            SizedBox(
              height: gridH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeColumn(gridH),
                  Container(
                    width: 1,
                    height: gridH,
                    color: Colors.grey.shade300,
                  ),
                  for (int day = 1; day <= 7; day++)
                    _buildDayColumn(context, dayMap[day] ?? [], day),
                ],
              ),
            ),

            // ── 备注行（晚上课程下方，随表格一起滚动）──────────
            if (remark.isNotEmpty)
              Container(
                width: totalWidth,
                constraints: const BoxConstraints(minHeight: _kRemarkH),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border(
                    top: BorderSide(color: Colors.amber.shade200, width: 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧图标对齐时间列宽度
                    SizedBox(
                      width: _kTimeW - 12,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 14,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '备注',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 备注文本
                    Expanded(
                      child: Text(
                        remark,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.brown.shade700,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    DateTime date,
    String dayLabel,
    DateTime todayDay,
    bool isVacation,
  ) {
    // 放假中不高亮今天
    final isToday = date == todayDay && !isVacation;
    return SizedBox(
      width: _kDayW,
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '周$dayLabel',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isToday ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 2),
          isToday
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${date.month}/${date.day}',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                )
              : Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(double gridH) {
    return SizedBox(
      width: _kTimeW,
      height: gridH,
      child: Stack(
        children: [
          ..._sectionBg(),
          for (int s = 1; s <= _kTotalSlots; s++)
            Positioned(
              top: (s - 1) * _kSlotH,
              left: 0,
              right: 0,
              height: _kSlotH,
              child: _SlotCell(slot: s),
            ),
          _hDivider(5 * _kSlotH, Colors.blue.shade200),
          _hDivider(10 * _kSlotH, Colors.indigo.shade200),
        ],
      ),
    );
  }

  Widget _buildDayColumn(
    BuildContext context,
    List<Course> dayCourses,
    int day,
  ) {
    final gridH = _kTotalSlots * _kSlotH;
    return Container(
      width: _kDayW,
      height: gridH,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Stack(
        children: [
          ..._sectionBg(),
          for (int s = 1; s <= _kTotalSlots; s++)
            _hDivider(s * _kSlotH, Colors.grey.shade200),
          _hDivider(5 * _kSlotH, Colors.blue.shade100, thickness: 1.5),
          _hDivider(10 * _kSlotH, Colors.indigo.shade100, thickness: 1.5),
          // 由于 selectedWeek 为 0 或 21 时，course.isActiveInWeek 均会返回 false，
          // 渲染时这里的 _cellColor 就会自动呈现出置灰效果，实现了放假中全局灰化。
          for (final course
              in [...dayCourses]..sort(
                (a, b) => (a.isActiveInWeek(selectedWeek) ? 1 : 0).compareTo(
                  b.isActiveInWeek(selectedWeek) ? 1 : 0,
                ),
              ))
            Positioned(
              key: ValueKey('${course.name}_${course.timeStr}'),
              top: (course.timeSlot - 1) * _kSlotH + 2,
              left: 2,
              right: 2,
              height: course.slotSpan * _kSlotH - 4,
              child: CourseCell(
                course: course,
                isActive: course.isActiveInWeek(selectedWeek),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sectionBg() => [
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 5 * _kSlotH,
      child: Container(color: Colors.white),
    ),
    Positioned(
      top: 5 * _kSlotH,
      left: 0,
      right: 0,
      height: 5 * _kSlotH,
      child: Container(color: Colors.blue.shade50.withValues(alpha: 0.4)),
    ),
    Positioned(
      top: 10 * _kSlotH,
      left: 0,
      right: 0,
      height: 3 * _kSlotH,
      child: Container(color: Colors.indigo.shade50.withValues(alpha: 0.4)),
    ),
  ];

  Widget _hDivider(double top, Color color, {double thickness = 0.5}) =>
      Positioned(
        top: top,
        left: 0,
        right: 0,
        child: Container(height: thickness, color: color),
      );
}

// ── 时间列单元格 ──────────────────────────────────────────────
class _SlotCell extends StatelessWidget {
  final int slot;
  const _SlotCell({required this.slot});

  @override
  Widget build(BuildContext context) {
    final times = _kSlotTimes[slot];
    return Container(
      alignment: Alignment.center,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$slot',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          if (times != null) ...[
            Text(
              times.$1,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
            ),
            Text(
              times.$2,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}
