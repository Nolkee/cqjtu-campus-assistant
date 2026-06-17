import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef WidgetTargetHandler = void Function(String target);

class WidgetNavigationService {
  static const _channel = MethodChannel('campus_app/widget_navigation');

  static bool get _usesNativeAndroidNavigation =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void setTargetHandler(WidgetTargetHandler handler) {
    if (!_usesNativeAndroidNavigation) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'widgetTargetChanged') return null;
      final target = call.arguments?.toString();
      if (target != null && target.isNotEmpty) handler(target);
      return null;
    });
  }

  static Future<String?> consumePendingTarget() async {
    if (!_usesNativeAndroidNavigation) return null;

    try {
      final target = await _channel.invokeMethod<String>(
        'consumePendingWidgetTarget',
      );
      return target?.isEmpty == true ? null : target;
    } catch (error) {
      debugPrint('[WIDGET] consumePendingTarget failed: $error');
      return null;
    }
  }
}
