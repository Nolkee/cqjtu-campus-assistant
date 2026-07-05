import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/models/grade.dart';
import '../features/study_progress/study_progress_providers.dart';
import '../utils/providers.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/grade_item.dart';
import 'academic_status_page.dart';
import 'campus_service_webview_page.dart';
import 'electricity_page.dart';
import 'leave_apply_page.dart';
import 'study_progress_page.dart';

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

class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  static const _emailUrl = 'https://i.cqjtu.edu.cn/email/#/index';
  static const _evaluationUrl = 'https://jwzlapp.cqjtu.edu.cn/#/login';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studyProgress = ref.watch(studyProgressProvider);
    final studySummary = ref.watch(studyCreditProgressSummaryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('服务'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _AcademicProgressServiceCard(
            summary: studySummary,
            hasData: studyProgress.hasData,
            isLoading: studyProgress.isLoading,
            hasError: studyProgress.hasError && !studyProgress.hasData,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AcademicStatusPage()),
            ),
            onRefresh: () => ref
                .read(studyProgressProvider.notifier)
                .refresh(forceRefresh: true),
          ),
          const SizedBox(height: 18),
          _ServiceSection(
            title: '教务',
            children: [
              _ServiceTile(
                icon: Icons.grade_outlined,
                color: Colors.orange,
                title: '成绩查询',
                subtitle: '成绩列表与明细',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GradesPage()),
                ),
              ),
              _ServiceTile(
                icon: Icons.event_note_outlined,
                color: Colors.purple,
                title: '考试安排',
                subtitle: '考试时间、考场与座位',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExamsPage()),
                ),
              ),
              _ServiceTile(
                icon: Icons.schema_outlined,
                color: Colors.teal,
                title: '培养计划',
                subtitle: '执行计划与培养方案',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StudyProgressPage()),
                ),
              ),
              _ServiceTile(
                icon: Icons.rate_review_outlined,
                color: Colors.deepPurple,
                title: '课程评价',
                subtitle: '进入评教系统',
                onTap: () => _openWebService(
                  context,
                  title: '课程评价',
                  url: _evaluationUrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ServiceSection(
            title: '校园',
            children: [
              _ServiceTile(
                icon: Icons.bolt_outlined,
                color: Colors.amber.shade800,
                title: '宿舍电费',
                subtitle: '余额查询与充值',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ElectricityPage()),
                ),
              ),
              _ServiceTile(
                icon: Icons.assignment_return_outlined,
                color: Colors.green,
                title: '请假申请',
                subtitle: '出入校与请假记录',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LeaveApplyPage()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ServiceSection(
            title: '在线系统',
            children: [
              _ServiceTile(
                icon: Icons.alternate_email,
                color: Colors.blue,
                title: '邮箱服务',
                subtitle: '学校邮箱与别名',
                onTap: () =>
                    _openWebService(context, title: '邮箱服务', url: _emailUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openWebService(
    BuildContext context, {
    required String title,
    required String url,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CampusServiceWebViewPage(title: title, initialUrl: url),
      ),
    );
  }
}

class _AcademicProgressServiceCard extends StatelessWidget {
  const _AcademicProgressServiceCard({
    required this.summary,
    required this.hasData,
    required this.isLoading,
    required this.hasError,
    required this.onTap,
    required this.onRefresh,
  });

  final StudyCreditProgressSummary summary;
  final bool hasData;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6ECF3)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '学业情况',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF25313D),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _academicCardSubtitle(summary, hasData),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF667085),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (hasError || !hasData)
                      IconButton(
                        tooltip: hasError ? '重新获取学业情况' : '同步培养计划数据',
                        icon: const Icon(Icons.refresh, size: 19),
                        visualDensity: VisualDensity.compact,
                        onPressed: onRefresh,
                      )
                    else
                      const Icon(Icons.chevron_right, color: Colors.black26),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final topContent = constraints.maxWidth < 320
                        ? Column(
                            children: [
                              _RequiredCreditRing(
                                summary: summary,
                                hasData: hasData,
                              ),
                              const SizedBox(height: 16),
                              _RequiredCreditLegend(
                                summary: summary,
                                hasData: hasData,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              _RequiredCreditRing(
                                summary: summary,
                                hasData: hasData,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _RequiredCreditLegend(
                                  summary: summary,
                                  hasData: hasData,
                                ),
                              ),
                            ],
                          );

                    return Column(
                      children: [
                        topContent,
                        const SizedBox(height: 18),
                        const Divider(height: 1, color: Color(0xFFE6ECF3)),
                        const SizedBox(height: 14),
                        _EarnedCreditProgressGrid(
                          summary: summary,
                          hasData: hasData,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequiredCreditRing extends StatelessWidget {
  const _RequiredCreditRing({required this.summary, required this.hasData});

  final StudyCreditProgressSummary summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      height: 116,
      child: CustomPaint(
        painter: _CreditRingPainter(summary.buckets),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  hasData ? _formatCredit(summary.requiredCredits) : '--',
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF25313D),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '应修学分',
                style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequiredCreditLegend extends StatelessWidget {
  const _RequiredCreditLegend({required this.summary, required this.hasData});

  final StudyCreditProgressSummary summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < summary.buckets.length; i++) ...[
          _RequiredCreditLegendRow(
            bucket: summary.buckets[i],
            totalRequired: summary.requiredCredits,
            hasData: hasData,
          ),
          if (i != summary.buckets.length - 1)
            const Divider(height: 18, color: Color(0xFFE6ECF3)),
        ],
      ],
    );
  }
}

class _RequiredCreditLegendRow extends StatelessWidget {
  const _RequiredCreditLegendRow({
    required this.bucket,
    required this.totalRequired,
    required this.hasData,
  });

  final StudyCreditBucketView bucket;
  final double totalRequired;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final percent = totalRequired <= 0
        ? 0
        : (bucket.requiredCredits / totalRequired * 100).round();
    final color = _creditCategoryColor(bucket.category);

    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '应修${bucket.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF4B5563),
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            hasData ? '$percent%' : '--',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
        ),
        Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: const Color(0xFFE6ECF3),
        ),
        SizedBox(
          width: 46,
          child: Text(
            hasData ? '${_formatCredit(bucket.requiredCredits)}分' : '--',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF25313D),
            ),
          ),
        ),
      ],
    );
  }
}

class _EarnedCreditProgressGrid extends StatelessWidget {
  const _EarnedCreditProgressGrid({
    required this.summary,
    required this.hasData,
  });

  final StudyCreditProgressSummary summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 520;
        final tileWidth = useTwoColumns
            ? (constraints.maxWidth - 28) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 28,
          runSpacing: 12,
          children: [
            for (final bucket in summary.buckets)
              SizedBox(
                width: tileWidth,
                child: _EarnedCreditProgressTile(
                  bucket: bucket,
                  hasData: hasData,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EarnedCreditProgressTile extends StatelessWidget {
  const _EarnedCreditProgressTile({
    required this.bucket,
    required this.hasData,
  });

  final StudyCreditBucketView bucket;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final progress = !hasData || bucket.requiredCredits <= 0
        ? 0.0
        : (bucket.earnedCredits / bucket.requiredCredits).clamp(0.0, 1.0);
    final color = _creditCategoryColor(bucket.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '已修${bucket.label}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF25313D),
                ),
              ),
            ),
            Text(
              hasData ? '${_formatCredit(bucket.earnedCredits)}分' : '--',
              style: const TextStyle(color: Color(0xFF25313D)),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: color,
            backgroundColor: const Color(0xFFE8EAED),
          ),
        ),
      ],
    );
  }
}

class _CreditRingPainter extends CustomPainter {
  const _CreditRingPainter(this.buckets);

  final List<StudyCreditBucketView> buckets;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.22;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFFE8EAED);

    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, basePaint);

    final total = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.requiredCredits,
    );
    if (total <= 0) return;

    var start = -math.pi / 2;
    const gap = 0.035;
    for (final bucket in buckets) {
      if (bucket.requiredCredits <= 0) continue;
      final sweep = math.pi * 2 * bucket.requiredCredits / total;
      final visibleSweep = (sweep - gap).clamp(0.0, sweep);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = _creditCategoryColor(bucket.category);
      canvas.drawArc(arcRect, start, visibleSweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _CreditRingPainter oldDelegate) =>
      oldDelegate.buckets != buckets;
}

String _formatCredit(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _academicCardSubtitle(StudyCreditProgressSummary summary, bool hasData) {
  if (!hasData) return '等待培养计划数据同步';
  if (summary.currentSemester.trim().isEmpty) return '已联动培养计划';
  return '已联动培养计划 · ${summary.currentSemester}';
}

Color _creditCategoryColor(StudyCreditCategory category) {
  switch (category) {
    case StudyCreditCategory.compulsory:
      return const Color(0xFF2F63D7);
    case StudyCreditCategory.elective:
      return const Color(0xFF5AA9FF);
    case StudyCreditCategory.schoolElective:
      return const Color(0xFFFF8452);
  }
}

class _ServiceSection extends StatelessWidget {
  const _ServiceSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    color: Color(0xFFF0F0F0),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: Colors.black26),
      onTap: onTap,
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
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString()),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref
                    .read(gradesProvider(_semester).notifier)
                    .refresh(forceRefresh: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (result) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (gradesAsync.shouldOfferManualRefresh)
              BackgroundRefreshBanner(
                onRefresh: () => ref
                    .read(gradesProvider(_semester).notifier)
                    .refresh(forceRefresh: true),
              ),
            if (result.summary.isNotEmpty) _SummaryCard(result.summary),
            const SizedBox(height: 12),
            ...result.grades.map(
              (g) => GradeItem(
                grade: g,
                onTap: g.hasDetail
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GradeDetailPage(grade: g),
                        ),
                      )
                    : null,
              ),
            ),
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

class GradeDetailPage extends ConsumerWidget {
  const GradeDetailPage({super.key, required this.grade});

  final Grade grade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (grade: grade);
    final detailAsync = ref.watch(gradeDetailProvider(arg));
    final isFetching = detailAsync.isRefreshing && !detailAsync.hasValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩明细'),
        actions: [
          IconButton(
            tooltip: '刷新明细',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(gradeDetailProvider(arg).notifier)
                .refresh(forceRefresh: true),
          ),
        ],
      ),
      body: detailAsync.when(
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => _GradeDetailContent(
          grade: grade,
          detail: const GradeDetail(items: [], totalScore: ''),
          isFetching: true,
        ),
        error: (error, _) => _GradeDetailError(
          grade: grade,
          message: error.toString(),
          onRetry: () => ref
              .read(gradeDetailProvider(arg).notifier)
              .refresh(forceRefresh: true),
        ),
        data: (detail) => _GradeDetailContent(
          grade: grade,
          detail: detail,
          isFetching: isFetching,
          banner: detailAsync.shouldOfferManualRefresh
              ? BackgroundRefreshBanner(
                  onRefresh: () => ref
                      .read(gradeDetailProvider(arg).notifier)
                      .refresh(forceRefresh: true),
                )
              : null,
        ),
      ),
    );
  }
}

class _GradeDetailContent extends StatelessWidget {
  const _GradeDetailContent({
    required this.grade,
    required this.detail,
    required this.isFetching,
    this.banner,
  });

  final Grade grade;
  final GradeDetail detail;
  final bool isFetching;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final total = detail.totalScore.trim().isEmpty
        ? grade.score
        : detail.totalScore.trim();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ?banner,
        _GradeHeroCard(grade: grade, totalScore: total),
        const SizedBox(height: 12),
        if (detail.items.isEmpty)
          _DetailEmptyState(isFetching: isFetching)
        else
          _BreakdownCard(items: detail.items),
      ],
    );
  }
}

class _GradeHeroCard extends StatelessWidget {
  const _GradeHeroCard({required this.grade, required this.totalScore});

  final Grade grade;
  final String totalScore;

  Color _scoreColor(BuildContext context) {
    final score = double.tryParse(totalScore);
    if (score == null) return Theme.of(context).colorScheme.primary;
    if (score >= 90) return Colors.green.shade700;
    if (score >= 75) return Theme.of(context).colorScheme.primary;
    if (score >= 60) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grade.courseName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${grade.semester}  ${grade.credits} 学分  绩点 ${grade.gradePoint}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  if (grade.courseAttribute.isNotEmpty ||
                      grade.courseNature.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          grade.courseAttribute,
                          grade.courseNature,
                        ].where((text) => text.trim().isNotEmpty).join(' · '),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              children: [
                Text(
                  totalScore,
                  style: TextStyle(
                    color: color,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '总成绩',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.items});

  final List<GradeDetailItem> items;

  @override
  Widget build(BuildContext context) {
    final segments = _buildBreakdownSegments(items);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '成绩构成',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (segments.isEmpty)
              Text('暂无可展示的成绩构成', style: TextStyle(color: Colors.grey.shade600))
            else ...[
              _SegmentedBreakdownBar(segments: segments),
              const SizedBox(height: 14),
              for (var i = 0; i < segments.length; i++) ...[
                _BreakdownRow(segment: segments[i]),
                if (i != segments.length - 1) const Divider(height: 24),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

const _breakdownPalette = <Color>[
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFFE11D48),
  Color(0xFF0891B2),
  Color(0xFF7C3AED),
];

class _BreakdownSegment {
  const _BreakdownSegment({
    required this.item,
    required this.ratio,
    required this.color,
    required this.weightedScore,
  });

  final GradeDetailItem item;
  final double ratio;
  final Color color;
  final double? weightedScore;
}

List<_BreakdownSegment> _buildBreakdownSegments(List<GradeDetailItem> items) {
  final segments = <_BreakdownSegment>[];

  for (final item in items) {
    final ratio = _parsePercent(item.ratio);
    if (ratio == null || ratio <= 0) continue;

    final normalizedRatio = ratio > 1 ? 1.0 : ratio;
    final score = double.tryParse(item.score.trim());
    segments.add(
      _BreakdownSegment(
        item: item,
        ratio: normalizedRatio,
        color: _breakdownPalette[segments.length % _breakdownPalette.length],
        weightedScore: score == null ? null : score * normalizedRatio,
      ),
    );
  }

  return segments;
}

class _SegmentedBreakdownBar extends StatelessWidget {
  const _SegmentedBreakdownBar({required this.segments});

  final List<_BreakdownSegment> segments;

  int _flexFor(double ratio) {
    final flex = (ratio * 1000).round();
    return flex <= 0 ? 1 : flex;
  }

  @override
  Widget build(BuildContext context) {
    final usedRatio = segments.fold<double>(
      0,
      (total, segment) => total + segment.ratio,
    );
    final remainder = usedRatio >= 1 ? 0.0 : 1 - usedRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                flex: _flexFor(segment.ratio),
                child: ColoredBox(
                  color: segment.color,
                  child: const SizedBox.expand(),
                ),
              ),
            if (remainder > 0)
              Expanded(
                flex: _flexFor(remainder),
                child: ColoredBox(
                  color: Colors.grey.shade200,
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.segment});

  final _BreakdownSegment segment;

  @override
  Widget build(BuildContext context) {
    final item = segment.item;
    final weighted = segment.weightedScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: segment.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              item.score.isEmpty ? '-' : item.score,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '占比 ${item.ratio.isEmpty ? '-' : item.ratio}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const Spacer(),
            Text(
              weighted == null ? '折算 -' : '折算 ${weighted.toStringAsFixed(1)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailEmptyState extends StatelessWidget {
  const _DetailEmptyState({required this.isFetching});

  final bool isFetching;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          children: [
            Icon(
              isFetching ? Icons.cloud_sync_outlined : Icons.info_outline,
              color: Colors.grey.shade500,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              isFetching ? '正在后台获取成绩明细' : '该课程暂无可展示的明细',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeDetailError extends StatelessWidget {
  const _GradeDetailError({
    required this.grade,
    required this.message,
    required this.onRetry,
  });

  final Grade grade;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GradeHeroCard(grade: grade, totalScore: grade.score),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新获取'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

double? _parsePercent(String value) {
  final normalized = value.trim().replaceAll('%', '');
  final parsed = double.tryParse(normalized);
  if (parsed == null) return null;
  return parsed / 100;
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
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (exams) {
          if (exams.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (examsAsync.shouldOfferManualRefresh)
                  BackgroundRefreshBanner(
                    onRefresh: () => ref
                        .read(examsProvider(_semester).notifier)
                        .refresh(forceRefresh: true),
                  ),
                const SizedBox(height: 120),
                const Center(
                  child: Text(
                    '当前学期暂无考试安排',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount:
                exams.length + (examsAsync.shouldOfferManualRefresh ? 1 : 0),
            itemBuilder: (_, i) {
              if (examsAsync.shouldOfferManualRefresh && i == 0) {
                return BackgroundRefreshBanner(
                  onRefresh: () => ref
                      .read(examsProvider(_semester).notifier)
                      .refresh(forceRefresh: true),
                );
              }
              final examIndex =
                  i - (examsAsync.shouldOfferManualRefresh ? 1 : 0);
              final exam = exams[examIndex];
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
