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
              validateStatus: (status) => status != null && status < 600,
            ));

  final Dio _dio;

  Future<String> createSession(String username) async {
    final res = await _dio.post(
      '/api/auth/createSession',
      queryParameters: {'username': username},
    );
    _checkCode(res.data, statusCode: res.statusCode);
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
    _checkCode(res.data, statusCode: res.statusCode);
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
    _checkCode(res.data, statusCode: res.statusCode);
    final data = res.data['data'] as Map<String, dynamic>;
    final summary = Map<String, String>.from(
      (data['summary'] as Map?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
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
    _checkCode(res.data, statusCode: res.statusCode);
    return (res.data['data'] as List)
        .map((e) => Exam.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> getElecBalance(
    String username,
    String password, {
    String? sessionId,
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async {
    dev.log(
      '[ApiService] getElecBalance username=$username passwordLen=${password.length} forceRefresh=$forceRefresh',
      name: 'ApiService',
    );
    final res = await _dio.get('/api/elec/balance', queryParameters: {
      'username': username,
      'password': password,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      'forceRefresh': forceRefresh,
      if (dormParams != null) ...dormParams,
    });
    dev.log(
      '[ApiService] getElecBalance response code=${res.data['code']} msg=${res.data['msg']}',
      name: 'ApiService',
    );
    _checkCode(res.data, statusCode: res.statusCode);
    return res.data['data'] as String;
  }

  Future<String> getCampusCardBalance(
    String username,
    String password, {
    String? sessionId,
    bool forceRefresh = false,
  }) async {
    dev.log(
      '[ApiService] getCampusCardBalance username=$username passwordLen=${password.length} forceRefresh=$forceRefresh',
      name: 'ApiService',
    );
    final res = await _dio.get('/api/elec/cardBalance', queryParameters: {
      'username': username,
      'password': password,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      'forceRefresh': forceRefresh,
    });
    dev.log(
      '[ApiService] getCampusCardBalance response code=${res.data['code']} msg=${res.data['msg']}',
      name: 'ApiService',
    );
    _checkCode(res.data, statusCode: res.statusCode);
    return res.data['data'] as String;
  }

  Future<String> rechargeElec(
    String username,
    double amount, {
    String? sessionId,
    Map<String, String>? dormParams,
  }) async {
    final res = await _dio.get('/api/elec/recharge', queryParameters: {
      'username': username,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      'amount': amount,
      if (dormParams != null) ...dormParams,
    });
    _checkCode(res.data, statusCode: res.statusCode);
    return res.data['msg'] as String;
  }

  Future<String> getPayCodeToken(
    String username, {
    String? sessionId,
  }) async {
    final res = await _dio.get('/api/elec/paycode', queryParameters: {
      'username': username,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    });
    _checkCode(res.data, statusCode: res.statusCode);
    return res.data['data'] as String;
  }

  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    String? sessionId,
  }) async {
    final res = await _dio.get('/api/elec/chargeCard', queryParameters: {
      'username': username,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      'amount': amount,
    });
    _checkCode(res.data, statusCode: res.statusCode);
    return res.data['data'] as String;
  }

  Future<EnterLeaveApplyListResult> enterLeaveApplyList(
    String username, {
    required String sessionId,
    required String zoveToken,
    int currentPage = 1,
    int pageSize = 10,
  }) async {
    final res = await _dio.post(
      '/api/auth/enterLeaveApplyList',
      data: {
        'username': username,
        'sessionId': sessionId,
        'zoveToken': zoveToken,
        'currentPage': '$currentPage',
        'pageSize': '$pageSize',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 500,
      ),
    );

    final raw = _toMapStringDynamic(res.data);
    final code = _toInt(raw['code']) ?? (res.statusCode == 401 ? 401 : -1);

    return EnterLeaveApplyListResult(
      code: code,
      entered: _toBool(_readField(raw, 'entered')),
      msg: _readField(raw, 'msg')?.toString() ?? raw['msg']?.toString() ?? '',
      leavePageBody: _readField(raw, 'leavePageBody'),
      leaveConfigBody: _readField(raw, 'leaveConfigBody'),
      personalStatisticsBody: _readField(raw, 'personalStatisticsBody'),
      mobileIndexBody: _readField(raw, 'mobileIndexBody'),
    );
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
    _checkCode(res.data, statusCode: res.statusCode);
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
    _checkCode(res.data, statusCode: res.statusCode);
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
    _checkCode(res.data, statusCode: res.statusCode);
  }

  dynamic _readField(Map<String, dynamic> raw, String key) {
    if (raw.containsKey(key)) return raw[key];
    final data = raw['data'];
    if (data is Map<String, dynamic>) return data[key];
    if (data is Map) return data[key];
    return null;
  }

  Map<String, dynamic> _toMapStringDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
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

  void _checkCode(dynamic data, {int? statusCode}) {
    final raw = _toMapStringDynamic(data);
    final code = _toInt(raw['code']) ?? statusCode ?? -1;
    if (code == 449) {
      throw CaptchaRequiredException();
    }
    if (code == 200) return;
    if (raw.isNotEmpty) {
      throw ApiException(code, data['msg'] as String? ?? '未知错误');
    }
    throw ApiException(code, 'HTTP $code');
  }
}

class CaptchaRequiredException implements Exception {
  @override
  String toString() => '需要验证码';
}

class EnterLeaveApplyListResult {
  const EnterLeaveApplyListResult({
    required this.code,
    required this.entered,
    required this.msg,
    required this.leavePageBody,
    required this.leaveConfigBody,
    required this.personalStatisticsBody,
    required this.mobileIndexBody,
  });

  final int code;
  final bool entered;
  final String msg;
  final dynamic leavePageBody;
  final dynamic leaveConfigBody;
  final dynamic personalStatisticsBody;
  final dynamic mobileIndexBody;

  bool get success => code == 200 && entered;

  bool get tokenExpired => code == 401;
}

class ApiException implements Exception {
  final int code;
  final String message;
  ApiException(this.code, this.message);

  @override
  String toString() => message;
}
