import 'package:flutter/material.dart';

class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.pages,
    required this.destinations,
    required this.railDestinations,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final List<NavigationRailDestination> railDestinations;

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      body: Row(
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
            child: IndexedStack(index: currentIndex, children: pages),
          ),
        ],
      ),
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
