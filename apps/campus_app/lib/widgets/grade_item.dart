import 'package:flutter/material.dart';
import 'package:core/models/grade.dart';

class GradeItem extends StatelessWidget {
  final Grade grade;

  const GradeItem({super.key, required this.grade});

  Color get _scoreColor {
    final n = double.tryParse(grade.score);
    if (n == null) return Colors.blue;
    if (n >= 90) return Colors.green;
    if (n >= 75) return Colors.blue;
    if (n >= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(grade.courseName,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
            '${grade.semester}  ${grade.credits} 学分  绩点 ${grade.gradePoint}'),
        trailing: Text(
          grade.score,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _scoreColor),
        ),
      ),
    );
  }
}
