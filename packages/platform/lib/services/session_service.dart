import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final sessionServiceProvider =
    Provider<SessionService>((ref) => SessionService());

class SessionService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _sessionPrefix = 'session_id_';
  static const _ticketPrefix = 'login_ticket_';
  static const _casCookiesPrefix = 'cas_cookies_';
  static const _jwgCookiesPrefix = 'jwg_cookies_';
  static const _ecardCookiesPrefix = 'ecard_cookies_';
  static const _zoveTokenPrefix = 'zove_token_';

  Future<String?> loadSessionId(String username) =>
      _storage.read(key: _sessionKey(username));

  Future<void> saveSessionId(String username, String sessionId) =>
      _storage.write(key: _sessionKey(username), value: sessionId);

  Future<String?> loadTicket(String username) =>
      _storage.read(key: _ticketKey(username));

  Future<void> saveTicket(String username, String ticket) =>
      _storage.write(key: _ticketKey(username), value: ticket);

  Future<String?> loadCasCookies(String username) =>
      _storage.read(key: _casCookiesKey(username));

  Future<void> saveCasCookies(String username, String cookies) =>
      _storage.write(key: _casCookiesKey(username), value: cookies);

  Future<String?> loadJwgCookies(String username) =>
      _storage.read(key: _jwgCookiesKey(username));

  Future<void> saveJwgCookies(String username, String cookies) =>
      _storage.write(key: _jwgCookiesKey(username), value: cookies);

  Future<String?> loadEcardCookies(String username) =>
      _storage.read(key: _ecardCookiesKey(username));

  Future<void> saveEcardCookies(String username, String cookies) =>
      _storage.write(key: _ecardCookiesKey(username), value: cookies);

  Future<String?> loadZoveToken(String username) =>
      _storage.read(key: _zoveTokenKey(username));

  Future<void> saveZoveToken(String username, String token) =>
      _storage.write(key: _zoveTokenKey(username), value: token);

  Future<void> clearForUsername(String username) async {
    await _storage.delete(key: _sessionKey(username));
    await _storage.delete(key: _ticketKey(username));
    await _storage.delete(key: _casCookiesKey(username));
    await _storage.delete(key: _jwgCookiesKey(username));
    await _storage.delete(key: _ecardCookiesKey(username));
    await _storage.delete(key: _zoveTokenKey(username));
  }

  String sessionKeyFor(String username) => _sessionKey(username);

  String _sessionKey(String username) => '$_sessionPrefix$username';

  String _ticketKey(String username) => '$_ticketPrefix$username';

  String _casCookiesKey(String username) => '$_casCookiesPrefix$username';

  String _jwgCookiesKey(String username) => '$_jwgCookiesPrefix$username';

  String _ecardCookiesKey(String username) => '$_ecardCookiesPrefix$username';

  String _zoveTokenKey(String username) => '$_zoveTokenPrefix$username';
}
