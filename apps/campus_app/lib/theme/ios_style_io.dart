import 'dart:io';

/// True on iOS 26+ where Apple Liquid Glass is the system visual language.
bool isIos26OrAbove() {
  if (!Platform.isIOS) return false;
  final match = RegExp(
    r'Version\s+(\d+)',
  ).firstMatch(Platform.operatingSystemVersion);
  final major = int.tryParse(match?.group(1) ?? '') ?? 0;
  return major >= 26;
}
