import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// HIG-style value + chevron for Settings-style disclosure rows.
class IosDisclosureTrailing extends StatelessWidget {
  const IosDisclosureTrailing({
    super.key,
    required this.value,
    this.enabled = true,
  });

  final String value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = enabled
        ? (isDark ? CupertinoColors.systemGrey : const Color(0xFF8E8E93))
        : (isDark
              ? CupertinoColors.systemGrey.withValues(alpha: 0.5)
              : const Color(0xFFC7C7CC));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: muted,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          CupertinoIcons.chevron_forward,
          size: 16,
          color: muted.withValues(alpha: enabled ? 0.85 : 0.45),
        ),
      ],
    );
  }
}

/// Value picker for 学期周数 / 提醒时间 — **not** Liquid Glass.
///
/// Follows [Apple HIG — Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers):
/// - Short lists → list with checkmarks (less visual weight than a wheel).
/// - Medium / ordered lists → wheel picker at the bottom of the window.
/// - Shown in context via modal popup (avoid full-screen view switches).
/// - System materials only (`systemBackground` / grouped list chrome).
Future<void> showIosWheelPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T value) labelOf,
  required ValueChanged<T> onDone,
}) async {
  if (options.isEmpty) return;

  final onIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  if (!onIos) {
    await _showMaterialListPicker(
      context: context,
      title: title,
      options: options,
      selected: selected,
      labelOf: labelOf,
      onDone: onDone,
    );
    return;
  }

  // HIG: short lists prefer list/pull-down weight; wheels suit medium ordered sets.
  if (options.length <= 8) {
    await _showCupertinoCheckListPicker(
      context: context,
      title: title,
      options: options,
      selected: selected,
      labelOf: labelOf,
      onDone: onDone,
    );
  } else {
    await _showCupertinoWheelPicker(
      context: context,
      title: title,
      options: options,
      selected: selected,
      labelOf: labelOf,
      onDone: onDone,
    );
  }
}

/// Settings-style list (checkmark) — ideal for 提醒时间 (few discrete values).
Future<void> _showCupertinoCheckListPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T value) labelOf,
  required ValueChanged<T> onDone,
}) async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final bg = CupertinoColors.systemGroupedBackground.resolveFrom(
        sheetContext,
      );
      final card = CupertinoColors.secondarySystemGroupedBackground
          .resolveFrom(sheetContext);
      final label = CupertinoColors.label.resolveFrom(sheetContext);
      final accent = CupertinoColors.activeBlue.resolveFrom(sheetContext);
      final separator = CupertinoColors.separator.resolveFrom(sheetContext);

      return Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: separator.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        sheetContext,
                      ),
                      letterSpacing: -0.08,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: card,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < options.length; i++) ...[
                            if (i > 0)
                              Container(
                                height: 0.5,
                                margin: const EdgeInsetsDirectional.only(
                                  start: 16,
                                ),
                                color: separator,
                              ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                onDone(options[i]);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        labelOf(options[i]),
                                        style: TextStyle(
                                          fontSize: 17,
                                          color: label,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                    ),
                                    if (options[i] == selected)
                                      Icon(
                                        CupertinoIcons.checkmark,
                                        size: 20,
                                        color: accent,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Classic iOS wheel at bottom — ideal for 学期周数 (ordered medium list).
Future<void> _showCupertinoWheelPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T value) labelOf,
  required ValueChanged<T> onDone,
}) async {
  var current = options.contains(selected) ? selected : options.first;
  final initialIndex = options.indexOf(current).clamp(0, options.length - 1);
  final bottom = MediaQuery.viewPaddingOf(context).bottom;

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final bg = CupertinoColors.systemBackground.resolveFrom(sheetContext);
      final label = CupertinoColors.label.resolveFrom(sheetContext);
      final accent = CupertinoColors.activeBlue.resolveFrom(sheetContext);
      final separator = CupertinoColors.separator.resolveFrom(sheetContext);

      return Material(
        color: Colors.transparent,
        child: Container(
          height: 280 + bottom,
          color: bg,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 17, color: accent),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: label,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onDone(current);
                      },
                      child: Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: separator),
              Expanded(
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: initialIndex,
                  ),
                  itemExtent: 36,
                  magnification: 1.05,
                  useMagnifier: false,
                  squeeze: 1.1,
                  onSelectedItemChanged: (i) => current = options[i],
                  children: [
                    for (final o in options)
                      Center(
                        child: Text(
                          labelOf(o),
                          style: TextStyle(
                            fontSize: 20,
                            color: label,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: bottom > 0 ? bottom : 8),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showMaterialListPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T value) labelOf,
  required ValueChanged<T> onDone,
}) async {
  final picked = await showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      title: Text(labelOf(o)),
                      trailing: o == selected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(sheetContext).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(o),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  if (picked != null) onDone(picked);
}
