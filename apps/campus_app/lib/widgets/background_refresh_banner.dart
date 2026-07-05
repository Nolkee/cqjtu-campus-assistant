import 'package:flutter/material.dart';

class BackgroundRefreshBanner extends StatelessWidget {
  const BackgroundRefreshBanner({
    super.key,
    required this.onRefresh,
    this.message = '后台刷新连续失败，当前显示的是上次缓存。',
  });

  final VoidCallback onRefresh;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem, color: Colors.amber.shade800, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onSurface, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('手动刷新'),
          ),
        ],
      ),
    );
  }
}
