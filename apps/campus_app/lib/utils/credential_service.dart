import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final credentialServiceProvider =
    Provider<CredentialService>((ref) => CredentialService());

/// 使用系统级加密存储账号密码。
/// Android 底层走 Android Keystore，绝不明文存储。
class CredentialService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyUsername = 'username';
  static const _keyPassword = 'password';

  Future<void> save(String username, String password) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
  }

  Future<({String username, String password})?> load() async {
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  Future<void> clear() async => _storage.deleteAll();
}
