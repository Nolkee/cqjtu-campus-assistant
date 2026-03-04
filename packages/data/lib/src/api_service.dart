import 'package:dio/dio.dart';
import 'package:core/models/course.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/exam.dart';
import 'dart:developer' as dev;

class ApiService {
  ApiService({
    required String baseUrl,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;

  // ── 课程表 ──────────────────────────────────────────────
  Future<({List<Course> courses, String remark})> getSchedule(
      String username, String password,
      {String? semester, bool forceRefresh = false}) async {
    final res = await _dio.get('/api/getSchedule', queryParameters: {
      'username': username,
      'password': password,
      if (semester != null && semester.isNotEmpty) 'semester': semester,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    final data = res.data['data'];
    final courses = (data as List)
        .whereType<Map<String, dynamic>>()
        .map((e) => Course.fromJson(e))
        .toList();
    final remark = res.data['scheduleRemark'] as String? ?? '';
    return (courses: courses, remark: remark);
  }

  // ── 成绩 ────────────────────────────────────────────────
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
      String username, String password,
      {String semester = '', bool forceRefresh = false}) async {
    final res = await _dio.get('/api/getGrades', queryParameters: {
      'username': username,
      'password': password,
      'semester': semester,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    final data = res.data['data'] as Map<String, dynamic>;
    final summary = Map<String, String>.from(
        (data['summary'] as Map?)?.map((k, v) => MapEntry(k, v.toString())) ??
            {});
    final grades = (data['list'] as List? ?? [])
        .map((e) => Grade.fromJson(e as Map<String, dynamic>))
        .toList();
    return (summary: summary, grades: grades);
  }

  // ── 考试安排 ─────────────────────────────────────────────
  Future<List<Exam>> getExams(String username, String password,
      {String? semester, bool forceRefresh = false}) async {
    final res = await _dio.get('/api/getExams', queryParameters: {
      'username': username,
      'password': password,
      if (semester != null) 'semester': semester,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    return (res.data['data'] as List)
        .map((e) => Exam.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── 电费余额 ─────────────────────────────────────────────
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async {
    final res = await _dio.get('/api/elec/balance', queryParameters: {
      'username': username,
      'password': password,
      'forceRefresh': forceRefresh,
      if (dormParams != null) ...dormParams,
    });
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  // ── 校园卡余额 ───────────────────────────────────────────
  Future<String> getCampusCardBalance(String username, String password,
      {bool forceRefresh = false}) async {
    final res = await _dio.get('/api/elec/cardBalance', queryParameters: {
      'username': username,
      'password': password,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  // ── 电费充值（校园卡扣款）────────────────────────────────
  Future<String> rechargeElec(String username, double amount,
      {Map<String, String>? dormParams}) async {
    final res = await _dio.get('/api/elec/recharge', queryParameters: {
      'username': username,
      'amount': amount,
      // 如果有寝室参数，就拼接到请求参数里
      if (dormParams != null) ...dormParams,
    });
    _checkCode(res.data);
    return res.data['msg'] as String;
  }

  // ── 消费二维码 Token ─────────────────────────────────────
  Future<String> getPayCodeToken(String username) async {
    final res = await _dio
        .get('/api/elec/paycode', queryParameters: {'username': username});
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  // ── 校园卡支付宝充值链接 ──────────────────────────────────
  Future<String> getCampusCardAlipayUrl(String username, double amount) async {
    final res = await _dio.get('/api/elec/chargeCard',
        queryParameters: {'username': username, 'amount': amount});
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  // ── SSO Ticket 登录（WebView 拦截后调用）────────────────────
  /// 将 WebView 拦截到的 SSO ticket 发给后端，后端自行完成握手。
  Future<void> loginWithTicket(String username, String ticket) async {
    dev.log('发送 SSO ticket，用户：$username', name: 'ApiService');
    final res = await _dio.post(
      '/api/auth/loginWithTicket',
      queryParameters: {'username': username, 'ticket': ticket},
    );
    _checkCode(res.data);
  }

  // ── JSESSIONID 直接注入（策略二兜底）───────────────────────
  Future<void> injectJsessionid(String username, String jsessionid) async {
    dev.log('注入 JSESSIONID，用户：$username', name: 'ApiService');
    final res = await _dio.post(
      '/api/auth/injectJsessionid',
      queryParameters: {'username': username, 'jsessionid': jsessionid},
    );
    _checkCode(res.data);
  }

  Future<void> injectCookies(
      String username, String domain, String cookies) async {
    final res = await _dio.post('/api/auth/injectCookies', queryParameters: {
      'username': username,
      'domain': domain,
      'cookies': cookies,
    });
    _checkCode(res.data);
  }

  // ── 内部工具 ─────────────────────────────────────────────

  void _checkCode(dynamic data) {
    final code = data['code'] as int;
    if (code == 449) {
      // 需要滑动验证码，由 login_page 捕获后弹出 WebView
      throw CaptchaRequiredException();
    }
    if (code != 200) {
      throw ApiException(code, data['msg'] as String? ?? '未知错误');
    }
  }
}

/// 后端返回 449：需要用户手动完成滑动验证码。
class CaptchaRequiredException implements Exception {
  @override
  String toString() => '需要验证码';
}

class ApiException implements Exception {
  final int code;
  final String message;
  ApiException(this.code, this.message);

  @override
  String toString() => message;
}
