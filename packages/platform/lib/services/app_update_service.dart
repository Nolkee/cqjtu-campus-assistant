import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppUpdateCheckStatus { notConfigured, upToDate, updateAvailable }

class InstalledAppVersion {
  const InstalledAppVersion({
    required this.version,
    required this.buildNumber,
  });

  final String version;
  final int buildNumber;

  String get label => buildNumber > 0 ? '$version+$buildNumber' : version;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.force,
    required this.title,
    required this.notes,
    required this.releasePageUrl,
    this.downloadUrl,
    this.androidDownloadUrl,
    this.iosDownloadUrl,
  });

  factory AppUpdateInfo.fromJson(
    Map<String, dynamic> json, {
    required String defaultReleasePageUrl,
  }) {
    final android = AppUpdateService._asMap(json['android']);
    final ios = AppUpdateService._asMap(json['ios']);
    final assets = AppUpdateService._asList(json['assets']);
    final apkAsset = AppUpdateService._pickAndroidAsset(assets);
    final rawVersion = AppUpdateService._readString(json, const [
          'version',
          'latestVersion',
          'tag_name',
          'tagName',
          'name',
        ]) ??
        AppUpdateService._readString(apkAsset, const ['name']) ??
        '';

    final version = AppUpdateService._normalizeVersion(rawVersion);
    if (version.isEmpty) {
      throw const FormatException('Update feed missing version');
    }

    final buildNumber = AppUpdateService._readInt(json, const [
          'buildNumber',
          'build',
          'versionCode',
        ]) ??
        AppUpdateService._extractBuildNumber(rawVersion) ??
        AppUpdateService._extractBuildNumber(
          AppUpdateService._readString(apkAsset, const ['name']) ?? '',
        ) ??
        0;

    return AppUpdateInfo(
      version: version,
      buildNumber: buildNumber,
      force: AppUpdateService._readBool(json, const ['force', 'mandatory']) ??
          false,
      title: AppUpdateService._readString(json, const ['title', 'name']) ??
          '发现新版本',
      notes: AppUpdateService._readNotes(json),
      releasePageUrl: AppUpdateService._readString(
            json,
            const ['releasePageUrl', 'html_url', 'htmlUrl'],
          ) ??
          defaultReleasePageUrl,
      downloadUrl: AppUpdateService._readString(json, const [
        'downloadUrl',
        'url',
        'storeUrl',
      ]),
      androidDownloadUrl: AppUpdateService._readString(
            android,
            const ['downloadUrl', 'url', 'apkUrl'],
          ) ??
          AppUpdateService._readString(
            apkAsset,
            const ['browser_download_url'],
          ),
      iosDownloadUrl: AppUpdateService._readString(
        ios,
        const ['downloadUrl', 'url', 'storeUrl', 'browser_download_url'],
      ),
    );
  }

  final String version;
  final int buildNumber;
  final bool force;
  final String title;
  final String notes;
  final String releasePageUrl;
  final String? downloadUrl;
  final String? androidDownloadUrl;
  final String? iosDownloadUrl;

  String get label => buildNumber > 0 ? '$version+$buildNumber' : version;

  String? resolveDownloadUrl() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return androidDownloadUrl ?? downloadUrl;
      case TargetPlatform.iOS:
        return iosDownloadUrl ?? downloadUrl;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return downloadUrl ?? androidDownloadUrl ?? iosDownloadUrl;
    }
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.current,
    this.latest,
  });

  final AppUpdateCheckStatus status;
  final InstalledAppVersion current;
  final AppUpdateInfo? latest;

  bool get hasUpdate => status == AppUpdateCheckStatus.updateAvailable;
}

class AppUpdateService {
  static const _updateUrl = String.fromEnvironment(
    'APP_UPDATE_URL',
    defaultValue: '',
  );
  static const _githubRepo = String.fromEnvironment(
    'GITHUB_REPO',
    defaultValue: 'AAAAxuuuuu/cqjtu-campus-assistant',
  );

  static const _installedVersionKey = 'app_installed_version';
  static const _installedBuildKey = 'app_installed_build_number';
  static const _lastNotifiedVersionKey = 'app_update_last_notified_version';
  static const _updateFeedCacheKey = 'app_update_feed_cache_v1';
  static const _updateFeedCacheTtl = Duration(hours: 6);

  static String get defaultReleasePageUrl =>
      'https://github.com/${_githubRepo.trim()}/releases/latest';

  static String? get feedUrl {
    final explicit = _updateUrl.trim();
    if (explicit.isNotEmpty) return explicit;

    final repo = _githubRepo.trim();
    if (repo.isEmpty) return null;
    return 'https://api.github.com/repos/$repo/releases/latest';
  }

  static Future<void> saveInstalledVersion(InstalledAppVersion version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_installedVersionKey, version.version);
    await prefs.setInt(_installedBuildKey, version.buildNumber);
  }

  static Future<InstalledAppVersion?> loadInstalledVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString(_installedVersionKey);
    final buildNumber = prefs.getInt(_installedBuildKey);
    if (version == null || version.isEmpty || buildNumber == null) {
      return null;
    }
    return InstalledAppVersion(version: version, buildNumber: buildNumber);
  }

  static Future<AppUpdateCheckResult?> checkForStoredInstalledVersion() async {
    final installed = await loadInstalledVersion();
    if (installed == null) return null;
    return checkForUpdate(current: installed);
  }

  static Future<AppUpdateCheckResult> checkForUpdate({
    required InstalledAppVersion current,
    bool forceRefresh = false,
  }) async {
    final url = feedUrl;
    if (url == null || url.isEmpty) {
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.notConfigured,
        current: current,
      );
    }

    final cache = await _loadFeedCache();
    if (!forceRefresh && cache != null && cache.isFresh(_updateFeedCacheTtl)) {
      final latest = AppUpdateInfo.fromJson(
        cache.data,
        defaultReleasePageUrl: defaultReleasePageUrl,
      );
      return _resultForCurrent(latest, current);
    }

    try {
      final payload = await _fetchLatestFeed(url, cache: cache);
      await _saveFeedCache(payload);
      final latest = AppUpdateInfo.fromJson(
        payload.data,
        defaultReleasePageUrl: defaultReleasePageUrl,
      );
      return _resultForCurrent(latest, current);
    } catch (error) {
      if (cache != null) {
        debugPrint('[UPDATE] using cached feed after error: $error');
        final latest = AppUpdateInfo.fromJson(
          cache.data,
          defaultReleasePageUrl: defaultReleasePageUrl,
        );
        return _resultForCurrent(latest, current);
      }
      throw Exception('Unable to check for updates: $error');
    }
  }

  static Future<bool> shouldNotify(AppUpdateInfo latest) async {
    final prefs = await SharedPreferences.getInstance();
    final lastNotified = prefs.getString(_lastNotifiedVersionKey) ?? '';
    return lastNotified != latest.label;
  }

  static Future<void> markNotified(AppUpdateInfo latest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNotifiedVersionKey, latest.label);
  }

  static Future<_UpdateFeedPayload> _fetchLatestFeed(
    String url, {
    _UpdateFeedCache? cache,
  }) async {
    final uri = Uri.tryParse(url);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 600,
        headers: _buildRequestHeaders(uri, cache?.etag),
      ),
    );

    final response = await dio.get<dynamic>(url);
    if (response.statusCode == 304) {
      if (cache == null) {
        throw Exception('HTTP 304: no cached update feed available');
      }
      return _UpdateFeedPayload(
        data: cache.data,
        etag: cache.etag,
        checkedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    if ((response.statusCode ?? 500) >= 400) {
      final message = _extractErrorMessage(response.data);
      final prefix = 'HTTP ${response.statusCode}';
      if (message != null && message.isNotEmpty) {
        throw Exception('$prefix: $message');
      }
      if (response.statusCode == 403 && uri?.host == 'api.github.com') {
        throw Exception(
          '$prefix: GitHub API access forbidden. This is usually rate limiting or repository access restrictions.',
        );
      }
      throw Exception(prefix);
    }

    dynamic raw = response.data;
    if (raw is String) {
      raw = jsonDecode(raw);
    }

    final outer = _asMap(raw);
    final code = _readInt(outer, const ['code']);
    final data = code == 200 ? _asMap(outer['data']) : outer;
    return _UpdateFeedPayload(
      data: data,
      etag: response.headers.value('etag'),
      checkedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Map<String, String> _buildRequestHeaders(
    Uri? uri,
    String? etag,
  ) {
    final headers = <String, String>{};
    if (uri?.host.toLowerCase() != 'api.github.com') {
      return headers;
    }
    headers.addAll({
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'cqjtu-campus-assistant',
    });
    final normalizedEtag = etag?.trim();
    if (normalizedEtag != null && normalizedEtag.isNotEmpty) {
      headers['If-None-Match'] = normalizedEtag;
    }
    return headers;
  }

  static String? _extractErrorMessage(dynamic raw) {
    if (raw == null) return null;

    dynamic data = raw;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return null;
      try {
        data = jsonDecode(trimmed);
      } catch (_) {
        return trimmed;
      }
    }

    final json = _asMap(data);
    return _readString(json, const ['message', 'msg', 'error', 'detail']);
  }

  static Future<_UpdateFeedCache?> _loadFeedCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_updateFeedCacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final mapped = json.map((key, value) => MapEntry(key.toString(), value));
      return _UpdateFeedCache.fromJson(mapped);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveFeedCache(_UpdateFeedPayload payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _updateFeedCacheKey,
      jsonEncode(
        {
          'data': payload.data,
          'etag': payload.etag,
          'checkedAtMs': payload.checkedAtMs,
        },
      ),
    );
  }

  static AppUpdateCheckResult _resultForCurrent(
    AppUpdateInfo latest,
    InstalledAppVersion current,
  ) {
    if (_isNewerThanCurrent(latest, current)) {
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.updateAvailable,
        current: current,
        latest: latest,
      );
    }

    return AppUpdateCheckResult(
      status: AppUpdateCheckStatus.upToDate,
      current: current,
      latest: latest,
    );
  }

  static bool _isNewerThanCurrent(
    AppUpdateInfo latest,
    InstalledAppVersion current,
  ) {
    if (latest.buildNumber > 0 && current.buildNumber > 0) {
      if (latest.buildNumber != current.buildNumber) {
        return latest.buildNumber > current.buildNumber;
      }
    }

    final versionCompare = _compareVersion(latest.version, current.version);
    if (versionCompare != 0) return versionCompare > 0;

    return latest.buildNumber > current.buildNumber;
  }

  static int _compareVersion(String left, String right) {
    final leftParts = _parseVersionParts(left);
    final rightParts = _parseVersionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final a = i < leftParts.length ? leftParts[i] : 0;
      final b = i < rightParts.length ? rightParts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  static List<int> _parseVersionParts(String version) {
    final cleaned = _normalizeVersion(version);
    if (cleaned.isEmpty) return const [0];
    return cleaned
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  static String _normalizeVersion(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    var normalized = trimmed;
    final slash = normalized.lastIndexOf('/');
    if (slash >= 0 && slash < normalized.length - 1) {
      normalized = normalized.substring(slash + 1);
    }

    final match = RegExp(r'v?(\d+(?:\.\d+)+)').firstMatch(normalized);
    return match?.group(1) ?? '';
  }

  static int? _extractBuildNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final plusMatch = RegExp(r'\+(\d+)(?:\D|$)').firstMatch(trimmed);
    if (plusMatch != null) {
      return int.tryParse(plusMatch.group(1)!);
    }

    final buildMatch = RegExp(
      r'build[._-]?(\d+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (buildMatch != null) {
      return int.tryParse(buildMatch.group(1)!);
    }

    return null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.map(_asMap).toList(growable: false);
  }

  static Map<String, dynamic> _pickAndroidAsset(
    List<Map<String, dynamic>> assets,
  ) {
    for (final asset in assets) {
      final name = (_readString(asset, const ['name']) ?? '').toLowerCase();
      final contentType =
          (_readString(asset, const ['content_type']) ?? '').toLowerCase();
      if (name.endsWith('.apk') ||
          contentType.contains('android.package-archive')) {
        return asset;
      }
    }
    return const <String, dynamic>{};
  }

  static String _readNotes(Map<String, dynamic> json) {
    final dynamic value = json['notes'] ??
        json['releaseNotes'] ??
        json['changelog'] ??
        json['body'] ??
        '';
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  static String? _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static bool? _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final text = value.trim().toLowerCase();
        if (text == 'true' || text == '1') return true;
        if (text == 'false' || text == '0') return false;
      }
    }
    return null;
  }
}

class _UpdateFeedCache {
  const _UpdateFeedCache({
    required this.data,
    required this.checkedAtMs,
    required this.etag,
  });

  final Map<String, dynamic> data;
  final int checkedAtMs;
  final String? etag;

  bool isFresh(Duration ttl) {
    final age = DateTime.now().millisecondsSinceEpoch - checkedAtMs;
    return age >= 0 && age < ttl.inMilliseconds;
  }

  factory _UpdateFeedCache.fromJson(Map<String, dynamic> json) {
    final data = AppUpdateService._asMap(json['data']);
    return _UpdateFeedCache(
      data: data,
      checkedAtMs: int.tryParse(json['checkedAtMs']?.toString() ?? '') ?? 0,
      etag: json['etag']?.toString(),
    );
  }
}

class _UpdateFeedPayload {
  const _UpdateFeedPayload({
    required this.data,
    required this.checkedAtMs,
    required this.etag,
  });

  final Map<String, dynamic> data;
  final int checkedAtMs;
  final String? etag;
}
