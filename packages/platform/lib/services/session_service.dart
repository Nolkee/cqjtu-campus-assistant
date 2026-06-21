import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:data/data.dart';

final sessionServiceProvider =
    Provider<SessionService>((ref) => SessionService());

class SessionService implements SelfHostedSessionStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _sessionPrefix = 'session_id_';
  static const _ticketPrefix = 'login_ticket_';
  static const _ticketUpdatedAtPrefix = 'login_ticket_updated_at_';
  static const _casCookiesPrefix = 'cas_cookies_';
  static const _casCookiesUpdatedAtPrefix = 'cas_cookies_updated_at_';
  static const _jwgCookiesPrefix = 'jwg_cookies_';
  static const _jwgCookiesUpdatedAtPrefix = 'jwg_cookies_updated_at_';
  static const _ecardCookiesPrefix = 'ecard_cookies_';
  static const _ecardCookiesUpdatedAtPrefix = 'ecard_cookies_updated_at_';
  static const _zoveTokenPrefix = 'zove_token_';
  static const _zoveTokenUpdatedAtPrefix = 'zove_token_updated_at_';

  Future<String?> loadSessionId(String username) =>
      _storage.read(key: _sessionKey(username));

  Future<void> saveSessionId(String username, String sessionId) =>
      _storage.write(key: _sessionKey(username), value: sessionId);

  Future<String?> loadTicket(String username) =>
      _storage.read(key: _ticketKey(username));

  Future<void> saveTicket(String username, String ticket) =>
      _writeWithTimestamp(
        key: _ticketKey(username),
        updatedAtKey: _ticketUpdatedAtKey(username),
        value: ticket,
      );

  Future<int?> loadTicketUpdatedAt(String username) =>
      _readTimestamp(_ticketUpdatedAtKey(username));

  Future<String?> loadCasCookies(String username) =>
      _storage.read(key: _casCookiesKey(username));

  Future<void> saveCasCookies(String username, String cookies) =>
      _writeWithTimestamp(
        key: _casCookiesKey(username),
        updatedAtKey: _casCookiesUpdatedAtKey(username),
        value: cookies,
      );

  Future<int?> loadCasCookiesUpdatedAt(String username) =>
      _readTimestamp(_casCookiesUpdatedAtKey(username));

  Future<String?> loadJwgCookies(String username) =>
      _storage.read(key: _jwgCookiesKey(username));

  Future<void> saveJwgCookies(String username, String cookies) =>
      _writeWithTimestamp(
        key: _jwgCookiesKey(username),
        updatedAtKey: _jwgCookiesUpdatedAtKey(username),
        value: cookies,
      );

  Future<int?> loadJwgCookiesUpdatedAt(String username) =>
      _readTimestamp(_jwgCookiesUpdatedAtKey(username));

  Future<String?> loadEcardCookies(String username) =>
      _storage.read(key: _ecardCookiesKey(username));

  Future<void> saveEcardCookies(String username, String cookies) =>
      _writeWithTimestamp(
        key: _ecardCookiesKey(username),
        updatedAtKey: _ecardCookiesUpdatedAtKey(username),
        value: cookies,
      );

  Future<int?> loadEcardCookiesUpdatedAt(String username) =>
      _readTimestamp(_ecardCookiesUpdatedAtKey(username));

  Future<String?> loadZoveToken(String username) =>
      _storage.read(key: _zoveTokenKey(username));

  Future<void> saveZoveToken(String username, String token) async {
    await _writeWithTimestamp(
      key: _zoveTokenKey(username),
      updatedAtKey: _zoveTokenUpdatedAtKey(username),
      value: token,
    );
  }

  Future<int?> loadZoveTokenUpdatedAt(String username) =>
      _readTimestamp(_zoveTokenUpdatedAtKey(username));

  Future<void> saveWebLoginArtifacts(
    String username, {
    String? ticket,
    String? casCookies,
    String? jwgCookies,
    String? ecardCookies,
    String? zoveToken,
  }) async {
    if (ticket != null && ticket.isNotEmpty) {
      await saveTicket(username, ticket);
    }
    if (casCookies != null && casCookies.isNotEmpty) {
      await saveCasCookies(username, casCookies);
    }
    if (jwgCookies != null && jwgCookies.isNotEmpty) {
      await saveJwgCookies(username, jwgCookies);
    }
    if (ecardCookies != null && ecardCookies.isNotEmpty) {
      await saveEcardCookies(username, ecardCookies);
    }
    if (zoveToken != null && zoveToken.isNotEmpty) {
      await saveZoveToken(username, zoveToken);
    }
  }

  Future<void> clearForUsername(String username) async {
    await _storage.delete(key: _sessionKey(username));
    await _storage.delete(key: _ticketKey(username));
    await _storage.delete(key: _ticketUpdatedAtKey(username));
    await _storage.delete(key: _casCookiesKey(username));
    await _storage.delete(key: _casCookiesUpdatedAtKey(username));
    await _storage.delete(key: _jwgCookiesKey(username));
    await _storage.delete(key: _jwgCookiesUpdatedAtKey(username));
    await _storage.delete(key: _ecardCookiesKey(username));
    await _storage.delete(key: _ecardCookiesUpdatedAtKey(username));
    await _storage.delete(key: _zoveTokenKey(username));
    await _storage.delete(key: _zoveTokenUpdatedAtKey(username));
  }

  Future<void> _writeWithTimestamp({
    required String key,
    required String updatedAtKey,
    required String value,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await _storage.write(key: key, value: value);
    await _storage.write(key: updatedAtKey, value: now);
  }

  Future<int?> _readTimestamp(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  String sessionKeyFor(String username) => _sessionKey(username);

  String _sessionKey(String username) => '$_sessionPrefix$username';

  String _ticketKey(String username) => '$_ticketPrefix$username';

  String _ticketUpdatedAtKey(String username) =>
      '$_ticketUpdatedAtPrefix$username';

  String _casCookiesKey(String username) => '$_casCookiesPrefix$username';

  String _casCookiesUpdatedAtKey(String username) =>
      '$_casCookiesUpdatedAtPrefix$username';

  String _jwgCookiesKey(String username) => '$_jwgCookiesPrefix$username';

  String _jwgCookiesUpdatedAtKey(String username) =>
      '$_jwgCookiesUpdatedAtPrefix$username';

  String _ecardCookiesKey(String username) => '$_ecardCookiesPrefix$username';

  String _ecardCookiesUpdatedAtKey(String username) =>
      '$_ecardCookiesUpdatedAtPrefix$username';

  String _zoveTokenKey(String username) => '$_zoveTokenPrefix$username';

  String _zoveTokenUpdatedAtKey(String username) =>
      '$_zoveTokenUpdatedAtPrefix$username';
}
