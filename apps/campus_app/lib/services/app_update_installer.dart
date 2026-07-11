import 'dart:io';

import 'package:campus_platform/services/app_update_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateLaunchStatus {
  installerOpened,
  permissionRequired,
  browserOpened,
  failed,
}

class AppUpdateLaunchResult {
  const AppUpdateLaunchResult({required this.status, this.error});

  final AppUpdateLaunchStatus status;
  final Object? error;
}

class AppUpdateInstaller {
  static const _channel = MethodChannel('campus_app/app_update');

  static Future<AppUpdateLaunchResult> downloadAndLaunch(
    AppUpdateInfo update,
  ) async {
    final fallbackUrl = update.releasePageUrl;
    final downloadUrl = update.resolveDownloadUrl();

    if (defaultTargetPlatform != TargetPlatform.android ||
        downloadUrl == null) {
      final opened = await _openExternalUrl(fallbackUrl);
      return AppUpdateLaunchResult(
        status: opened
            ? AppUpdateLaunchStatus.browserOpened
            : AppUpdateLaunchStatus.failed,
      );
    }

    try {
      final apkPath = await _downloadApk(
        downloadUrl,
        suggestedFileName: 'cqjtu-campus-assistant-${update.label}.apk',
      );
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': apkPath,
      });

      if (result == 'install_started') {
        return const AppUpdateLaunchResult(
          status: AppUpdateLaunchStatus.installerOpened,
        );
      }
      if (result == 'permission_required') {
        return const AppUpdateLaunchResult(
          status: AppUpdateLaunchStatus.permissionRequired,
        );
      }
    } catch (error) {
      final opened = await _openExternalUrl(fallbackUrl);
      return AppUpdateLaunchResult(
        status: opened
            ? AppUpdateLaunchStatus.browserOpened
            : AppUpdateLaunchStatus.failed,
        error: error,
      );
    }

    final opened = await _openExternalUrl(fallbackUrl);
    return AppUpdateLaunchResult(
      status: opened
          ? AppUpdateLaunchStatus.browserOpened
          : AppUpdateLaunchStatus.failed,
    );
  }

  static Future<String> _downloadApk(
    String url, {
    required String suggestedFileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeFileName = suggestedFileName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '-',
    );
    final file = File('${dir.path}/$safeFileName');
    if (await file.exists()) {
      await file.delete();
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    await dio.download(url, file.path);

    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    if (!exists || length <= 0) {
      throw Exception('downloaded apk is empty');
    }
    return file.path;
  }

  static Future<bool> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
