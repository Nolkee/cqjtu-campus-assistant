import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'ios_style_io.dart' if (dart.library.html) 'ios_style_stub.dart'
    as ios_impl;

/// Whether the current device should use Apple Liquid Glass styling.
///
/// On iOS 26+ — see:
/// https://developer.apple.com/documentation/technologyoverviews/liquid-glass
/// https://developer.apple.com/documentation/uikit/uiglasseffect
bool get usesAppleLiquidGlass {
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.iOS) return false;
  return ios_impl.isIos26OrAbove();
}

/// Platform view type registered in `LiquidGlassPlatformView.swift`.
const String kNativeLiquidGlassViewType = 'campus_app/ui_glass_effect';

/// Cupertino-style control accent (system blue).
Color liquidGlassAccent(BuildContext context) {
  return CupertinoColors.activeBlue.resolveFrom(context);
}

/// High contrast / bold text → avoid translucency where possible.
bool liquidGlassReduceTransparency(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  if (mq == null) return false;
  return mq.highContrast || mq.boldText;
}

/// Adaptive switch: [CupertinoSwitch] on iOS, Material [Switch] elsewhere.
class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final onIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (onIos) {
      return CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: activeColor ?? liquidGlassAccent(context),
      );
    }
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeColor,
    );
  }
}

/// Maps to [UIGlassEffect.Style] on iOS 26+.
///
/// - [thin] / clear → `UIGlassEffectStyleClear`
/// - [regular] / [thick] → `UIGlassEffectStyleRegular`
enum LiquidGlassWeight {
  thin,
  regular,
  thick,
}

/// Liquid Glass surface.
///
/// **iOS 26+:** Apple's official [UIGlassEffect] via `UiKitView`
/// (`UIVisualEffectView` + `UIGlassEffect`). No Flutter-drawn “fake glass”
/// layers on top — system material only (Adopting Liquid Glass).
///
/// **Elsewhere:** translucent fallback so the app still runs.
///
/// Spec:
/// https://developer.apple.com/documentation/uikit/uiglasseffect
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 28,
    this.padding,
    this.weight = LiquidGlassWeight.regular,
    this.tint,
    this.interactive = false,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final LiquidGlassWeight weight;
  final Color? tint;
  final bool interactive;

  /// Prefer clear so content peeks through (Apple: glass elevates content).
  String get _nativeStyle => switch (weight) {
    LiquidGlassWeight.thin => 'clear',
    LiquidGlassWeight.regular => 'clear',
    LiquidGlassWeight.thick => 'regular',
  };

  @override
  Widget build(BuildContext context) {
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (usesAppleLiquidGlass &&
        !kIsWeb &&
        !liquidGlassReduceTransparency(context)) {
      return _NativeLiquidGlass(
        borderRadius: borderRadius,
        style: _nativeStyle,
        interactive: interactive,
        tint: tint,
        child: content,
      );
    }

    return _FallbackGlass(
      borderRadius: borderRadius,
      weight: weight,
      interactive: interactive,
      child: content,
    );
  }
}

/// Pure system glass — **no** Flutter border/gradient painted over it.
///
/// Extra Flutter fills were what made the bar look “weird” (double chrome).
class _NativeLiquidGlass extends StatelessWidget {
  const _NativeLiquidGlass({
    required this.borderRadius,
    required this.style,
    required this.interactive,
    required this.child,
    this.tint,
  });

  final double borderRadius;
  final String style;
  final bool interactive;
  final Color? tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final params = <String, Object?>{
      'style': style,
      'interactive': interactive,
      'cornerRadius': borderRadius,
      if (tint != null) 'tint': _colorToHex(tint!),
    };

    // Shadow lives *outside* the clip so we don't paint over UIGlassEffect.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: interactive ? 0.14 : 0.1),
            blurRadius: interactive ? 24 : 18,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: UiKitView(
                viewType: kNativeLiquidGlassViewType,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                gestureRecognizers:
                    const <Factory<OneSequenceGestureRecognizer>>{},
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }

  static String _colorToHex(Color c) {
    final a = (c.a * 255).round().clamp(0, 255);
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '${a.toRadixString(16).padLeft(2, '0')}'
        '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
}

/// Non-iOS26 / reduce-transparency fallback (not official UIGlassEffect).
class _FallbackGlass extends StatelessWidget {
  const _FallbackGlass({
    required this.child,
    required this.borderRadius,
    required this.weight,
    required this.interactive,
  });

  final Widget child;
  final double borderRadius;
  final LiquidGlassWeight weight;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduce = liquidGlassReduceTransparency(context);
    final radius = BorderRadius.circular(borderRadius);
    final blur = reduce
        ? 0.0
        : switch (weight) {
            LiquidGlassWeight.thin => 20.0,
            LiquidGlassWeight.regular => 36.0,
            LiquidGlassWeight.thick => 48.0,
          };

    final fills = reduce
        ? (isDark
              ? [const Color(0xF02C2C2E), const Color(0xF01C1C1E)]
              : [const Color(0xF5F2F2F7), const Color(0xF5E5E5EA)])
        : [
            Colors.white.withValues(alpha: isDark ? 0.18 : 0.5),
            Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
          ];

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.85),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: interactive ? 28 : 22,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fills,
        ),
      ),
      child: child,
    );

    if (blur <= 0) {
      return ClipRRect(borderRadius: radius, child: surface);
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: surface,
      ),
    );
  }
}
