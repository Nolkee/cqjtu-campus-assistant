import 'package:flutter/services.dart';

/// 封装 Android 电池优化相关的原生调用。
/// 对应的原生代码在 android/.../MainActivity.kt 中实现。
class BatteryOptimizationService {
  static const _channel = MethodChannel('campus_app/battery');

  /// 查询当前 App 是否已被加入电池优化白名单（即已忽略电池优化）。
  /// 返回 true 表示已豁免，后台任务可正常运行。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 查询 MIUI 自启动权限状态（通过 AppOps API）。
  /// 返回 true=已开启, false=未开启, null=无法检测（非 MIUI 或系统拦截）。
  static Future<bool?> checkMiuiAutostart() async {
    try {
      return await _channel.invokeMethod<bool>('checkMiuiAutostart');
    } catch (_) {
      return null;
    }
  }

  /// 弹出系统对话框，请求用户将本 App 加入电池优化白名单。
  /// Android 6+（API 23+）有效，MIUI 上此弹窗可能被系统拦截，
  /// 被拦截时会自动降级到 openBatterySettings()。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // 降级：直接打开 App 详情页，用户手动操作
      await openBatterySettings();
    }
  }

  /// 打开 MIUI 自启动管理页面。
  /// 非 MIUI 设备或 MIUI 版本不同时，会自动降级到 App 详情页。
  static Future<void> openMiuiAutostart() async {
    try {
      await _channel.invokeMethod('openMiuiAutostart');
    } catch (_) {
      await openBatterySettings();
    }
  }

  /// 打开系统"应用详情"页（可在此手动关闭电池优化 / 开启自启动）。
  static Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }
}