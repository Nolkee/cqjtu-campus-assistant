import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/ios_style.dart';

/// iOS 26+ floating Liquid Glass tab bar (课表 / 校园卡 / 服务 / 我的).
///
/// **On iOS 26+** this is a **native** Platform View:
/// - Chrome: Apple's official [UIGlassEffect] (`UIVisualEffectView`)
/// - Interaction: UIKit pan/tap with continuous A→B pill motion
///
/// Flutter-only glass + GestureDetector was unreliable (Platform View hit-testing
/// broke A→B drag and looked “double layered”).
///
/// Spec:
/// https://developer.apple.com/documentation/uikit/uiglasseffect
/// https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
class LiquidGlassTabBar extends StatelessWidget {
  const LiquidGlassTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<LiquidGlassTabItem> items;

  static const double barHeight = 56;
  static const double surfaceVerticalPadding = 5;
  static const double glassSurfaceHeight =
      barHeight + surfaceVerticalPadding * 2;
  static const double contentClearance = 12;
  static const double fallbackBottomGap = 12;

  static double occupiedHeight(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final outerBottom = safeBottom > 0 ? safeBottom : fallbackBottomGap;
    return glassSurfaceHeight + outerBottom;
  }

  static double contentBottomInset(BuildContext context) =>
      occupiedHeight(context) + contentClearance;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final outerBottom = bottom > 0 ? bottom : fallbackBottomGap;
    final height = glassSurfaceHeight + outerBottom;

    if (usesAppleLiquidGlass &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: _NativeLiquidGlassTabBar(
          currentIndex: currentIndex,
          onTap: onTap,
          items: items,
        ),
      );
    }

    // Non-iOS26 fallback (Material-ish capsule).
    return _FlutterFallbackTabBar(
      currentIndex: currentIndex,
      onTap: onTap,
      items: items,
      outerBottom: outerBottom,
    );
  }
}

class LiquidGlassTabItem {
  const LiquidGlassTabItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.sfSymbol = 'circle',
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  /// SF Symbol name for the native tab bar.
  final String sfSymbol;
}

/// Native UIKit tab bar — official UIGlassEffect + A→B pan.
class _NativeLiquidGlassTabBar extends StatefulWidget {
  const _NativeLiquidGlassTabBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<LiquidGlassTabItem> items;

  @override
  State<_NativeLiquidGlassTabBar> createState() =>
      _NativeLiquidGlassTabBarState();
}

class _NativeLiquidGlassTabBarState extends State<_NativeLiquidGlassTabBar> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant _NativeLiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _channel?.invokeMethod<void>('setSelectedIndex', widget.currentIndex);
    }
  }

  void _onCreated(int id) {
    _channel = MethodChannel('campus_app/liquid_glass_tab_bar_$id');
    _channel!.setMethodCallHandler((call) async {
      if (call.method == 'onSelected') {
        final index = call.arguments;
        if (index is int) {
          widget.onTap(index);
        } else if (index is num) {
          widget.onTap(index.toInt());
        }
      }
    });
    _channel!.invokeMethod<void>('setSelectedIndex', widget.currentIndex);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = <String, Object?>{
      'selectedIndex': widget.currentIndex,
      'items': [
        for (final item in widget.items)
          {'label': item.label, 'symbol': item.sfSymbol},
      ],
    };

    // EagerGestureRecognizer: Flutter must immediately yield the gesture arena
    // to the platform view, otherwise horizontal drags never reach UIKit and
    // A→B pan appears “broken”.
    return UiKitView(
      viewType: 'campus_app/liquid_glass_tab_bar',
      creationParams: params,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onCreated,
      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        Factory<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
        ),
        Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
      },
    );
  }
}

/// Simple Flutter fallback when not on iOS 26.
class _FlutterFallbackTabBar extends StatelessWidget {
  const _FlutterFallbackTabBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.outerBottom,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<LiquidGlassTabItem> items;
  final double outerBottom;

  @override
  Widget build(BuildContext context) {
    final accent = liquidGlassAccent(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, outerBottom),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(30),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SizedBox(
          height: LiquidGlassTabBar.glassSurfaceHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == currentIndex
                              ? (items[i].selectedIcon ?? items[i].icon)
                              : items[i].icon,
                          color: i == currentIndex
                              ? accent
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 22,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == currentIndex
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: i == currentIndex
                                ? accent
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
