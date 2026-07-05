import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final credentialServiceProvider =
    Provider<CredentialService>((ref) => CredentialService());

String _redactIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '<empty>';
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

/// 使用系统级加密存储账号密码。
/// Android 底层走 Android Keystore，绝不明文存储。
class CredentialService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyUsername = 'username';
  static const _keyPassword = 'password';
  static const _signedInUsernameKey = 'credential_signed_in_username_v1';

  Future<void> save(String username, String password) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_signedInUsernameKey, username);
    if (kDebugMode) {
      debugPrint(
        '[CredentialService] save username=${_redactIdentifier(username)} passwordLen=${password.length}',
      );
    }
  }

  Future<({String username, String password})?> load() async {
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
        '[CredentialService] load username=${_redactIdentifier(username)} passwordLen=${password.length}',
      );
    }
    return (username: username, password: password);
  }

  Future<String?> loadSignedInUsernameHint() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_signedInUsernameKey)?.trim();
    return username == null || username.isEmpty ? null : username;
  }

  Future<void> clear() async {
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_signedInUsernameKey);
  }
}
