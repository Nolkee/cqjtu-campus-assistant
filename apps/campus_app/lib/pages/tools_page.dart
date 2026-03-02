import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/providers.dart';
import '../widgets/grade_item.dart';

// ── 学期选项生成 ──────────────────────────────────────────────
/// 生成学期列表：向后1个学期 + 当前学期 + 向前8个学年（共18个选项）
/// 顺序：最新学期在前
List<String> _buildSemesterOptions() {
  final now = DateTime.now();
  // 8 月及以后算上半学年（第 1 学期），否则算下半（第 2 学期）
  int currentYear = now.month >= 8 ? now.year : now.year - 1;
  int currentTerm = now.month >= 8 ? 1 : 2;

  // 计算起始点：向后推 1 个学期
  int startYear = currentYear;
  int startTerm = currentTerm + 1;
  if (startTerm > 2) {
    startTerm = 1;
    startYear++;
  }

  final options = <String>[];
  int y = startYear;
  int t = startTerm;

  // 1(向后) + 1(当前) + 16(向前8年) = 18 个选项
  for (int i = 0; i < 18; i++) {
    options.add('$y-${y + 1}-$t');
    // 往下循环时往前推一个学期
    if (t == 2) {
      t = 1;
    } else {
      t = 2;
      y--;
    }
  }
  return options;
}

// ── 学期选择底部弹窗 ─────────────────────────────────────────
Future<String?> showSemesterPicker(
  BuildContext context, {
  required String current, // 当前选中值，空字符串表示"全部"
}) async {
  final options = _buildSemesterOptions();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true, // [新增] 允许弹窗高度随内容伸展
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      // [新增] 限制最大高度为屏幕的 70%，体验更好
      final maxHeight = MediaQuery.of(ctx).size.height * 0.7;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min, // 核心：让外部 Column 紧贴内容
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '选择学期',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // 查全部入口
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: const Text('查全部'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // [新增] 用 Flexible + SingleChildScrollView 包裹列表，完美解决越界和滑动
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: options.map((s) {
                      final isSelected = s == current;
                      // 解析显示更友好的名称
                      final parts = s.split('-');
                      final label = parts.length == 3
                          ? '${parts[0]}-${parts[1]} 学年  第 ${parts[2]} 学期'
                          : s;
                      return ListTile(
                        title: Text(label),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: Theme.of(ctx).colorScheme.primary,
                              )
                            : null,
                        selected: isSelected,
                        selectedColor: Theme.of(ctx).colorScheme.primary,
                        onTap: () => Navigator.pop(ctx, s),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

// ── 工具主页 (如果你之后还要用到的话保留，不需要也可以删掉) ─────────────────────────
class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('工具')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolTile(
            icon: Icons.grade_outlined,
            title: '成绩查询',
            subtitle: '查看历史学期成绩与 GPA 排名',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GradesPage()),
            ), // 已修改为公开的 GradesPage
          ),
          _ToolTile(
            icon: Icons.event_note_outlined,
            title: '考试安排',
            subtitle: '查看当前学期考试时间与考场',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExamsPage()),
            ), // 已修改为公开的 ExamsPage
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ── 成绩页 (已修改为公开类) ────────────────────────────────────────────────────
class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  String _semester = ''; // 空字符串 = 全部

  String get _semesterLabel {
    if (_semester.isEmpty) return '全部学期';
    final parts = _semester.split('-');
    return parts.length == 3
        ? '${parts[0]}-${parts[1]}  第${parts[2]}学期'
        : _semester;
  }

  @override
  Widget build(BuildContext context) {
    final gradesAsync = ref.watch(gradesProvider(_semester));

    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩查询'),
        actions: [
          // 学期筛选入口：显示当前选中学期
          TextButton.icon(
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(_semesterLabel, style: const TextStyle(fontSize: 13)),
            onPressed: () async {
              final result = await showSemesterPicker(
                context,
                current: _semester,
              );
              // result == null 说明用户关闭弹窗未选择，保持原值
              if (result != null && result != _semester) {
                setState(() => _semester = result);
              }
            },
          ),
        ],
      ),
      body: gradesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString()),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(gradesProvider(_semester)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (result) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (result.summary.isNotEmpty) _SummaryCard(result.summary),
            const SizedBox(height: 12),
            ...result.grades.map((g) => GradeItem(grade: g)),
            if (result.grades.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('暂无成绩数据', style: TextStyle(color: Colors.grey)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, String> summary;
  const _SummaryCard(this.summary);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '学业汇总',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Item('GPA', summary['gpa'] ?? '-'),
                _Item('均分', summary['avgScore'] ?? '-'),
                _Item('班级排名', summary['classRank'] ?? '-'),
                _Item('专业排名', summary['majorRank'] ?? '-'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String label;
  final String value;
  const _Item(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  );
}

// ── 考试安排页 (已修改为公开类) ─────────────────────────────────────────────────
class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  // null = 当前学期（后端默认）
  String? _semester;

  String get _semesterLabel {
    if (_semester == null) return '当前学期';
    final parts = _semester!.split('-');
    return parts.length == 3
        ? '${parts[0]}-${parts[1]}  第${parts[2]}学期'
        : _semester!;
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsProvider(_semester));

    return Scaffold(
      appBar: AppBar(
        title: const Text('考试安排'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(_semesterLabel, style: const TextStyle(fontSize: 13)),
            onPressed: () async {
              final result = await showSemesterPicker(
                context,
                current: _semester ?? '',
              );
              if (result != null) {
                setState(() {
                  // 空字符串映射回 null（后端默认当前学期）
                  _semester = result.isEmpty ? null : result;
                });
              }
            },
          ),
        ],
      ),
      body: examsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (exams) {
          if (exams.isEmpty) {
            return const Center(
              child: Text('当前学期暂无考试安排', style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: exams.length,
            itemBuilder: (_, i) {
              final exam = exams[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.courseName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Divider(),
                      _ExamRow(Icons.access_time_outlined, exam.examTime),
                      _ExamRow(Icons.room_outlined, exam.examRoom),
                      _ExamRow(
                        Icons.event_seat_outlined,
                        '座位号：${exam.seatNumber}',
                      ),
                      _ExamRow(
                        Icons.confirmation_number_outlined,
                        '准考证：${exam.ticketNumber}',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ExamRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
