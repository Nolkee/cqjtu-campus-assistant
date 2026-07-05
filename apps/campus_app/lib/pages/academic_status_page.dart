import 'package:core/models/grade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/providers.dart';
import '../widgets/background_refresh_banner.dart';

class AcademicStatusPage extends ConsumerWidget {
  const AcademicStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradesState = ref.watch(gradesProvider(''));

    return Scaffold(
      appBar: AppBar(title: const Text('学业情况')),
      body: gradesState.when(
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _AcademicError(
          message: error.toString(),
          onRetry: () =>
              ref.read(gradesProvider('').notifier).refresh(forceRefresh: true),
        ),
        data: (result) => _AcademicStatusContent(
          summary: result.summary,
          grades: result.grades,
          showRefreshBanner: gradesState.shouldOfferManualRefresh,
          onRefresh: () =>
              ref.read(gradesProvider('').notifier).refresh(forceRefresh: true),
        ),
      ),
    );
  }
}

class _AcademicStatusContent extends StatelessWidget {
  const _AcademicStatusContent({
    required this.summary,
    required this.grades,
    required this.showRefreshBanner,
    required this.onRefresh,
  });

  final Map<String, String> summary;
  final List<Grade> grades;
  final bool showRefreshBanner;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final stats = _AcademicStats.fromGrades(grades);

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (showRefreshBanner) BackgroundRefreshBanner(onRefresh: onRefresh),
          _OverviewCard(summary: summary, stats: stats),
          const SizedBox(height: 12),
          _CreditCard(stats: stats),
          if (grades.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(
                child: Text('暂无学业数据', style: TextStyle(color: Colors.grey)),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.summary, required this.stats});

  final Map<String, String> summary;
  final _AcademicStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 4,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '学业概览',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 2.7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _MetricTile(label: 'GPA', value: summary['gpa'] ?? '-'),
                _MetricTile(label: '均分', value: summary['avgScore'] ?? '-'),
                _MetricTile(label: '班级排名', value: summary['classRank'] ?? '-'),
                _MetricTile(label: '专业排名', value: summary['majorRank'] ?? '-'),
              ],
            ),
            if (stats.weightedAverage != null) ...[
              const SizedBox(height: 12),
              Text(
                '按当前可读取成绩估算加权均分 ${stats.weightedAverage!.toStringAsFixed(1)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.stats});

  final _AcademicStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '学分进度',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: '已读课程',
                    value: '${stats.totalCourses}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: '通过学分',
                    value: _formatNumber(stats.passedCredits),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: '待关注',
                    value: '${stats.failedCourses}',
                    valueColor: stats.failedCourses > 0
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? Theme.of(context).colorScheme.primary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademicError extends StatelessWidget {
  const _AcademicError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcademicStats {
  const _AcademicStats({
    required this.totalCourses,
    required this.failedCourses,
    required this.passedCredits,
    this.weightedAverage,
  });

  final int totalCourses;
  final int failedCourses;
  final double passedCredits;
  final double? weightedAverage;

  factory _AcademicStats.fromGrades(List<Grade> grades) {
    var passedCredits = 0.0;
    var failedCourses = 0;
    var weightedScore = 0.0;
    var weightedCredits = 0.0;

    for (final grade in grades) {
      final score = double.tryParse(grade.score.trim());
      final credit = double.tryParse(grade.credits.trim()) ?? 0;
      if (score == null) {
        continue;
      }

      if (score >= 60) {
        passedCredits += credit;
      } else {
        failedCourses += 1;
      }
      if (credit > 0) {
        weightedScore += score * credit;
        weightedCredits += credit;
      }
    }

    return _AcademicStats(
      totalCourses: grades.length,
      failedCourses: failedCourses,
      passedCredits: passedCredits,
      weightedAverage: weightedCredits == 0
          ? null
          : weightedScore / weightedCredits,
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}
