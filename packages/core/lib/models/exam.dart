class Exam {
  final String courseName;
  final String teacher;
  final String examTime;
  final String examRoom;
  final String seatNumber;
  final String campus;
  final String ticketNumber;

  const Exam({
    required this.courseName,
    required this.teacher,
    required this.examTime,
    required this.examRoom,
    required this.seatNumber,
    required this.campus,
    required this.ticketNumber,
  });

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
        courseName: json['courseName'] as String? ?? '',
        teacher: json['teacher'] as String? ?? '',
        examTime: json['examTime'] as String? ?? '',
        examRoom: json['examRoom'] as String? ?? '',
        seatNumber: json['seatNumber'] as String? ?? '-',
        campus: json['campus'] as String? ?? '',
        ticketNumber: json['ticketNumber'] as String? ?? '-',
      );
}
