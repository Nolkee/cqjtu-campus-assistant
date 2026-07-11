import 'package:flutter/material.dart';

import '../theme/ios_style.dart';
import 'liquid_glass_tab_bar.dart';

class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.pages,
    required this.destinations,
    required this.railDestinations,
    this.liquidGlassItems,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final List<NavigationRailDestination> railDestinations;

  /// When non-null and [usesAppleLiquidGlass], renders iOS 26 Liquid Glass tab bar.
  final List<LiquidGlassTabItem>? liquidGlassItems;

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    final liquid =
        usesAppleLiquidGlass &&
        liquidGlassItems != null &&
        liquidGlassItems!.isNotEmpty &&
        !isWideScreen;

    final glassInset =
        liquid ? LiquidGlassTabBar.contentBottomInset(context) : 0.0;

    final media = MediaQuery.of(context);
    // Publish bottom inset for scrollables / SafeArea.
    // Content stays **full-bleed** so UIGlassEffect can sample it (Apple:
    // material brings focus to *underlying* content; opaque empty pad kills that).
    final contentMedia = liquid
        ? media.copyWith(
            padding: media.padding.copyWith(bottom: glassInset),
            viewPadding: media.viewPadding.copyWith(bottom: glassInset),
          )
        : media;

    final pagesBody = MediaQuery(
      data: contentMedia,
      child: Row(
        children: [
          if (isWideScreen)
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: onTabSelected,
              labelType: NavigationRailLabelType.all,
              destinations: railDestinations,
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 1,
            ),
          Expanded(
            // Edge-to-edge pages under the floating glass tab bar.
            child: IndexedStack(index: currentIndex, children: pages),
          ),
        ],
      ),
    );

    if (liquid) {
      return Scaffold(
        // Transparent-ish scaffold so glass samples page content, not a solid fill.
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: pagesBody),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LiquidGlassTabBar(
                currentIndex: currentIndex,
                onTap: onTabSelected,
                items: liquidGlassItems!,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: pagesBody,
      bottomNavigationBar: isWideScreen
          ? null
          : NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: onTabSelected,
              destinations: destinations,
              elevation: 0,
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
    );
  }
}
