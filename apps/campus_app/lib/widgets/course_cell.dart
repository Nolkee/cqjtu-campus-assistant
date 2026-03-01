import 'package:flutter/material.dart';
import 'package:core/models/course.dart';

class CourseCell extends StatelessWidget {
  final Course course;
  final bool isActive;

  const CourseCell({
    super.key,
    required this.course,
    this.isActive = true,
  });

  static const _palette = [
    Color(0xFF5B9BD5),
    Color(0xFF70AD47),
    Color(0xFFED7D31),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
    Color(0xFFE74C3C),
    Color(0xFF3498DB),
    Color(0xFFF39C12),
  ];

  Color get _baseColor  => _palette[course.name.hashCode.abs() % _palette.length];
  Color get _cellColor  => isActive ? _baseColor : Colors.grey.shade300;
  Color get _textColor  => isActive ? Colors.white : Colors.grey.shade500;
  Color get _subColor   => isActive ? Colors.white70 : Colors.grey.shade400;

  @override
  Widget build(BuildContext context) {
    // 高度完全由父级 Positioned 决定，这里不设固定 height
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: _cellColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
              maxLines: course.slotSpan >= 2 ? 4 : 2,
              overflow: TextOverflow.ellipsis,
            ),
            // 只有跨 2 节及以上才显示教室，避免单节时溢出
            if (course.slotSpan >= 2) ...[
              const Spacer(),
              Text(
                course.classroom,
                style: TextStyle(fontSize: 10, color: _subColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(course.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (!isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('本周无课',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ),
            ]),
            const SizedBox(height: 16),
            _InfoRow(Icons.person_outline, course.teacher),
            _InfoRow(Icons.access_time_outlined, course.timeStr),
            _InfoRow(Icons.room_outlined, course.classroom),
            _InfoRow(
              Icons.calendar_month_outlined,
              // 改为展示这门课一共要上多少周，节次保持不变
              '共 ${course.weekList.length} 周 | 第 ${course.timeSlot}–${course.endTimeSlot} 节',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}