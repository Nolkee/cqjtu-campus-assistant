import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:data/data.dart';

class MockCampusBackend implements CampusBackend {
  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    return (courses: <Course>[], remark: 'Mock data');
  }

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) async {
    return (summary: {'GPA': '0.0', 'Avg': '0'}, grades: <Grade>[]);
  }

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    return <Exam>[];
  }

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async =>
      '0.0';

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async =>
      '0.00';

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    Map<String, String>? dormParams,
  }) async =>
      'Mock: recharge disabled';

  @override
  Future<String> getPayCodeToken(String username) async => 'mock_token';

  @override
  Future<String> getCampusCardAlipayUrl(String username, double amount) async =>
      'https://example.com/mock';
}
