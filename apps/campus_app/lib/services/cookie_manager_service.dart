import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-platform cookie reader for school WebView sessions.
///
/// Android: `MainActivity` CookieManager channel.
/// iOS: `AppDelegate` WKHTTPCookieStore (+ HTTPCookieStorage merge).
class CookieManagerService {
  CookieManagerService._();

  static const _channel = MethodChannel('campus_app/cookie_manager');

  /// Returns cookie header string `name=value; name2=value2` for [url], or empty.
  static Future<String> getCookies(String url) async {
    if (kIsWeb) return '';
    try {
      final cookies = await _channel.invokeMethod<String>('getCookies', {
        'url': url,
      });
      return cookies?.trim() ?? '';
    } on MissingPluginException catch (error) {
      debugPrint(
        '[CookieManager] native plugin missing on '
        '${defaultTargetPlatform.name}: $error',
      );
      rethrow;
    } on PlatformException catch (error) {
      debugPrint('[CookieManager] getCookies($url) failed: $error');
      rethrow;
    }
  }
}
