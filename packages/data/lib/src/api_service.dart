import 'dart:developer' as dev;

import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:dio/dio.dart';

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

  Future<String> createSession(String username) async {
    final res = await _dio.post(
      '/api/auth/createSession',
      queryParameters: {'username': username},
    );
    _checkCode(res.data);
    final sessionId = _readSessionId(res.data);
    if (sessionId == null || sessionId.isEmpty) {
      throw ApiException(res.data['code'] as int? ?? -1, '创建会话失败');
    }
    return sessionId;
  }

  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    required String sessionId,
    String? semester,
    bool forceRefresh = false,
  }) async {
    final res = await _dio.get('/api/getSchedule', queryParameters: {
      'username': username,
      'password': password,
      'sessionId': sessionId,
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

  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    required String sessionId,
    String semester = '',
    bool forceRefresh = false,
  }) async {
    final res = await _dio.get('/api/getGrades', queryParameters: {
      'username': username,
      'password': password,
      'sessionId': sessionId,
      'semester': semester,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    final data = res.data['data'] as Map<String, dynamic>;
    final summary = Map<String, String>.from(
      (data['summary'] as Map?)?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
    );
    final grades = (data['list'] as List? ?? [])
        .map((e) => Grade.fromJson(e as Map<String, dynamic>))
        .toList();
    return (summary: summary, grades: grades);
  }

  Future<List<Exam>> getExams(
    String username,
    String password, {
    required String sessionId,
    String? semester,
    bool forceRefresh = false,
  }) async {
    final res = await _dio.get('/api/getExams', queryParameters: {
      'username': username,
      'password': password,
      'sessionId': sessionId,
      if (semester != null) 'semester': semester,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    return (res.data['data'] as List)
        .map((e) => Exam.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> getElecBalance(
    String username,
    String password, {
    required String sessionId,
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async {
    final res = await _dio.get('/api/elec/balance', queryParameters: {
      'username': username,
      'password': password,
      'sessionId': sessionId,
      'forceRefresh': forceRefresh,
      if (dormParams != null) ...dormParams,
    });
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  Future<String> getCampusCardBalance(
    String username,
    String password, {
    required String sessionId,
    bool forceRefresh = false,
  }) async {
    final res = await _dio.get('/api/elec/cardBalance', queryParameters: {
      'username': username,
      'password': password,
      'sessionId': sessionId,
      'forceRefresh': forceRefresh,
    });
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  Future<String> rechargeElec(
    String username,
    double amount, {
    required String sessionId,
    Map<String, String>? dormParams,
  }) async {
    final res = await _dio.get('/api/elec/recharge', queryParameters: {
      'username': username,
      'sessionId': sessionId,
      'amount': amount,
      if (dormParams != null) ...dormParams,
    });
    _checkCode(res.data);
    return res.data['msg'] as String;
  }

  Future<String> getPayCodeToken(
    String username, {
    required String sessionId,
  }) async {
    final res = await _dio.get('/api/elec/paycode', queryParameters: {
      'username': username,
      'sessionId': sessionId,
    });
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    required String sessionId,
  }) async {
    final res = await _dio.get('/api/elec/chargeCard', queryParameters: {
      'username': username,
      'sessionId': sessionId,
      'amount': amount,
    });
    _checkCode(res.data);
    return res.data['data'] as String;
  }

  Future<void> loginWithTicket(
    String username,
    String ticket, {
    required String sessionId,
  }) async {
    dev.log('发送 SSO ticket，用户：$username', name: 'ApiService');
    final res = await _dio.post(
      '/api/auth/loginWithTicket',
      queryParameters: {
        'username': username,
        'ticket': ticket,
        'sessionId': sessionId,
      },
    );
    _checkCode(res.data);
  }

  Future<void> injectJsessionid(
    String username,
    String jsessionid, {
    required String sessionId,
  }) async {
    dev.log('注入 JSESSIONID，用户：$username', name: 'ApiService');
    final res = await _dio.post(
      '/api/auth/injectJsessionid',
      queryParameters: {
        'username': username,
        'jsessionid': jsessionid,
        'sessionId': sessionId,
      },
    );
    _checkCode(res.data);
  }

  Future<void> injectCookies(
    String username,
    String domain,
    String cookies, {
    required String sessionId,
  }) async {
    final res = await _dio.post('/api/auth/injectCookies', queryParameters: {
      'username': username,
      'sessionId': sessionId,
      'domain': domain,
      'cookies': cookies,
    });
    _checkCode(res.data);
  }

  String? _readSessionId(dynamic data) {
    final direct = data['sessionId'];
    if (direct is String && direct.isNotEmpty) return direct;

    final inner = data['data'];
    if (inner is Map<String, dynamic>) {
      final nested = inner['sessionId'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
    if (inner is Map) {
      final nested = inner['sessionId'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
    return null;
  }

  void _checkCode(dynamic data) {
    final code = data['code'] as int;
    if (code == 449) {
      throw CaptchaRequiredException();
    }
    if (code != 200) {
      throw ApiException(code, data['msg'] as String? ?? '未知错误');
    }
  }
}

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
