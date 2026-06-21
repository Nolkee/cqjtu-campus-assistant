import 'package:campus_platform/services/credential_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户凭据（学号/密码）状态。
class CredentialsNotifier
    extends Notifier<({String username, String password})?> {
  @override
  ({String username, String password})? build() => null;

  Future<void> load(CredentialService svc) async {
    state = await svc.load();
  }

  void set(String username, String password) {
    state = (username: username, password: password);
  }

  void clear() => state = null;
}

final credentialsProvider =
    NotifierProvider<
      CredentialsNotifier,
      ({String username, String password})?
    >(CredentialsNotifier.new);

void ensureCredentialPassword(({String username, String password}) creds) {
  if (creds.password.trim().isEmpty) {
    throw Exception('Credential password is empty, please login again');
  }
}
