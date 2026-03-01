import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';

abstract class CampusBackend {
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  });

  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  });

  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  });

  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  });

  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  });

  Future<String> rechargeElec(String username, double amount);

  Future<String> getPayCodeToken(String username);

  Future<String> getCampusCardAlipayUrl(String username, double amount);
}