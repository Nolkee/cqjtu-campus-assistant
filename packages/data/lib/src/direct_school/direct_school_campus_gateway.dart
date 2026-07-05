import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

import '../campus_failure.dart';
import '../campus_gateway.dart';
import '../self_hosted/self_hosted_session_manager.dart';

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

String _currentSemester([DateTime? now]) {
  final date = now ?? DateTime.now();
  final year = date.year;
  final month = date.month;
  if (month >= 8) return '$year-${year + 1}-1';
  if (month == 1) return '${year - 1}-$year-1';
  return '${year - 1}-$year-2';
}

List<String> _recentSemesters({DateTime? now, int count = 8}) {
  final current = _currentSemester(now).split('-');
  if (current.length != 3) return const [];

  final parsedStartYear = int.tryParse(current[0]);
  final parsedEndYear = int.tryParse(current[1]);
  final parsedTerm = int.tryParse(current[2]);
  if (parsedStartYear == null || parsedEndYear == null || parsedTerm == null) {
    return const [];
  }
  var startYear = parsedStartYear;
  var endYear = parsedEndYear;
  var term = parsedTerm;

  final semesters = <String>[];
  for (var i = 0; i < count; i++) {
    semesters.add('$startYear-$endYear-$term');
    if (term == 2) {
      term = 1;
    } else {
      term = 2;
      startYear -= 1;
      endYear -= 1;
    }
  }
  return semesters;
}

// ---------------------------------------------------------------------------
// School system URL configuration
// ---------------------------------------------------------------------------

/// Configurable base URLs for the school's backend systems.
///
/// Defaults point to CQJTU (Chongqing Jiaotong University) systems.
/// Override via constructor to target a different school.
class SchoolSystemConfig {
  final String casLoginUrl;
  final String scheduleUrl;
  final String gradesUrl;
  final String gradeDetailUrl;
  final String studyProgressUrl;
  final String studentExecutionPlanUrl;
  final String examsUrl;
  final String ecardPayeleUrl;
  final String ecardEleresultUrl;
  final String ecardElepaybillUrl;
  final String ecardPayconfirmUrl;
  final String ecardIndexUrl;
  final String ecardV5qrcodeUrl;
  final String ecardDodikechargeUrl;

  const SchoolSystemConfig({
    this.casLoginUrl =
        'https://ids.cqjtu.edu.cn/authserver/login?service=http%3A%2F%2Fjwgln.cqjtu.edu.cn%2Fjsxsd%2Fsso.jsp',
    this.scheduleUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/xskb/xskb_list.do',
    this.gradesUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/kscj/cjcx_list',
    this.gradeDetailUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/kscj/pscj_list.do',
    this.studyProgressUrl =
        'https://jwgln.cqjtu.edu.cn/jsxsd/xxwcqk/xxwcqk_idxOntx.do',
    this.studentExecutionPlanUrl =
        'https://jwgln.cqjtu.edu.cn/jsxsd/xxwcqk/xxwcqkOnkctx.do',
    this.examsUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/xsks/xsksap_list',
    this.ecardPayeleUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/payele',
    this.ecardEleresultUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/eleresult',
    this.ecardElepaybillUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/elepaybill',
    this.ecardPayconfirmUrl =
        'https://ecard.cqjtu.edu.cn/epay/h5/payconfirm.json',
    this.ecardIndexUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/index',
    this.ecardV5qrcodeUrl =
        'https://ecard.cqjtu.edu.cn/epay/h5/v5qrcode?codetype=O5',
    this.ecardDodikechargeUrl =
        'https://ecard.cqjtu.edu.cn/epay/h5/dodikecharge',
  });
}

// ---------------------------------------------------------------------------
// Manual Cookie Jar — per-domain cookie isolation
// ---------------------------------------------------------------------------

/// A cookie entry stored in [ManualCookieJar].
class _CookieEntry {
  final Cookie cookie;
  final String domain;
  final String path;
  final bool hostOnly;

  _CookieEntry(this.cookie, this.domain, this.path, this.hostOnly);
}

/// Per-domain cookie jar that properly isolates cookies by host.
///
/// [HttpClient]'s built-in jar leaks cookies across cross-domain redirects
/// during CAS login. This jar ensures each domain only gets its own cookies.
class ManualCookieJar {
  final Map<String, _CookieEntry> _store = {};

  void saveFromResponse(Uri uri, List<Cookie> cookies) {
    for (final cookie in cookies) {
      final rawDomain = cookie.domain;
      final hostOnly = rawDomain == null || rawDomain.isEmpty;
      final domain = (hostOnly ? uri.host : rawDomain)
          .replaceFirst(RegExp(r'^\.'), '')
          .toLowerCase();
      final path =
          (cookie.path == null || cookie.path!.isEmpty) ? '/' : cookie.path!;
      final key = '$domain|$path|${cookie.name}';

      if (cookie.expires != null && cookie.expires!.isBefore(DateTime.now())) {
        _store.remove(key);
      } else {
        _store[key] = _CookieEntry(cookie, domain, path, hostOnly);
      }
    }
  }

  List<Cookie> loadForRequest(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final isHttps = uri.scheme == 'https';
    final now = DateTime.now();

    return _store.values
        .where((entry) {
          final cookie = entry.cookie;
          if (cookie.secure && !isHttps) return false;
          if (cookie.expires != null && cookie.expires!.isBefore(now))
            return false;

          final domainMatches = entry.hostOnly
              ? host == entry.domain
              : host == entry.domain || host.endsWith('.${entry.domain}');
          if (!domainMatches) return false;
          if (!path.startsWith(entry.path)) return false;

          return true;
        })
        .map((entry) => entry.cookie)
        .toList();
  }

  void saveFromCookieHeader(Uri uri, String cookieHeader) {
    final cookies = <Cookie>[];
    for (final part in cookieHeader.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;

      final name = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (name.isEmpty || _isCookieAttribute(name)) continue;

      cookies.add(Cookie(name, value)..path = '/');
    }
    saveFromResponse(uri, cookies);
  }

  String cookieHeaderFor(Uri uri) {
    return loadForRequest(uri)
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  bool hasCookieForHost(String host, String name) {
    host = host.toLowerCase();
    return _store.values.any((entry) =>
        entry.cookie.name == name &&
        (host == entry.domain || host.endsWith('.${entry.domain}')));
  }

  void clear() => _store.clear();

  bool _isCookieAttribute(String name) {
    switch (name.toLowerCase()) {
      case 'path':
      case 'domain':
      case 'expires':
      case 'max-age':
      case 'samesite':
      case 'secure':
      case 'httponly':
        return true;
      default:
        return false;
    }
  }
}

// ---------------------------------------------------------------------------
// HTTP client wrapper with manual cookie + redirect handling
// ---------------------------------------------------------------------------

/// Wraps [HttpClient] with [ManualCookieJar] and manual redirect following.
///
/// CAS login involves cross-domain redirects (ids → jwgln). The built-in
/// auto-follow strips sensitive headers (Cookie) on cross-domain hops, so
/// we disable it and manage cookies + redirects ourselves.
class _SchoolHttpClient {
  _SchoolHttpClient({Duration? readTimeout})
      : _readTimeout = readTimeout ?? const Duration(seconds: 20);

  final Duration _readTimeout;
  final HttpClient _client = HttpClient();
  final ManualCookieJar _jar = ManualCookieJar();

  static const String _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  static String _redactUri(Uri uri) {
    const sensitiveKeys = {
      'password',
      'ticket',
      'token',
      'sessionid',
      'jsessionid',
      'cookies',
      'h-zove-token',
      'username',
      'account',
      'user',
      'xh',
    };
    if (!uri.hasQuery) return uri.toString();

    final redacted = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      redacted[key] =
          sensitiveKeys.contains(key.toLowerCase()) ? '<redacted>' : value;
    });
    return uri.replace(queryParameters: redacted).toString();
  }

  static String _redactLocation(Uri currentUri, String? location) {
    if (location == null || location.isEmpty) return '';
    try {
      return _redactUri(currentUri.resolve(location));
    } catch (_) {
      return '<invalid-location>';
    }
  }

  /// Send a request with manual cookie attachment. Does NOT follow redirects.
  Future<HttpClientResponse> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final req = await _client.openUrl(method, uri);
    req.followRedirects = false;

    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    req.headers.set(HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');

    headers?.forEach(req.headers.set);

    // Attach cookies for this domain only
    req.cookies.addAll(_jar.loadForRequest(uri));

    if (body != null) {
      req.add(body);
    }

    final res = await req.close().timeout(_readTimeout);
    _jar.saveFromResponse(uri, res.cookies);
    return res;
  }

  /// GET with manual redirect following.
  Future<_HttpResponse> get(String url,
      {Map<String, String>? queryParams, int maxRedirects = 10}) async {
    final uri = _buildUri(url, queryParams);
    final res = await _followRedirects('GET', uri, maxRedirects: maxRedirects);
    final body = await res.transform(utf8.decoder).join();
    return _HttpResponse(statusCode: res.statusCode, body: body);
  }

  /// POST with manual redirect following.
  Future<_HttpResponse> post(String url,
      {Map<String, String>? formBody,
      Map<String, String>? queryParams,
      Map<String, String>? extraHeaders,
      int maxRedirects = 10}) async {
    final uri = _buildUri(url, queryParams);
    final encoded = formBody?.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final bodyBytes = encoded != null ? utf8.encode(encoded) : null;

    final origin = '${uri.scheme}://${uri.host}${_portSegment(uri)}';
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
      'Origin': origin,
      HttpHeaders.refererHeader: uri.toString(),
      ...?extraHeaders,
    };

    final res = await _followRedirects('POST', uri,
        headers: headers, body: bodyBytes, maxRedirects: maxRedirects);
    final body = await res.transform(utf8.decoder).join();
    return _HttpResponse(statusCode: res.statusCode, body: body);
  }

  /// Follow redirects manually, switching POST → GET on 301/302/303.
  Future<HttpClientResponse> _followRedirects(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
    int maxRedirects = 10,
  }) async {
    var currentMethod = method;
    var currentUri = uri;
    var currentBody = body;
    var currentHeaders = headers;

    for (var i = 0; i < maxRedirects; i++) {
      final res = await _send(currentMethod, currentUri,
          headers: currentHeaders, body: currentBody);

      final status = res.statusCode;
      final location = res.headers.value(HttpHeaders.locationHeader);
      final isRedirect = status == 301 ||
          status == 302 ||
          status == 303 ||
          status == 307 ||
          status == 308;

      dev.log(
        '[HTTP] $currentMethod ${_redactUri(currentUri)} -> $status '
        'location=${_redactLocation(currentUri, location)} '
        'cookieCount=${_jar.loadForRequest(currentUri).length}',
        name: 'DirectSchool',
      );

      if (!isRedirect || location == null) {
        return res;
      }

      await res.drain();
      final nextUri = currentUri.resolve(location);

      // 301/302/303 → switch to GET and drop body
      if (status == 301 || status == 302 || status == 303) {
        currentMethod = 'GET';
        currentBody = null;
        currentHeaders = null;
      }

      currentUri = nextUri;
    }

    throw Exception('Too many redirects');
  }

  void clearCookies() => _jar.clear();

  void importCookieHeader(String url, String cookieHeader) {
    final trimmed = cookieHeader.trim();
    if (trimmed.isEmpty) return;
    _jar.saveFromCookieHeader(Uri.parse(url), trimmed);
  }

  String exportCookieHeader(String url) {
    return _jar.cookieHeaderFor(Uri.parse(url));
  }

  /// Exposed for login success checking.
  ManualCookieJar get cookieJar => _jar;

  Uri _buildUri(String url, Map<String, String>? queryParams) {
    final uri = Uri.parse(url);
    if (queryParams == null || queryParams.isEmpty) return uri;
    final params = Map<String, String>.from(uri.queryParameters);
    params.addAll(queryParams);
    return uri.replace(queryParameters: params);
  }

  String _portSegment(Uri uri) {
    if (!uri.hasPort) return '';
    final isDefaultHttp = uri.scheme == 'http' && uri.port == 80;
    final isDefaultHttps = uri.scheme == 'https' && uri.port == 443;
    if (isDefaultHttp || isDefaultHttps) return '';
    return ':${uri.port}';
  }
}

class _HttpResponse {
  final int statusCode;
  final String body;

  const _HttpResponse({
    required this.statusCode,
    required this.body,
  });
}

// ---------------------------------------------------------------------------
// AES/CBC/PKCS7 encryption for CAS password
// ---------------------------------------------------------------------------

/// Mirrors the Java PasswordEncryptor used by the Spring Boot backend.
///
/// The CAS login page provides a `pwdEncryptSalt` (16-char AES key).
/// The password is prefixed with 64 random characters, then encrypted
/// with AES/CBC/PKCS7 (Java's PKCS5Padding is equivalent to PKCS7).
class _CasPasswordEncryptor {
  static const String _chars =
      'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  static final Random _rng = Random.secure();

  /// Encrypt the plaintext password using the salt as AES key.
  static String encrypt(String password, String salt) {
    // 1. Prefix with 64 random chars
    final prefix =
        List.generate(64, (_) => _chars[_rng.nextInt(_chars.length)]).join();
    final plaintext = prefix + password;

    // 2. Generate random 16-char IV (same charset as Java's PasswordEncryptor)
    final ivString =
        List.generate(16, (_) => _chars[_rng.nextInt(_chars.length)]).join();
    final iv = utf8.encode(ivString);

    // 3. Convert salt to key bytes (must be exactly 16 bytes)
    final key = utf8.encode(salt);
    if (key.length != 16) {
      throw ArgumentError(
          'Salt must be exactly 16 characters, got ${key.length}');
    }

    // 4. Encrypt with AES/CBC/PKCS7 using PaddedBlockCipherImpl
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(
          KeyParameter(Uint8List.fromList(key)),
          Uint8List.fromList(iv),
        ),
        null,
      ),
    );

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(plainBytes);

    // 5. Return base64-encoded ciphertext
    return base64.encode(encrypted);
  }
}

// ---------------------------------------------------------------------------
// CAS authenticator
// ---------------------------------------------------------------------------

/// Handles the full CAS login flow against the school's IDP.
class _CasAuthenticator {
  _CasAuthenticator(this._httpClient, this._config);

  final _SchoolHttpClient _httpClient;
  final SchoolSystemConfig _config;

  /// Whether a password has been cached for re-login.
  String? _cachedPassword;

  /// Cache the password for operations that don't receive it (recharge, etc.).
  void cachePassword(String password) {
    _cachedPassword = password;
  }

  /// Perform full CAS login. Returns the username on success.
  Future<String> login(String username, String password) async {
    dev.log('[_CasAuth] Starting CAS login for ${_redactIdentifier(username)}',
        name: 'DirectSchool');

    // Step 1: GET the CAS login page
    final loginPage = await _httpClient.get(_config.casLoginUrl);
    final html = loginPage.body;

    // Step 2: Check for CAPTCHA requirement (only if server explicitly says so)
    if (_containsCaptcha(html)) {
      throw const CaptchaRequiredFailure();
    }

    // Step 3: Extract execution token and encryption salt
    final execution = _extractInputValue(html, 'execution');
    if (execution == null || execution.isEmpty) {
      dev.log('[_CasAuth] No execution token found in login page',
          name: 'DirectSchool');
      throw const SchoolSystemChangedFailure('登录页面缺少 execution 参数');
    }

    final salt = _extractPwdEncryptSalt(html);
    if (salt == null || salt.isEmpty) {
      dev.log('[_CasAuth] No pwdEncryptSalt found in login page',
          name: 'DirectSchool');
      throw const SchoolSystemChangedFailure('登录页面缺少加密盐值');
    }

    // Step 4: Encrypt password
    final encryptedPwd = _CasPasswordEncryptor.encrypt(password, salt);

    // Step 5: POST login form
    final loginResult = await _httpClient.post(
      _config.casLoginUrl,
      formBody: {
        'username': username,
        'password': encryptedPwd,
        'execution': execution,
        '_eventId': 'submit',
        'cllt': 'userNameLogin',
        'dllt': 'generalLogin',
        'rmShown': '1',
        'lt': '',
      },
    );

    final resultBody = loginResult.body;

    // Step 6: Evaluate result — check cookie jar for jwgln session
    if (_isLoginError(resultBody)) {
      throw const AuthInvalidFailure();
    }

    // Check if we got jwgln cookies (real success signal)
    if (_httpClient._jar.hasCookieForHost('jwgln.cqjtu.edu.cn', 'JSESSIONID') ||
        _httpClient._jar.hasCookieForHost('jwgln.cqjtu.edu.cn', 'SESSION')) {
      _cachedPassword = password;
      dev.log(
        '[_CasAuth] Login successful for ${_redactIdentifier(username)} '
        '(jwgln cookie found)',
        name: 'DirectSchool',
      );
      return username;
    }

    // Still on CAS page
    if (resultBody.contains('authserver/login')) {
      if (_containsCaptcha(resultBody)) {
        throw const CaptchaRequiredFailure();
      }
      throw const NetworkFailure('登录失败，请检查网络连接');
    }

    // Fallback: check body for academic system content
    if (resultBody.contains('timetable') ||
        resultBody.contains('kbcontent') ||
        resultBody.contains('xsMain') ||
        resultBody.contains('framework')) {
      _cachedPassword = password;
      dev.log(
        '[_CasAuth] Login successful for ${_redactIdentifier(username)} '
        '(body match)',
        name: 'DirectSchool',
      );
      return username;
    }

    throw const NetworkFailure('登录失败，未能获取教务系统会话');
  }

  /// Login using a CAS ticket obtained from WebView SSO.
  /// The ticket is submitted to the CAS server's login endpoint
  /// with the service parameter to validate and create a session.
  Future<String> loginWithTicket(String username, String ticket) async {
    dev.log(
        '[_CasAuth] Logging in with ticket for ${_redactIdentifier(username)}',
        name: 'DirectSchool');

    final result = await _httpClient.get(
      _config.casLoginUrl,
      queryParams: {'ticket': ticket},
    );
    final resultBody = result.body;

    if (_httpClient._jar.hasCookieForHost('jwgln.cqjtu.edu.cn', 'JSESSIONID') ||
        _httpClient._jar.hasCookieForHost('jwgln.cqjtu.edu.cn', 'SESSION') ||
        _isAcademicSystemBody(resultBody)) {
      _cachedPassword = null; // No password cached for ticket login.
      dev.log(
        '[_CasAuth] Ticket login successful for ${_redactIdentifier(username)}',
        name: 'DirectSchool',
      );
      return username;
    }

    if (resultBody.contains('authserver/login') ||
        resultBody.contains('casLoginForm')) {
      if (_containsCaptcha(resultBody)) {
        throw const CaptchaRequiredFailure();
      }
      if (_isLoginError(resultBody)) {
        throw const AuthInvalidFailure();
      }
      throw const AuthInvalidFailure('ticket 无效或已过期');
    }

    throw const NetworkFailure('ticket 登录失败，未能获取教务系统会话');
  }

  /// Re-login using cached password. Returns true on success.
  Future<bool> relogin(String username) async {
    if (_cachedPassword == null) return false;
    try {
      await login(username, _cachedPassword!);
      return true;
    } catch (e) {
      dev.log('[_CasAuth] Re-login failed: $e', name: 'DirectSchool');
      return false;
    }
  }

  /// Check if the current session is still valid by probing the schedule page.
  Future<bool> isSessionValid() async {
    try {
      final resp = await _httpClient.post(
        _config.scheduleUrl,
        formBody: {'xnxq01id': ''},
      );
      final body = resp.body;
      // If we see the CAS login page, session is expired
      if (body.contains('authserver/login')) return false;
      if (body.contains('jsxsd') || body.contains('timetable')) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Ensure a valid session exists, performing login if needed.
  Future<void> ensureSession(String username, String password) async {
    if (await isSessionValid()) {
      _cachedPassword = password;
      return;
    }
    await login(username, password);
  }

  /// E-card SSO authorization: probe the e-card payele endpoint.
  /// Returns true if authorized.
  Future<bool> authEcard() async {
    try {
      final resp = await _httpClient.get(_config.ecardPayeleUrl);
      // If we land on the CAS IDP host, session is expired
      if (resp.body.contains('authserver/login') ||
          resp.body.contains('ids.cqjtu')) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// E-card authorization with retry and fallback re-login.
  Future<bool> ensureEcardAuth(String username) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      if (await authEcard()) return true;
      if (attempt < 2) {
        await Future.delayed(Duration(milliseconds: 500 + attempt * 500));
      }
    }
    // Fallback: re-login to CAS and retry
    if (_cachedPassword != null) {
      try {
        await login(username, _cachedPassword!);
      } catch (_) {
        return false;
      }
      // Retry once more after re-login
      return await authEcard();
    }
    return false;
  }

  // ---- HTML extraction helpers ----

  /// Extract the value of a hidden input by name or id.
  String? _extractInputValue(String html, String name) {
    // Search for: id="name" value="xxx" or name="name" value="xxx"
    final idStr = 'id="$name"';
    final nameStr = 'name="$name"';
    final idPos = html.indexOf(idStr);
    final namePos = html.indexOf(nameStr);
    final pos = (idPos >= 0 && (namePos < 0 || idPos < namePos))
        ? idPos
        : (namePos >= 0 ? namePos : -1);
    if (pos < 0) return null;

    // Find the value attribute after this position
    final valueStart = html.indexOf('value="', pos);
    if (valueStart < 0) return null;
    final valueEnd = html.indexOf('"', valueStart + 7);
    if (valueEnd < 0) return null;
    return html.substring(valueStart + 7, valueEnd);
  }

  /// Extract the pwdEncryptSalt from the login page.
  /// Can be in a hidden input or a JavaScript variable.
  String? _extractPwdEncryptSalt(String html) {
    // Pattern 1: Hidden input with id="pwdEncryptSalt"
    final inputPattern = RegExp(
        r"""<input[^>]*\s+id=["']pwdEncryptSalt["'][^>]*\s+value=["']([^"']+)["']""",
        caseSensitive: false);
    final inputMatch = inputPattern.firstMatch(html);
    if (inputMatch != null) return inputMatch.group(1);

    // Pattern 2: var pwdEncryptSalt = "xxxx";
    final varPattern = RegExp(r"""pwdEncryptSalt\s*=\s*["']([^"']{16})["']""",
        caseSensitive: false);
    final varMatch = varPattern.firstMatch(html);
    if (varMatch != null) return varMatch.group(1);

    return null;
  }

  /// Check if the login page requires a CAPTCHA by calling the check API.
  /// Returns true only if the server explicitly requires one.
  bool _containsCaptcha(String html) {
    // Don't rely on static HTML keywords - the page always contains
    // "captcha", "inputCodeTip" etc. as part of the template.
    // Instead, check for the actual captcha input element being visible.
    // The server sets needCaptcha dynamically.
    if (html.contains('needCaptcha') &&
        (html.contains('needCaptcha = "1"') ||
            html.contains("needCaptcha = '1'") ||
            html.contains('needCaptcha=1'))) {
      return true;
    }
    return false;
  }

  /// Check if the response indicates wrong credentials.
  bool _isLoginError(String html) {
    final lower = html.toLowerCase();
    return lower.contains('账号或密码错误') ||
        lower.contains('用户名或密码错误') ||
        lower.contains('password error');
  }

  bool _isAcademicSystemBody(String html) {
    return html.contains('jsxsd') ||
        html.contains('timetable') ||
        html.contains('kbcontent') ||
        html.contains('xsMain') ||
        html.contains('framework');
  }
}

// ---------------------------------------------------------------------------
// HTML parsers
// ---------------------------------------------------------------------------

/// Parses the timetable HTML from the 强智 educational administration system.
class _ScheduleParser {
  /// Parse the timetable HTML and return courses + remark.
  static ({List<Course> courses, String remark}) parse(String html) {
    final courses = <Course>[];
    final document = html_parser.parse(html);
    final remark = _parseRemark(document);

    dev.log(
      '[_ScheduleParser] HTML len=${html.length} '
      'timetable=${html.contains('timetable')} '
      'kbcontent=${html.contains('kbcontent')} '
      'authserver=${html.contains('authserver/login')}',
      name: 'DirectSchool',
    );

    final table = document.getElementById('timetable');
    if (table == null) {
      dev.log('[_ScheduleParser] No #timetable found', name: 'DirectSchool');
      return (courses: courses, remark: remark);
    }

    final rows = table.querySelectorAll('tr');
    for (int r = 1; r < rows.length; r++) {
      final cells = rows[r].querySelectorAll('td');

      for (int c = 0; c < cells.length; c++) {
        final kbContent = cells[c].querySelector('div.kbcontent');
        if (kbContent == null) continue;

        Course? currentCourse;
        for (final font in kbContent.querySelectorAll('font')) {
          final fontText = font.text.trim();
          if (fontText.isEmpty) continue;

          if (!font.attributes.containsKey('title') &&
              !font.attributes.containsKey('name')) {
            if (currentCourse != null && currentCourse.name.isNotEmpty) {
              courses.add(currentCourse);
            }
            currentCourse = Course(
              name: fontText,
              teacher: '',
              timeStr: '',
              classroom: '',
              dayOfWeek: c + 1,
              timeSlot: r,
              weekList: [],
            );
          } else {
            if (currentCourse == null) continue;

            final title = font.attributes['title'] ?? '';
            switch (title) {
              case '教师':
                currentCourse = currentCourse.copyWith(teacher: fontText);
                break;
              case '周次(节次)':
                currentCourse = currentCourse.copyWith(timeStr: fontText);
                // Parse week list and slots from timeStr
                final parsed = _parseTimeStr(fontText);
                currentCourse = currentCourse.copyWith(
                  weekList: parsed.weekList,
                  timeSlot: parsed.startSlot,
                  endTimeSlot: parsed.endSlot,
                );
                break;
              case '教室':
                currentCourse = currentCourse.copyWith(classroom: fontText);
                break;
            }
          }
        }

        // Finalize the last course in this cell
        if (currentCourse != null && currentCourse.name.isNotEmpty) {
          courses.add(currentCourse);
        }
      }
    }

    dev.log(
      '[_ScheduleParser] Parsed ${courses.length} courses, remark length=${remark.length}',
      name: 'DirectSchool',
    );
    return (courses: courses, remark: remark);
  }

  /// Parse the remark row from the timetable.
  static String _parseRemark(dom.Document document) {
    final table = document.getElementById('timetable');
    if (table == null) return '';

    for (final row in table.querySelectorAll('tr')) {
      final th = row.querySelector('th');
      if (th == null || !th.text.contains('备注')) continue;
      return row.querySelector('td')?.text.trim() ?? '';
    }

    return '';
  }

  /// Parse a time string like "5(周)[09-10节]" or "10-16(单周)[09-10节]".
  static _ParsedTimeStr _parseTimeStr(String timeStr) {
    if (timeStr.isEmpty) {
      return _ParsedTimeStr(weekList: [], startSlot: 1, endSlot: 1);
    }

    // Extract slot info: [09-10节] or [05节]
    var startSlot = 1;
    var endSlot = 1;

    final rangeMatch = RegExp(r'\[(\d+)-(\d+)节\]').firstMatch(timeStr);
    if (rangeMatch != null) {
      startSlot = int.tryParse(rangeMatch.group(1) ?? '') ?? 1;
      endSlot = int.tryParse(rangeMatch.group(2) ?? '') ?? startSlot;
      // Clamp to valid range
      startSlot = startSlot.clamp(1, 13);
      endSlot = endSlot.clamp(startSlot, 13);
    } else {
      final singleMatch = RegExp(r'\[(\d+)节\]').firstMatch(timeStr);
      if (singleMatch != null) {
        startSlot = int.tryParse(singleMatch.group(1) ?? '') ?? 1;
        startSlot = startSlot.clamp(1, 13);
        endSlot = startSlot;
      }
    }

    // Extract week info
    final weekList = <int>[];

    // Split on '(' to separate week portion from type portion
    final parenIndex = timeStr.indexOf('(');
    if (parenIndex < 0)
      return _ParsedTimeStr(
          weekList: weekList, startSlot: startSlot, endSlot: endSlot);

    final weekPart = timeStr.substring(0, parenIndex).trim();
    final typePart = timeStr.substring(parenIndex + 1);

    // Determine odd/even filter
    bool? oddOnly;
    bool? evenOnly;
    if (typePart.contains('单周')) oddOnly = true;
    if (typePart.contains('双周')) evenOnly = true;

    // Parse week segments (comma-separated)
    final segments = weekPart.split(',');
    for (final segment in segments) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;

      final rangeParts = trimmed.split('-');
      if (rangeParts.length == 2) {
        final start = int.tryParse(rangeParts[0].trim());
        final end = int.tryParse(rangeParts[1].trim());
        if (start != null && end != null && start <= end) {
          for (var w = start; w <= end; w++) {
            if (oddOnly == true && w % 2 == 0) continue;
            if (evenOnly == true && w % 2 != 0) continue;
            weekList.add(w);
          }
        }
      } else {
        final week = int.tryParse(trimmed);
        if (week != null) {
          if (oddOnly == true && week % 2 == 0) continue;
          if (evenOnly == true && week % 2 != 0) continue;
          weekList.add(week);
        }
      }
    }

    weekList.sort();
    return _ParsedTimeStr(
        weekList: weekList, startSlot: startSlot, endSlot: endSlot);
  }
}

class _ParsedTimeStr {
  final List<int> weekList;
  final int startSlot;
  final int endSlot;

  const _ParsedTimeStr({
    required this.weekList,
    required this.startSlot,
    required this.endSlot,
  });
}

// ---------------------------------------------------------------------------
// Grade parser
// ---------------------------------------------------------------------------

/// Parses the grade page HTML from the 强智 system.
class _GradeParser {
  static ({Map<String, String> summary, List<Grade> grades}) parse(
      String html) {
    final summary = _parseSummary(html);
    final grades = _parseGradeList(html);
    return (summary: summary, grades: grades);
  }

  /// Extract summary fields from page text via regex.
  static Map<String, String> _parseSummary(String html) {
    final document = html_parser.parse(html);
    final text = document.documentElement?.text ?? document.body?.text ?? '';

    return {
      'totalCourses': _extractMatch(text, r'所修门数[：:](\d+)'),
      'totalCredits': _extractMatch(text, r'所修总学分[：:]([\d.]+)'),
      'gpa': _extractMatch(text, r'平均学分绩点[：:]([\d.]+)'),
      'avgScore': _extractMatch(text, r'平均成绩[：:]([\d.]+)'),
      'classRank': _extractMatch(text, r'绩点班级排名[：:](\d+)'),
      'majorRank': _extractMatch(text, r'绩点专业排名[：:](\d+)'),
    };
  }

  /// Extract the grade list from <table id="dataList">.
  static List<Grade> _parseGradeList(String html) {
    final grades = <Grade>[];
    final document = html_parser.parse(html);
    final table = document.getElementById('dataList');

    if (table == null) return grades;

    final rows = table.querySelectorAll('tr');
    for (int i = 1; i < rows.length; i++) {
      final cellElements = rows[i].querySelectorAll('td');
      final cells = cellElements.map((cell) => cell.text.trim()).toList();
      if (cells.length < 14) continue;
      final detailParams = _parseDetailParams(
        cellElements.length > 4 ? cellElements[4] : null,
      );

      grades.add(Grade(
        semester: cells.length > 1 ? cells[1] : '',
        courseCode: cells.length > 2 ? cells[2] : '',
        courseName: cells.length > 3 ? cells[3] : '',
        score: cells.length > 4 ? cells[4] : '-',
        credits: cells.length > 6 ? cells[6] : '-',
        gradePoint: cells.length > 8 ? cells[8] : '-',
        courseAttribute: cells.length > 12 ? cells[12] : '',
        courseNature: cells.length > 13 ? cells[13] : '',
        studentId: detailParams?['xs0101id'] ?? '',
        teachingClassId: detailParams?['jx0404id'] ?? '',
        gradeRecordId: detailParams?['cj0708id'] ?? '',
      ));
    }

    return grades;
  }

  static Map<String, String>? _parseDetailParams(dom.Element? scoreCell) {
    if (scoreCell == null) return null;
    final href = scoreCell.querySelector('a[href]')?.attributes['href'];
    if (href == null || href.trim().isEmpty) return null;
    final raw = href.trim().replaceAll('&amp;', '&');

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.query.isNotEmpty) {
      return uri.queryParameters;
    }

    final match = RegExp(
      r"""pscj_list\.do\?([^'")\s]+)""",
      caseSensitive: false,
    ).firstMatch(raw);
    final query = match?.group(1);
    if (query == null || query.isEmpty) return null;
    return Uri.splitQueryString(query);
  }

  static GradeDetail parseDetail(String html) {
    final document = html_parser.parse(html);
    final table =
        document.getElementById('dataList') ?? document.querySelector('table');
    if (table == null) return const GradeDetail(items: [], totalScore: '');

    final rows = table.querySelectorAll('tr');
    if (rows.length < 2) return const GradeDetail(items: [], totalScore: '');

    final headers = rows.first
        .querySelectorAll('th,td')
        .map((cell) => cell.text.trim())
        .toList();
    final values =
        rows[1].querySelectorAll('td').map((cell) => cell.text.trim()).toList();
    if (headers.isEmpty || values.isEmpty) {
      return const GradeDetail(items: [], totalScore: '');
    }

    final valueByHeader = <String, String>{};
    for (var i = 0; i < headers.length && i < values.length; i++) {
      valueByHeader[headers[i]] = values[i];
    }

    final items = <GradeDetailItem>[];
    for (var i = 0; i < headers.length; i++) {
      final header = headers[i];
      if (header.isEmpty || header == '序号' || header == '总成绩') continue;
      if (header.contains('比例')) continue;

      final score = valueByHeader[header]?.trim() ?? '';
      final ratio = valueByHeader['$header比例']?.trim() ?? '';
      if (score.isEmpty && ratio.isEmpty) continue;
      items.add(GradeDetailItem(name: header, score: score, ratio: ratio));
    }

    return GradeDetail(
      items: items,
      totalScore: valueByHeader['总成绩']?.trim() ?? '',
    );
  }

  static String _extractMatch(String text, String pattern) {
    final re = RegExp(pattern);
    final match = re.firstMatch(text);
    return match?.group(1) ?? '-';
  }
}

class _StudyProgressParser {
  static Map<String, String> parseIndexForm(String html) {
    final document = html_parser.parse(html);
    final form = document.querySelector('form');
    if (form == null) return const {};

    final values = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name']?.trim() ?? '';
      if (name.isEmpty) continue;
      values[name] = input.attributes['value']?.trim() ?? '';
    }
    return values;
  }

  static StudyProgressData parseReportHtml(
    String html, {
    required String currentSemester,
  }) {
    final document = html_parser.parse(html);
    final summaryTable = _findStudyProgressTable(
      document,
      '课程体系',
    );
    final courseTable = _findStudyProgressTable(
      document,
      '修读学期',
    );
    if (summaryTable == null || courseTable == null) {
      return StudyProgressData(
        groups: const [],
        currentSemester: currentSemester,
        currentSemesterCourses: const [],
      );
    }

    final summaryByTitle = _parseSummaryTable(summaryTable);
    final coursesByTitle = _parseCourseTable(courseTable);
    final groups = <StudyProgressGroup>[];

    final orderedTitles = <String>[
      ...summaryByTitle.keys,
      ...coursesByTitle.keys.where((title) => !summaryByTitle.containsKey(title)),
    ];

    for (final title in orderedTitles) {
      final summary = summaryByTitle[title];
      final courses = coursesByTitle[title] ?? const <StudyProgressCourse>[];
      groups.add(
        StudyProgressGroup(
          id: title,
          title: title,
          requiredCredits: summary?.requiredCredits ?? '',
          earnedCredits: summary?.earnedCredits ?? '',
          remainingCredits: summary?.remainingCredits ?? '',
          completionRate: '',
          courses: courses,
        ),
      );
    }

    return StudyProgressData(
      groups: groups,
      currentSemester: currentSemester,
      currentSemesterCourses: const [],
    );
  }

  static dom.Element? _findStudyProgressTable(
    dom.Document document,
    String marker,
  ) {
    for (final table in document.querySelectorAll('table')) {
      final text = table.text.replaceAll(RegExp(r'\s+'), '');
      if (text.contains(marker)) return table;
    }
    return null;
  }

  static Map<String, _StudyProgressSummary> _parseSummaryTable(dom.Element table) {
    final result = <String, _StudyProgressSummary>{};
    final rows = table.querySelectorAll('tr');

    for (var i = 1; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('td,th');
      if (cells.length < 5) continue;
      final rawTitle = cells[0].text.trim();
      if (rawTitle.isEmpty || rawTitle == '总计') continue;
      final title = _normalizeStudyGroupTitle(rawTitle);
      if (title.isEmpty) continue;

      final current = result[title];
      result[title] = _StudyProgressSummary(
        requiredCredits: _sumTexts(current?.requiredCredits, cells[1].text),
        earnedCredits: _sumTexts(current?.earnedCredits, cells[2].text),
        remainingCredits: _sumTexts(current?.remainingCredits, cells[4].text),
      );
    }

    return result;
  }

  static Map<String, List<StudyProgressCourse>> _parseCourseTable(dom.Element table) {
    final result = <String, List<StudyProgressCourse>>{};
    var currentGroup = '';
    final rows = table.querySelectorAll('tr');

    for (var i = 1; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('td,th');
      if (cells.isEmpty) continue;

      final texts = cells.map((cell) => cell.text.trim()).toList();
      final nonEmpty = texts.where((text) => text.isNotEmpty).toList();
      if (nonEmpty.isEmpty) continue;

      if (cells.length == 1 || (cells.length > 1 && nonEmpty.length == 1)) {
        currentGroup = nonEmpty.first;
        result.putIfAbsent(currentGroup, () => <StudyProgressCourse>[]);
        continue;
      }

      if (cells.length < 10 || currentGroup.isEmpty) continue;

      result.putIfAbsent(currentGroup, () => <StudyProgressCourse>[]).add(
        StudyProgressCourse(
          semester: texts[0],
          code: texts[1],
          name: texts[2],
          credits: texts[3],
          attribute: texts[4],
          nature: texts[5],
          status: texts[6],
          score: texts[7],
          remark: texts[8],
          isDegreeCourse: texts[9],
        ),
      );
    }

    return result;
  }

  static String _normalizeStudyGroupTitle(String rawTitle) {
    final text = rawTitle.trim();
    if (text.isEmpty) return '';
    if (!text.contains('_')) return text;
    final right = text.split('_').last.trim();
    return right.replaceAll(RegExp(r'\((必修|选修|校选)\)$'), '');
  }

  static String _sumTexts(String? current, String next) {
    final currentValue = double.tryParse((current ?? '').trim());
    final nextValue = double.tryParse(next.trim());
    if (currentValue == null && nextValue == null) return next.trim();
    if (currentValue == null) return nextValue!.toStringAsFixed(1);
    if (nextValue == null) return current!;
    return (currentValue + nextValue).toStringAsFixed(1);
  }
}

class _StudyProgressSummary {
  const _StudyProgressSummary({
    required this.requiredCredits,
    required this.earnedCredits,
    required this.remainingCredits,
  });

  final String requiredCredits;
  final String earnedCredits;
  final String remainingCredits;
}

// ---------------------------------------------------------------------------
// Exam parser
// ---------------------------------------------------------------------------

/// Parses the exam page HTML from the 强智 system.
class _ExamParser {
  static List<Exam> parse(String html) {
    final exams = <Exam>[];
    final document = html_parser.parse(html);
    final table = document.getElementById('dataList');

    if (table == null) return exams;

    final rows = table.querySelectorAll('tr');
    for (int i = 1; i < rows.length; i++) {
      final cells = rows[i]
          .querySelectorAll('td')
          .map((cell) => cell.text.trim())
          .toList();
      if (cells.length == 1 && cells.first.contains('未查询到数据')) break;
      if (cells.length < 12) continue;

      exams.add(Exam(
        campus: cells.length > 2 ? cells[2] : '',
        courseName: cells.length > 5 ? cells[5] : '',
        teacher: cells.length > 6 ? cells[6] : '',
        examTime: cells.length > 7 ? cells[7] : '',
        examRoom: cells.length > 8 ? cells[8] : '',
        seatNumber: cells.length > 9 ? cells[9] : '-',
        ticketNumber: cells.length > 10 ? cells[10] : '-',
      ));
    }

    return exams;
  }
}

// ---------------------------------------------------------------------------
// E-card page parsers
// ---------------------------------------------------------------------------

/// Parses e-card system HTML pages.
class _EcardParser {
  /// Extract electricity balance from the eleresult page.
  /// Looks for a label with text "剩余电量" and reads the sibling value.
  static String parseElecBalance(String html) {
    final document = html_parser.parse(html);
    dom.Element? label;
    for (final item in document.querySelectorAll('label.weui-label')) {
      if (item.text.contains('剩余电量')) {
        label = item;
        break;
      }
    }
    if (label == null) return '查询失败';

    final siblingValue = label.parent?.nextElementSibling?.text.trim();
    final siblingNumber = _numbersOnly(siblingValue ?? '');
    if (siblingNumber.isNotEmpty) return siblingNumber;

    final fallback = _extractNumberNearAnyKeyword(
      html,
      const ['剩余电量', '电量'],
    );
    return fallback ?? '查询失败';
  }

  /// Extract campus card balance from the index page.
  /// Looks for <p> containing "账户余额" and reads the sibling value.
  static String parseCampusCardBalance(String html) {
    final document = html_parser.parse(html);
    for (final p in document.querySelectorAll('p')) {
      if (!p.text.contains('账户余额')) continue;
      final siblingValue = _numbersOnly(
        p.parent?.nextElementSibling?.text.trim() ?? '',
      );
      if (siblingValue.isNotEmpty) return siblingValue;
    }

    final fallback = _extractNumberNearAnyKeyword(
      html,
      const ['账户余额', '余额'],
    );
    return fallback ?? '查询失败';
  }

  static String _numbersOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9.]'), '').trim();
  }

  static String? _extractNumberNearAnyKeyword(
    String html,
    List<String> keywords,
  ) {
    for (final keyword in keywords) {
      final index = html.indexOf(keyword);
      if (index < 0) continue;
      final end = (index + 900).clamp(0, html.length);
      final window = html.substring(index, end);
      final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(
        _stripTags(_decodeBasicHtmlEntities(window)),
      );
      if (match != null) return match.group(0);
    }
    return null;
  }

  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ');
  }

  static String _decodeBasicHtmlEntities(String html) {
    return html
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  /// Extract billno and refno from the elepaybill page.
  static ({String billno, String refno, String csrfToken, String csrfHeader})?
      parseRechargePage(String html) {
    final billno = _extractInputValue(html, 'billno');
    final refno = _extractInputValue(html, 'refno');
    if (billno == null || refno == null) return null;

    final csrfToken = _extractMetaContent(html, '_csrf');
    final csrfHeader = _extractMetaContent(html, '_csrf_header');

    return (
      billno: billno,
      refno: refno,
      csrfToken: csrfToken ?? 'X-CSRF-TOKEN',
      csrfHeader: csrfHeader ?? 'X-CSRF-TOKEN',
    );
  }

  /// Extract the pay code token from the v5qrcode page.
  static String? parsePayCodeToken(String html) {
    final pattern = RegExp(
      r"""<input[^>]*\s+id=["']myText["'][^>]*\s+value=["']([^"']*)["']""",
      caseSensitive: false,
    );
    final match = pattern.firstMatch(html);
    return match?.group(1);
  }

  static String? _extractInputValue(String html, String id) {
    final pattern = RegExp(
      r"""<input[^>]*\s+id=["']""" +
          RegExp.escape(id) +
          r"""["'][^>]*\s+value=["']([^"']*)["']""",
      caseSensitive: false,
    );
    final match = pattern.firstMatch(html);
    return match?.group(1);
  }

  static String? _extractMetaContent(String html, String name) {
    final pattern = RegExp(
      r"""<meta[^>]*\s+name=["']""" +
          RegExp.escape(name) +
          r"""["'][^>]*\s+content=["']([^"']*)["']""",
      caseSensitive: false,
    );
    final match = pattern.firstMatch(html);
    return match?.group(1);
  }
}

// ---------------------------------------------------------------------------
// DirectSchoolCampusGateway — main implementation
// ---------------------------------------------------------------------------

/// Local direct-connect campus gateway.
///
/// Makes HTTP requests directly to the school's educational administration
/// system and e-card system, parsing HTML responses to extract data.
///
/// Implements the full CAS authentication flow, cookie/session management,
/// and all [CampusGateway] methods. Designed for [CampusRuntimeMode.localAndroid].
class DirectSchoolCampusGateway implements CampusGateway {
  /// Create a gateway with the given URL configuration.
  ///
  /// Defaults to CQJTU (Chongqing Jiaotong University) endpoints.
  /// Pass a custom [config] to target a different school system.
  DirectSchoolCampusGateway({
    SchoolSystemConfig? config,
    SelfHostedSessionStore? sessionStore,
  })  : _config = config ?? const SchoolSystemConfig(),
        _sessionStore = sessionStore;

  final SchoolSystemConfig _config;
  final SelfHostedSessionStore? _sessionStore;

  // Lazy-initialized per-user state
  final Map<String, _UserSession> _sessions = {};

  _UserSession _session(String username) {
    return _sessions.putIfAbsent(
      username,
      () => _UserSession(_config, _sessionStore),
    );
  }

  /// Bind a CAS ticket captured by WebView into the local direct session.
  ///
  /// This keeps manual security verification local to the device. It must not
  /// call the self-hosted backend because localAndroid is the default product
  /// path for ordinary users.
  Future<void> loginWithTicket(String username, String ticket) async {
    if (ticket.trim().isEmpty) {
      throw const AuthInvalidFailure('ticket 为空，请重新完成网页登录');
    }
    final session = _session(username);
    await session.loginWithTicket(username, ticket);
  }

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    final session = _session(username);
    await session.ensureAuth(username, password);

    // POST to schedule URL with semester parameter
    final formBody = <String, String>{};
    if (semester != null && semester.isNotEmpty) {
      formBody['xnxq01id'] = semester;
    }

    final resp = await session.httpClient.post(
      _config.scheduleUrl,
      formBody: formBody,
    );

    if (_isSessionExpired(resp.body)) {
      await session.forceRelogin(username, password);
      final retryResp = await session.httpClient.post(
        _config.scheduleUrl,
        formBody: formBody,
      );
      return _ScheduleParser.parse(retryResp.body);
    }

    return _ScheduleParser.parse(resp.body);
  }

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) async {
    final session = _session(username);
    await session.ensureAuth(username, password);

    final normalizedSemester = semester.trim();
    if (normalizedSemester.isEmpty) {
      final summaryHtml = await _fetchGradesHtml(
        session,
        username,
        password,
        semester: '',
      );
      final summary = _GradeParser.parse(summaryHtml).summary;
      final grades = <Grade>[];

      for (final item in _recentSemesters()) {
        final html = await _fetchGradesHtml(
          session,
          username,
          password,
          semester: item,
        );
        grades.addAll(_GradeParser.parse(html).grades);
      }

      return (summary: summary, grades: _dedupeGrades(grades));
    }

    final html = await _fetchGradesHtml(
      session,
      username,
      password,
      semester: normalizedSemester,
    );
    return _GradeParser.parse(html);
  }

  @override
  Future<GradeDetail> getGradeDetail(
    String username,
    String password, {
    required Grade grade,
    bool forceRefresh = false,
  }) async {
    final params = grade.detailQueryParameters;
    if (params == null) return const GradeDetail(items: [], totalScore: '');

    final session = _session(username);
    await session.ensureAuth(username, password);

    final resp = await session.httpClient.get(
      _config.gradeDetailUrl,
      queryParams: params,
    );

    if (_isSessionExpired(resp.body)) {
      await session.forceRelogin(username, password);
      final retryResp = await session.httpClient.get(
        _config.gradeDetailUrl,
        queryParams: params,
      );
      return _GradeParser.parseDetail(retryResp.body);
    }

    return _GradeParser.parseDetail(resp.body);
  }

  @override
  Future<StudyProgressData> getStudyProgress(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async {
    final session = _session(username);
    await session.ensureAuth(username, password);

    final indexBody = await _fetchStudyProgressIndexBody(
      session,
      username,
      password,
    );
    final formBody = _StudyProgressParser.parseIndexForm(indexBody);
    final reportBody = await _fetchStudyProgressReportBody(
      session,
      username,
      password,
      formBody: formBody,
    );
    return _StudyProgressParser.parseReportHtml(
      reportBody,
      currentSemester: _currentSemester(),
    );
  }

  Future<String> _fetchGradesHtml(
    _UserSession session,
    String username,
    String password, {
    required String semester,
  }) async {
    final resp = await session.httpClient.get(
      _config.gradesUrl,
      queryParams: {
        'kksj': semester,
        'zylx': '0',
      },
    );

    if (_isSessionExpired(resp.body)) {
      await session.forceRelogin(username, password);
      final retryResp = await session.httpClient.get(
        _config.gradesUrl,
        queryParams: {
          'kksj': semester,
          'zylx': '0',
        },
      );
      return retryResp.body;
    }

    return resp.body;
  }

  List<Grade> _dedupeGrades(List<Grade> grades) {
    final seen = <String>{};
    final result = <Grade>[];

    for (final grade in grades) {
      final key = [
        grade.semester,
        grade.courseCode,
        grade.courseName,
        grade.score,
      ].join('|');
      if (!seen.add(key)) continue;
      result.add(grade);
    }

    return result;
  }

  Future<String> _fetchStudyProgressIndexBody(
    _UserSession session,
    String username,
    String password,
  ) async {
    final resp = await session.httpClient.get(_config.studyProgressUrl);

    if (_isSessionExpired(resp.body)) {
      await session.forceRelogin(username, password);
      final retryResp = await session.httpClient.get(_config.studyProgressUrl);
      return retryResp.body;
    }

    return resp.body;
  }

  Future<String> _fetchStudyProgressReportBody(
    _UserSession session,
    String username,
    String password, {
    required Map<String, String> formBody,
  }) async {
    final resp = await session.httpClient.post(
      _config.studentExecutionPlanUrl,
      formBody: formBody,
    );

    if (_isSessionExpired(resp.body)) {
      await session.forceRelogin(username, password);
      final retryResp = await session.httpClient.post(
        _config.studentExecutionPlanUrl,
        formBody: formBody,
      );
      return retryResp.body;
    }

    return resp.body;
  }

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    final session = _session(username);
    await session.ensureAuth(username, password);

    final targetSemester = semester == null || semester.trim().isEmpty
        ? _currentSemester()
        : semester;
    final formBody = <String, String>{
      'xnxqid': targetSemester,
      'xqlb': '',
    };

    final resp = await session.httpClient.post(
      _config.examsUrl,
      formBody: formBody,
    );

    if (_isSessionExpired(resp.body)) {
      await session.forceRelogin(username, password);
      final retryResp = await session.httpClient.post(
        _config.examsUrl,
        formBody: formBody,
      );
      return _ExamParser.parse(retryResp.body);
    }

    return _ExamParser.parse(resp.body);
  }

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async {
    final session = _session(username);
    await session.ensureAuth(username, password);

    if (dormParams == null ||
        dormParams['roomid'] == null ||
        dormParams['buildid'] == null) {
      throw const DormNotConfiguredFailure();
    }

    // Ensure e-card SSO authorization
    final ecardOk = await session.ensureEcardAuth(username);
    if (!ecardOk) {
      return '查询失败';
    }

    try {
      final resp = await session.httpClient.get(
        _config.ecardEleresultUrl,
        queryParams: dormParams,
      );
      return _EcardParser.parseElecBalance(resp.body);
    } catch (e) {
      dev.log('[_Elec] Balance query failed: $e', name: 'DirectSchool');
      // Retry with re-auth
      await session.ensureEcardAuth(username);
      try {
        final resp = await session.httpClient.get(
          _config.ecardEleresultUrl,
          queryParams: dormParams,
        );
        return _EcardParser.parseElecBalance(resp.body);
      } catch (e2) {
        dev.log('[_Elec] Retry also failed: $e2', name: 'DirectSchool');
        return '查询失败';
      }
    }
  }

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async {
    final session = _session(username);
    await session.ensureAuth(username, password);

    final ecardOk = await session.ensureEcardAuth(username);
    if (!ecardOk) {
      return '一卡通授权失败，请检查登录状态';
    }

    try {
      final resp = await session.httpClient.get(_config.ecardIndexUrl);
      return _EcardParser.parseCampusCardBalance(resp.body);
    } catch (e) {
      dev.log('[_Card] Balance query failed: $e', name: 'DirectSchool');
      return '查询失败：网络异常或页面结构变化';
    }
  }

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    String? password,
    Map<String, String>? dormParams,
  }) async {
    final session = _session(username);
    if (password != null && password.isNotEmpty) {
      await session.ensureAuth(username, password);
    }
    // Password should have been cached from a prior login
    if (!session.isAuthenticated) {
      throw const AuthInvalidFailure('请先登录后再充值');
    }

    if (dormParams == null ||
        dormParams['roomid'] == null ||
        dormParams['buildid'] == null) {
      throw const DormNotConfiguredFailure();
    }

    final ecardOk = await session.ensureEcardAuth(username);
    if (!ecardOk) {
      return '一卡通授权失败，无法充值';
    }

    try {
      // Step 1: GET the order page to obtain billno, refno, CSRF token
      final orderParams = Map<String, String>.from(dormParams)
        ..['amount'] = amount.toStringAsFixed(2)
        ..['rest'] = amount.toStringAsFixed(2);

      final orderResp = await session.httpClient.get(
        _config.ecardElepaybillUrl,
        queryParams: orderParams,
      );

      final orderInfo = _EcardParser.parseRechargePage(orderResp.body);
      if (orderInfo == null) {
        return '未能找到订单号或 CSRF Token';
      }

      // Step 2: POST to confirm payment
      final confirmResp = await session.httpClient.post(
        _config.ecardPayconfirmUrl,
        formBody: {
          'billno': orderInfo.billno,
          'refno': orderInfo.refno,
        },
      );

      return confirmResp.body;
    } catch (e) {
      dev.log('[_Elec] Recharge failed: $e', name: 'DirectSchool');
      return '网络异常';
    }
  }

  @override
  Future<String> getPayCodeToken(String username, {String? password}) async {
    final session = _session(username);
    if (password != null && password.isNotEmpty) {
      await session.ensureAuth(username, password);
    }
    if (!session.isAuthenticated) {
      throw const AuthInvalidFailure('请先登录后再获取付款码');
    }

    final ecardOk = await session.ensureEcardAuth(username);
    if (!ecardOk) return '';

    try {
      final resp = await session.httpClient.get(_config.ecardV5qrcodeUrl);
      return _EcardParser.parsePayCodeToken(resp.body) ?? '';
    } catch (e) {
      dev.log('[_Card] Pay code token failed: $e', name: 'DirectSchool');
      return '';
    }
  }

  @override
  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    String? password,
  }) async {
    final session = _session(username);
    if (password != null && password.isNotEmpty) {
      await session.ensureAuth(username, password);
    }
    if (!session.isAuthenticated) {
      throw const AuthInvalidFailure('请先登录后再充值');
    }

    final ecardOk = await session.ensureEcardAuth(username);
    if (!ecardOk) return '';

    try {
      final url =
          '${_config.ecardDodikechargeUrl}?amount=${amount.toStringAsFixed(2)}&paytype=dike_alipay';
      final resp = await session.httpClient.get(
        url,
      );

      // If we got a redirect (302), the Location header contains the alipay URL
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        // The body contains the Location URL when followRedirects=false
        if (resp.body.startsWith('alipays://') ||
            resp.body.startsWith('alipay')) {
          return resp.body;
        }
        return resp.body;
      }

      return resp.body;
    } catch (e) {
      dev.log('[_Card] Alipay URL failed: $e', name: 'DirectSchool');
      return '';
    }
  }

  // ---- helpers ----

  bool _isSessionExpired(String body) {
    return body.contains('authserver/login');
  }
}

// ---------------------------------------------------------------------------
// Per-user session state
// ---------------------------------------------------------------------------

/// Holds the HTTP client, authenticator, and auth state for one user.
class _UserSession {
  _UserSession(this._config, this._sessionStore) {
    _httpClient = _SchoolHttpClient();
    _authenticator = _CasAuthenticator(_httpClient, _config);
  }

  final SchoolSystemConfig _config;
  final SelfHostedSessionStore? _sessionStore;
  late final _SchoolHttpClient _httpClient;
  late final _CasAuthenticator _authenticator;
  bool _authenticated = false;

  static const _casCookieUrl = 'https://ids.cqjtu.edu.cn/authserver/';
  static const _jwgCookieUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/';
  static const _ecardCookieUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/';

  bool get isAuthenticated => _authenticated;

  _SchoolHttpClient get httpClient => _httpClient;

  /// Ensure the user is authenticated, performing login if needed.
  Future<void> ensureAuth(String username, String password) async {
    _authenticator.cachePassword(password);

    if (_authenticated) {
      // Quick session validity check
      if (await _authenticator.isSessionValid()) return;
      dev.log('[_Session] Session expired, re-logging in',
          name: 'DirectSchool');
    }

    if (await _restoreStoredCookies(username) &&
        await _authenticator.isSessionValid()) {
      _authenticated = true;
      await _persistCookies(username);
      dev.log(
        '[_Session] Restored stored cookies for ${_redactIdentifier(username)}',
        name: 'DirectSchool',
      );
      return;
    }

    await _authenticator.login(username, password);
    _authenticated = true;
    await _persistCookies(username);
  }

  Future<void> loginWithTicket(String username, String ticket) async {
    await _authenticator.loginWithTicket(username, ticket);
    _authenticated = true;
    await _persistCookies(username);
  }

  /// Force a full re-login.
  Future<void> forceRelogin(String username, String password) async {
    _httpClient.clearCookies();
    await _authenticator.login(username, password);
    _authenticated = true;
    await _persistCookies(username);
  }

  /// Ensure e-card SSO authorization.
  Future<bool> ensureEcardAuth(String username) async {
    var ok = await _authenticator.ensureEcardAuth(username);
    if (!ok && await _restoreStoredCookies(username)) {
      ok = await _authenticator.ensureEcardAuth(username);
    }
    if (ok) {
      await _persistCookies(username);
    }
    return ok;
  }

  Future<bool> _restoreStoredCookies(String username) async {
    final store = _sessionStore;
    if (store == null) return false;

    var restored = false;
    restored =
        await _restoreCookie(username, store.loadCasCookies, _casCookieUrl) ||
            restored;
    restored =
        await _restoreCookie(username, store.loadJwgCookies, _jwgCookieUrl) ||
            restored;
    restored = await _restoreCookie(
            username, store.loadEcardCookies, _ecardCookieUrl) ||
        restored;
    return restored;
  }

  Future<bool> _restoreCookie(
    String username,
    Future<String?> Function(String username) load,
    String url,
  ) async {
    final cookies = (await load(username))?.trim() ?? '';
    if (cookies.isEmpty) return false;
    _httpClient.importCookieHeader(url, cookies);
    return true;
  }

  Future<void> _persistCookies(String username) async {
    final store = _sessionStore;
    if (store == null) return;

    await _persistCookie(store.saveCasCookies, username, _casCookieUrl);
    await _persistCookie(store.saveJwgCookies, username, _jwgCookieUrl);
    await _persistCookie(store.saveEcardCookies, username, _ecardCookieUrl);
  }

  Future<void> _persistCookie(
    Future<void> Function(String username, String cookies) save,
    String username,
    String url,
  ) async {
    final cookies = _httpClient.exportCookieHeader(url).trim();
    if (cookies.isEmpty) return;
    await save(username, cookies);
  }
}
