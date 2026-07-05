import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';

/// Unified campus data gateway.
///
/// Hides the difference between the Android direct-school runtime and the
/// optional self-hosted backend runtime. UI code should depend on this facade
/// instead of dealing with Dio, OkHttp-compatible flows, cookies, tickets, or
/// HTML parsing details directly.
abstract class CampusGateway {
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

  Future<GradeDetail> getGradeDetail(
    String username,
    String password, {
    required Grade grade,
    bool forceRefresh = false,
  });

  Future<StudyProgressData> getStudyProgress(
    String username,
    String password, {
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

  Future<String> rechargeElec(
    String username,
    double amount, {
    String? password,
    Map<String, String>? dormParams,
  });

  Future<String> getPayCodeToken(String username, {String? password});

  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    String? password,
  });
}
