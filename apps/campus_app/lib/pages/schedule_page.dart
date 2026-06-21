import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/models/course.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/schedule_widget_service.dart';
import '../utils/providers.dart';
import '../widgets/course_cell.dart';
import '../widgets/error_view.dart';
import 'webview_login_page.dart'; // 👈 新增引入：用于在此页面唤起验证码验证

const int _kTotalSlots = 13;

/// 每小节高度（px）
const double _kSlotH = 64.0;

/// 每列（每天）宽度
const double _kDayW = 76.0;

/// 时间列宽度
const double _kTimeW = 52.0;

/// 备注行高度
const double _kRemarkH = 52.0;

/// 课表底部避让浮动按钮和底部导航，防止备注被遮挡。
const double _kTimetableBottomInset = 56.0;

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
DateTime _startOfWeek(DateTime date, {required bool sundayFirst}) {
  final dayOnly = DateTime(date.year, date.month, date.day);
  final offset = sundayFirst ? date.weekday % 7 : date.weekday - 1;
  return dayOnly.subtract(Duration(days: offset));
}

DateTime _startOfSemesterWeek(
  DateTime semesterStart, {
  required bool sundayFirst,
}) {
  return _startOfWeek(semesterStart, sundayFirst: sundayFirst);
}

DateTime _weekStartOf(
  DateTime semesterStart,
  int week, {
  required bool sundayFirst,
}) {
  return _startOfSemesterWeek(
    semesterStart,
    sundayFirst: sundayFirst,
  ).add(Duration(days: (week - 1) * 7));
}

List<int> _orderedWeekdays({required bool sundayFirst}) {
  return sundayFirst
      ? const [DateTime.sunday, 1, 2, 3, 4, 5, 6]
      : const [1, 2, 3, 4, 5, 6, DateTime.sunday];
}

List<String> _weekdayLabels({required bool sundayFirst}) {
  return sundayFirst
      ? const ['日', '一', '二', '三', '四', '五', '六']
      : const ['一', '二', '三', '四', '五', '六', '日'];
}

int _calcCurrentWeek(
  DateTime s, {
  bool sundayFirst = false,
  int totalWeeks = defaultSemesterTotalWeeks,
}) {
  final now = DateTime.now();
  final semesterMonday = _startOfSemesterWeek(s, sundayFirst: sundayFirst);

  if (now.isBefore(semesterMonday)) return 0;

  final diff = now.difference(semesterMonday).inDays;
  final week = diff ~/ 7 + 1;

  if (week > totalWeeks) return totalWeeks + 1;

  return week;
}

// ── 学期自动推算工具 ─────────────────────────────────────────────
String _calculateSemester(DateTime date) {
  int year = date.year;
  int month = date.month;
  if (month >= 8) {
    return '$year-${year + 1}-1';
  } else if (month == 1) {
    return '${year - 1}-$year-1';
  } else {
    return '${year - 1}-$year-2';
  }
}

String _semesterLabel(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return s;
  return '${parts[0].substring(2)}-${parts[1].substring(2)} 第${parts[2]}学期';
}

String _courseColorKey(Course course) {
  final normalized = course.name.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? '未命名课程' : normalized;
}

Map<String, Color> _buildCourseColorMap(List<Course> courses) {
  final names = courses.map(_courseColorKey).toSet().toList()..sort();
  final used = <int>{};
  final result = <String, Color>{};

  for (final name in names) {
    final seed = _stableCourseHash(name);
    for (var attempt = 0; attempt < 720; attempt++) {
      final color = _pastelCourseColor(seed, attempt);
      final value = color.toARGB32();
      if (!used.add(value)) continue;
      result[name] = color;
      break;
    }
  }

  return result;
}

Color _pastelCourseColor(int seed, int attempt) {
  final mixed = (seed + attempt * 0x9E3779B9) & 0xFFFFFFFF;
  final hue = ((mixed % 3600) / 10.0 + attempt * 17.0) % 360.0;
  final saturation = 0.30 + ((mixed >> 8) % 9) / 100.0;
  final lightness = 0.82 + ((mixed >> 16) % 6) / 100.0;
  return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
}

int _stableCourseHash(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

// ─────────────────────────────────────────────────────────────
class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSemesterAsync = ref.watch(selectedScheduleSemesterProvider);
    final selectedSemester = selectedSemesterAsync.valueOrNull;
    final semesterAsync = ref.watch(activeSemesterStartProvider);
    final sundayFirst =
        ref.watch(scheduleSundayFirstProvider).valueOrNull ?? false;
    final totalWeeks =
        ref.watch(semesterTotalWeeksProvider(selectedSemester)).valueOrNull ??
        defaultSemesterTotalWeeks;

    ref.listen<AsyncValue<DateTime?>>(activeSemesterStartProvider, (_, next) {
      final start = next.valueOrNull;
      if (start != null) {
        ref
            .read(selectedWeekProvider.notifier)
            .setWeek(
              _calcCurrentWeek(
                start,
                sundayFirst: sundayFirst,
                totalWeeks: totalWeeks,
              ),
            );
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
      sundayFirst: sundayFirst,
      totalWeeks: totalWeeks,
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
  final bool sundayFirst;
  final int totalWeeks;

  const _ScheduleBody({
    required this.semesterStart,
    this.selectedSemester,
    required this.sundayFirst,
    required this.totalWeeks,
  });

  // ── 统一的刷新逻辑（包含验证码拦截和 WebView 处理）──────────────────
  Future<void> _doRefresh(BuildContext context, WidgetRef ref) async {
    final creds = ref.read(credentialsProvider);
    if (creds == null) return;
    final backend = ref.read(campusGatewayProvider);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在同步最新课表...'),
          duration: Duration(seconds: 1),
        ),
      );

      // 强制后端发起请求
      await backend.getSchedule(
        creds.username,
        creds.password,
        semester: selectedSemester,
        forceRefresh: true,
      );

      // 刷新本地状态
      ref.invalidate(scheduleProvider(selectedSemester));
      final result = await ref.read(scheduleProvider(selectedSemester).future);

      debugPrint('[刷新] 课表已更新，重新调度课程通知...');
      await NotificationService.scheduleClassReminders(
        result.courses,
        semesterStart,
        totalWeeks: totalWeeks,
      );
      await ScheduleWidgetService.updateScheduleWidgets(
        courses: result.courses,
        semesterStart: semesterStart,
        selectedSemester: selectedSemester,
        remark: result.remark,
        totalWeeks: totalWeeks,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课表已更新')));
      }
    } catch (e) {
      final errorStr = e.toString();
      // 如果报错内容提示需要验证码，唤起 WebView
      if (errorStr.contains('449') ||
          errorStr.contains('验证码') ||
          errorStr.contains('HTML') ||
          errorStr.contains('CAS')) {
        if (context.mounted) {
          final result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (_) => WebViewLoginPage(
                username: creds.username,
                password: creds.password,
              ),
            ),
          );

          // WebView 登录成功，拿到了 Cookies
          if (result != null && context.mounted) {
            try {
              await ref
                  .read(webLoginBinderProvider)
                  .bind(username: creds.username, result: result);
            } catch (injectErr) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('会话恢复失败: $injectErr')));
              }
            }
          }
        }
      } else {
        // 普通的网络错误直接提示
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('刷新失败: ${errorStr.replaceAll('Exception: ', '')}'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider(selectedSemester));
    final showInactiveCourses =
        ref.watch(scheduleShowInactiveCoursesProvider).valueOrNull ?? true;
    final selectedWeek = ref.watch(selectedWeekProvider);
    final currentWeek = _calcCurrentWeek(
      semesterStart,
      sundayFirst: sundayFirst,
      totalWeeks: totalWeeks,
    );

    final semLabel = selectedSemester != null
        ? _semesterLabel(selectedSemester!)
        : '设置学期开学日期';

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程表'),
        actions: [
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
          if (selectedWeek != currentWeek)
            TextButton(
              onPressed: () =>
                  ref.read(selectedWeekProvider.notifier).setWeek(currentWeek),
              child: const Text('回本周'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            // ✅ 将右上角的刷新也指向通用的 _doRefresh
            onPressed: () => _doRefresh(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增课程'),
        onPressed: () => _showAddCustomCourseSheet(
          context,
          ref,
          selectedSemester,
          totalWeeks,
        ),
      ),
      body: scheduleAsync.when(
        skipError: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          String errMsg = e.toString();
          // ✅ 错误提示美化：去掉乱码，转换为直观提示
          if (errMsg.contains('449') ||
              errMsg.contains('验证码') ||
              errMsg.contains('HTML') ||
              errMsg.contains('CAS')) {
            errMsg = '系统会话已过期或需要安全验证\n请点击下方重试按钮进行验证';
          } else {
            errMsg = errMsg.replaceAll('Exception: ', '');
          }

          return ErrorView(
            message: errMsg,
            // ✅ 将屏幕中间的重试按钮也指向 _doRefresh
            onRetry: () => _doRefresh(context, ref),
          );
        },
        data: (result) => Column(
          children: [
            _WeekNavigator(
              semesterStart: semesterStart,
              selectedWeek: selectedWeek,
              currentWeek: currentWeek,
              sundayFirst: sundayFirst,
              totalWeeks: totalWeeks,
            ),
            Expanded(
              child: _TimetableGrid(
                courses: result.courses,
                remark: result.remark,
                semesterStart: semesterStart,
                selectedWeek: selectedWeek,
                sundayFirst: sundayFirst,
                totalWeeks: totalWeeks,
                selectedSemester: selectedSemester,
                showInactiveCourses: showInactiveCourses,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 以下其余部分保持不变 (选期逻辑、导航栏、表格绘制等) ─────────────────────────────────────────

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

  final semesterStr = _calculateSemester(picked);
  final forKeyNotifier = ref.read(
    semesterStartForKeyProvider(semesterStr).notifier,
  );
  final semesterStartNotifier = ref.read(semesterStartProvider.notifier);
  final selectedSemesterNotifier = ref.read(
    selectedScheduleSemesterProvider.notifier,
  );
  final selectedWeekNotifier = ref.read(selectedWeekProvider.notifier);
  final sundayFirst =
      ref.read(scheduleSundayFirstProvider).valueOrNull ?? false;

  await forKeyNotifier.set(picked);
  await semesterStartNotifier.set(picked);
  await selectedSemesterNotifier.set(semesterStr);
  selectedWeekNotifier.setWeek(
    _calcCurrentWeek(
      picked,
      sundayFirst: sundayFirst,
      totalWeeks:
          ref.read(semesterTotalWeeksProvider(semesterStr)).valueOrNull ??
          defaultSemesterTotalWeeks,
    ),
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已自动切换为 ${_semesterLabel(semesterStr)}')),
    );
  }
}

Future<void> _showAddCustomCourseSheet(
  BuildContext context,
  WidgetRef ref,
  String? selectedSemester,
  int totalWeeks,
) async {
  final nameController = TextEditingController();
  final classroomController = TextEditingController();
  final teacherController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final safeTotalWeeks = totalWeeks
      .clamp(minSemesterTotalWeeks, maxSemesterTotalWeeks)
      .toInt();
  final selectedWeek = ref.read(selectedWeekProvider);
  final initialWeek = selectedWeek >= 1 && selectedWeek <= safeTotalWeeks
      ? selectedWeek
      : 1;

  var weekday = DateTime.monday;
  var startSlot = 1;
  var endSlot = 2;
  var startWeek = initialWeek;
  var endWeek = initialWeek;

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.edit_calendar_outlined,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '新增自定义课程',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: '课程名称',
                          prefixIcon: Icon(Icons.menu_book_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入课程名称'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: classroomController,
                        decoration: const InputDecoration(
                          labelText: '教室',
                          prefixIcon: Icon(Icons.room_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入教室'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: teacherController,
                        decoration: const InputDecoration(
                          labelText: '教师（可选）',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: weekday,
                              decoration: const InputDecoration(
                                labelText: '星期',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(7, (index) {
                                final value = index + 1;
                                return DropdownMenuItem(
                                  value: value,
                                  child: Text(_weekdayName(value)),
                                );
                              }),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() => weekday = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: startSlot,
                              decoration: const InputDecoration(
                                labelText: '开始节',
                                border: OutlineInputBorder(),
                              ),
                              items: _slotMenuItems(),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  startSlot = value;
                                  if (endSlot < startSlot) endSlot = startSlot;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: endSlot,
                              decoration: const InputDecoration(
                                labelText: '结束节',
                                border: OutlineInputBorder(),
                              ),
                              items: _slotMenuItems(),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  endSlot = value < startSlot
                                      ? startSlot
                                      : value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: startWeek,
                              decoration: const InputDecoration(
                                labelText: '开始周',
                                border: OutlineInputBorder(),
                              ),
                              items: _weekMenuItems(safeTotalWeeks),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  startWeek = value;
                                  if (endWeek < startWeek) endWeek = startWeek;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: endWeek,
                              decoration: const InputDecoration(
                                labelText: '结束周',
                                border: OutlineInputBorder(),
                              ),
                              items: _weekMenuItems(safeTotalWeeks),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  endWeek = value < startWeek
                                      ? startWeek
                                      : value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('保存课程'),
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final weeks = [
                              for (
                                var week = startWeek;
                                week <= endWeek;
                                week++
                              )
                                week,
                            ];
                            final course = Course(
                              name: nameController.text.trim(),
                              teacher: teacherController.text.trim(),
                              timeStr: _customCourseTimeText(
                                weekday,
                                startSlot,
                                endSlot,
                                startWeek,
                                endWeek,
                              ),
                              classroom: classroomController.text.trim(),
                              dayOfWeek: weekday,
                              timeSlot: startSlot,
                              endTimeSlot: endSlot,
                              weekList: weeks,
                              isCustom: true,
                            );
                            await ref
                                .read(
                                  customCoursesProvider(
                                    selectedSemester,
                                  ).notifier,
                                )
                                .addCourse(course);
                            ref.invalidate(scheduleProvider(selectedSemester));
                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已新增「${course.name}」')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    nameController.dispose();
    classroomController.dispose();
    teacherController.dispose();
  }
}

List<DropdownMenuItem<int>> _slotMenuItems() {
  return List.generate(_kTotalSlots, (index) {
    final slot = index + 1;
    return DropdownMenuItem(value: slot, child: Text(_slotLabel(slot)));
  });
}

List<DropdownMenuItem<int>> _weekMenuItems(int totalWeeks) {
  return List.generate(totalWeeks, (index) {
    final week = index + 1;
    return DropdownMenuItem(value: week, child: Text('第 $week 周'));
  });
}

String _weekdayName(int weekday) {
  return switch (weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    _ => '周日',
  };
}

String _slotLabel(int slot) {
  final times = _kSlotTimes[slot];
  if (times == null) return '第 $slot 节';
  return '$slot (${times.$1})';
}

String _customCourseTimeText(
  int weekday,
  int startSlot,
  int endSlot,
  int startWeek,
  int endWeek,
) {
  final weekText = startWeek == endWeek
      ? '第 $startWeek 周'
      : '第 $startWeek-$endWeek 周';
  final slotText = startSlot == endSlot
      ? '第 $startSlot 节'
      : '第 $startSlot-$endSlot 节';
  return '$weekText · ${_weekdayName(weekday)} · $slotText';
}

class _WeekNavigator extends ConsumerWidget {
  final DateTime semesterStart;
  final int selectedWeek;
  final int currentWeek;
  final bool sundayFirst;
  final int totalWeeks;

  const _WeekNavigator({
    required this.semesterStart,
    required this.selectedWeek,
    required this.currentWeek,
    required this.sundayFirst,
    required this.totalWeeks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semesterDoneWeek = totalWeeks + 1;
    final isVacation = selectedWeek == 0 || selectedWeek == semesterDoneWeek;
    final weekStart = isVacation
        ? _startOfWeek(DateTime.now(), sundayFirst: sundayFirst)
        : _weekStartOf(semesterStart, selectedWeek, sundayFirst: sundayFirst);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final isCur = selectedWeek == currentWeek;

    VoidCallback? onLeft;
    if (selectedWeek > 1 && selectedWeek <= totalWeeks) {
      onLeft = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(selectedWeek - 1);
    } else if (selectedWeek == semesterDoneWeek) {
      onLeft = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(totalWeeks);
    } else if (selectedWeek == 1) {
      onLeft = () => ref.read(selectedWeekProvider.notifier).setWeek(0);
    }

    VoidCallback? onRight;
    if (selectedWeek >= 1 && selectedWeek < totalWeeks) {
      onRight = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(selectedWeek + 1);
    } else if (selectedWeek == 0) {
      onRight = () => ref.read(selectedWeekProvider.notifier).setWeek(1);
    } else if (selectedWeek == totalWeeks) {
      onRight = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(semesterDoneWeek);
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
                    '${weekStart.month}/${weekStart.day} - '
                    '${weekEnd.month}/${weekEnd.day}',
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
                itemCount: totalWeeks,
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

class _TimetableGrid extends ConsumerStatefulWidget {
  final List<Course> courses;
  final String remark;
  final DateTime semesterStart;
  final int selectedWeek;
  final bool sundayFirst;
  final int totalWeeks;
  final String? selectedSemester;
  final bool showInactiveCourses;

  const _TimetableGrid({
    required this.courses,
    required this.remark,
    required this.semesterStart,
    required this.selectedWeek,
    required this.sundayFirst,
    required this.totalWeeks,
    required this.selectedSemester,
    required this.showInactiveCourses,
  });

  @override
  ConsumerState<_TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends ConsumerState<_TimetableGrid> {
  final ScrollController _horizontalController = ScrollController();
  double _headerScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_syncHeaderOffset);
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_syncHeaderOffset);
    _horizontalController.dispose();
    super.dispose();
  }

  void _syncHeaderOffset() {
    if (!mounted) return;
    final next = _horizontalController.hasClients
        ? _horizontalController.offset
        : 0.0;
    if (next == _headerScrollOffset) return;
    setState(() => _headerScrollOffset = next);
  }

  Map<int, List<Course>> _buildDayMap() {
    final map = <int, List<Course>>{};
    for (final c in widget.courses) {
      map.putIfAbsent(c.dayOfWeek, () => []).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final dayMap = _buildDayMap();
    final courseColorMap = _buildCourseColorMap(widget.courses);
    final isVacation =
        widget.selectedWeek == 0 ||
        widget.selectedWeek == widget.totalWeeks + 1;
    final weekStart = isVacation
        ? _startOfWeek(DateTime.now(), sundayFirst: widget.sundayFirst)
        : _weekStartOf(
            widget.semesterStart,
            widget.selectedWeek,
            sundayFirst: widget.sundayFirst,
          );
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final gridH = _kTotalSlots * _kSlotH;
    final totalWidth = _kTimeW + _kDayW * 7;
    final dayLabels = _weekdayLabels(sundayFirst: widget.sundayFirst);
    final orderedWeekdays = _orderedWeekdays(sundayFirst: widget.sundayFirst);

    return Column(
      children: [
        Container(
          height: 44,
          color: Colors.blue.shade50,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: totalWidth,
              maxWidth: totalWidth,
              minHeight: 44,
              maxHeight: 44,
              child: Transform.translate(
                offset: Offset(-_headerScrollOffset, 0),
                child: SizedBox(
                  width: totalWidth,
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: _kTimeW, height: 44),
                      for (int d = 0; d < 7; d++)
                        _buildDayHeader(
                          context,
                          weekStart.add(Duration(days: d)),
                          dayLabels[d],
                          todayDay,
                          isVacation,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(height: 1, color: Colors.grey.shade300),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth > totalWidth
                    ? constraints.maxWidth
                    : totalWidth;

                return Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: gridH,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(width: _kTimeW),
                                  for (int day = 0; day < 7; day++)
                                    _buildDayColumn(
                                      context,
                                      dayMap[orderedWeekdays[day]] ?? [],
                                      weekStart.add(Duration(days: day)),
                                      courseColorMap,
                                    ),
                                ],
                              ),
                            ),
                            if (widget.remark.isNotEmpty)
                              Container(
                                width: contentWidth,
                                constraints: const BoxConstraints(
                                  minHeight: _kRemarkH,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.amber.shade200,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: _kTimeW - 12,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
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
                                    Expanded(
                                      child: Text(
                                        widget.remark,
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
                            SizedBox(
                              width: contentWidth,
                              height: _kTimetableBottomInset,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Container(
                        width: _kTimeW,
                        height: gridH,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            right: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: _buildTimeColumn(gridH),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    DateTime date,
    String dayLabel,
    DateTime todayDay,
    bool isVacation,
  ) {
    final isToday = date == todayDay && !isVacation;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: _kDayW,
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '周$dayLabel',
            maxLines: 1,
            overflow: TextOverflow.clip,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 12,
              height: 1.1,
              fontWeight: FontWeight.bold,
              color: isToday ? primaryColor : null,
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 16,
            child: Center(
              child: isToday
                  ? Container(
                      height: 16,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${date.month}/${date.day}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      '${date.month}/${date.day}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        color: Colors.grey.shade600,
                      ),
                    ),
            ),
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
    DateTime courseDate,
    Map<String, Color> courseColorMap,
  ) {
    final gridH = _kTotalSlots * _kSlotH;
    final placements = _buildCoursePlacements(dayCourses);
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
          for (final placement in placements)
            Positioned(
              key: ValueKey(placement.key),
              top: (placement.startSlot - 1) * _kSlotH + 2,
              left: placement.left,
              width: placement.width,
              height: placement.slotSpan * _kSlotH - 4,
              child: placement.isSummary
                  ? _InactiveCourseSummaryCell(courses: placement.courses)
                  : CourseCell(
                      course: placement.course,
                      isActive: placement.course.isActiveInWeek(
                        widget.selectedWeek,
                      ),
                      color: courseColorMap[_courseColorKey(placement.course)],
                      onDelete: placement.course.isCustom
                          ? () => _deleteCustomCourse(context, placement.course)
                          : null,
                    ),
            ),
        ],
      ),
    );
  }

  List<_CoursePlacement> _buildCoursePlacements(List<Course> dayCourses) {
    final activeCourses = dayCourses
        .where((course) => course.isActiveInWeek(widget.selectedWeek))
        .toList();
    final inactiveCourses = widget.showInactiveCourses
        ? (dayCourses
              .where(
                (course) =>
                    !course.isActiveInWeek(widget.selectedWeek) &&
                    !activeCourses.any(
                      (active) => _coursesOverlap(course, active),
                    ),
              )
              .toList()
            ..sort(_compareCoursesForLayout))
        : <Course>[];

    const outerPadding = 2.0;
    final fullWidth = _kDayW - outerPadding * 2;
    final inactivePlacements = <_CoursePlacement>[];
    var index = 0;

    while (index < inactiveCourses.length) {
      final cluster = <Course>[];
      var clusterEndSlot = inactiveCourses[index].endTimeSlot;

      while (index < inactiveCourses.length) {
        final course = inactiveCourses[index];
        if (cluster.isNotEmpty && course.timeSlot > clusterEndSlot) break;
        cluster.add(course);
        if (course.endTimeSlot > clusterEndSlot) {
          clusterEndSlot = course.endTimeSlot;
        }
        index++;
      }

      inactivePlacements.add(
        _CoursePlacement(
          courses: cluster,
          left: outerPadding,
          width: fullWidth,
        ),
      );
    }

    final activePlacements =
        activeCourses
            .toList()
            .map(
              (course) => _CoursePlacement(
                courses: [course],
                left: outerPadding,
                width: fullWidth,
              ),
            )
            .toList()
          ..sort((a, b) => _compareCoursesForLayout(a.course, b.course));

    return [...inactivePlacements, ...activePlacements];
  }

  int _compareCoursesForLayout(Course a, Course b) {
    final startCompare = a.timeSlot.compareTo(b.timeSlot);
    if (startCompare != 0) return startCompare;

    final endCompare = a.endTimeSlot.compareTo(b.endTimeSlot);
    if (endCompare != 0) return endCompare;

    final activeCompare = (a.isActiveInWeek(widget.selectedWeek) ? 0 : 1)
        .compareTo(b.isActiveInWeek(widget.selectedWeek) ? 0 : 1);
    if (activeCompare != 0) return activeCompare;

    if (a.isExam != b.isExam) return a.isExam ? 1 : -1;
    return a.name.compareTo(b.name);
  }

  bool _coursesOverlap(Course a, Course b) {
    return a.timeSlot <= b.endTimeSlot && b.timeSlot <= a.endTimeSlot;
  }

  Future<void> _deleteCustomCourse(BuildContext context, Course course) async {
    await ref
        .read(customCoursesProvider(widget.selectedSemester).notifier)
        .removeCourse(course);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除「${course.name}」')));
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

class _CoursePlacement {
  final List<Course> courses;
  final double left;
  final double width;

  const _CoursePlacement({
    required this.courses,
    required this.left,
    required this.width,
  });

  Course get course => courses.first;

  bool get isSummary => courses.length > 1;

  int get startSlot => courses
      .map((course) => course.timeSlot)
      .reduce((value, element) => value < element ? value : element);

  int get endSlot => courses
      .map((course) => course.endTimeSlot)
      .reduce((value, element) => value > element ? value : element);

  int get slotSpan => endSlot - startSlot + 1;

  String get key => isSummary
      ? 'inactive_summary_${courses.map((course) => '${course.name}_${course.timeStr}').join('|')}'
      : '${course.name}_${course.timeStr}';
}

class _InactiveCourseSummaryCell extends StatelessWidget {
  final List<Course> courses;

  const _InactiveCourseSummaryCell({required this.courses});

  @override
  Widget build(BuildContext context) {
    final title = courses.length == 1
        ? courses.first.name
        : '本周无课 · ${courses.length} 门';
    final subtitle = courses.length == 1
        ? courses.first.classroom
        : courses.take(2).map((course) => course.name).join('、');

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300, width: 0.6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                  height: 1.15,
                ),
              ),
              const Spacer(),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.layers_outlined, color: Colors.grey),
                SizedBox(width: 10),
                Text(
                  '本周无课的重叠课程',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final course in courses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${course.timeSlot}-${course.endTimeSlot}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (course.classroom.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                course.classroom,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                        ],
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
}

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
