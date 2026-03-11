import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final credentialServiceProvider =
    Provider<CredentialService>((ref) => CredentialService());

/// 使用系统级加密存储账号密码。
/// Android 底层走 Android Keystore，绝不明文存储。
class CredentialService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _keyUsername = 'username';
  static const _keyPassword = 'password';
  static const _keyBundle = 'credential_bundle_v1';

  Future<void> save(String username, String password) async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      throw ArgumentError('username/password cannot be empty');
    }

    final payload = jsonEncode({
      'username': username,
      'password': password,
    });
    await _storage.write(key: _keyBundle, value: payload);
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
    if (kDebugMode) {
      debugPrint(
        '[CredentialService] save username=$username passwordLen=${password.length}',
      );
    }
  }

  Future<({String username, String password})?> load() async {
    final bundle = await _storage.read(key: _keyBundle);
    if (bundle != null && bundle.trim().isNotEmpty) {
      final decoded = _decodeBundle(bundle);
      if (decoded != null) {
        final legacyUsername = await _storage.read(key: _keyUsername);
        final legacyPassword = await _storage.read(key: _keyPassword);
        if (legacyUsername != decoded.username ||
            legacyPassword != decoded.password) {
          await _storage.write(key: _keyUsername, value: decoded.username);
          await _storage.write(key: _keyPassword, value: decoded.password);
        }
        if (kDebugMode) {
          debugPrint(
            '[CredentialService] load(bundle) username=${decoded.username} passwordLen=${decoded.password.length}',
          );
        }
        return decoded;
      }
    }

    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    if (username == null || password == null || password.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[CredentialService] load empty username=${username != null} passwordLen=${password?.length ?? 0}',
        );
      }
      return null;
    }
    if (kDebugMode) {
      debugPrint(
        '[CredentialService] load username=$username passwordLen=${password.length}',
      );
    }

    final payload = jsonEncode({
      'username': username,
      'password': password,
    });
    await _storage.write(key: _keyBundle, value: payload);
    return (username: username, password: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyBundle);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
  }

  ({String username, String password})? _decodeBundle(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final username = decoded['username']?.toString() ?? '';
      final password = decoded['password']?.toString() ?? '';
      if (username.trim().isEmpty || password.trim().isEmpty) return null;
      return (username: username, password: password);
    } catch (_) {
      return null;
    }
  }
}
