import 'package:campus_platform/services/credential_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CredentialLoadState { idle, loading, loaded }

final credentialLoadStateProvider = StateProvider<CredentialLoadState>(
  (ref) => CredentialLoadState.idle,
);

class CredentialsNotifier
    extends Notifier<({String username, String password})?> {
  @override
  ({String username, String password})? build() => null;

  Future<void> load(CredentialService svc) async {
    ref.read(credentialLoadStateProvider.notifier).state =
        CredentialLoadState.loading;
    state = await svc.load();
    ref.read(credentialLoadStateProvider.notifier).state =
        CredentialLoadState.loaded;
  }

  void set(String username, String password) {
    ref.read(credentialLoadStateProvider.notifier).state =
        CredentialLoadState.loaded;
    state = (username: username, password: password);
  }

  void clear() {
    ref.read(credentialLoadStateProvider.notifier).state =
        CredentialLoadState.loaded;
    state = null;
  }
}

final credentialsProvider =
    NotifierProvider<
      CredentialsNotifier,
      ({String username, String password})?
    >(CredentialsNotifier.new);

final signedInUsernameHintProvider = Provider<String?>((ref) => null);

void ensureCredentialPassword(({String username, String password}) creds) {
  if (creds.password.trim().isEmpty) {
    throw Exception('Credential password is empty, please login again');
  }
}
