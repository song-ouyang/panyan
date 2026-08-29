import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';

class WanpanShell extends StatelessWidget {
  const WanpanShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    if (index != navigationShell.currentIndex) {
      HapticFeedback.selectionClick();
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        color: WanpanColors.surface,
        border: Border(top: BorderSide(color: WanpanColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _select,
          animationDuration: Duration.zero,
          destinations: const [
            NavigationDestination(
              icon: _TabIcon('assets/icons/gym.png'),
              selectedIcon: _TabIcon('assets/icons/gym-active.png'),
              label: '岩馆',
              tooltip: '岩馆',
            ),
            NavigationDestination(
              icon: _TabIcon('assets/icons/feed.png'),
              selectedIcon: _TabIcon('assets/icons/feed-active.png'),
              label: '广场',
              tooltip: '广场',
            ),
            NavigationDestination(
              icon: _TabIcon('assets/icons/ranking.png'),
              selectedIcon: _TabIcon('assets/icons/ranking-active.png'),
              label: '排行',
              tooltip: '排行',
            ),
            NavigationDestination(
              icon: _TabIcon('assets/icons/profile.png'),
              selectedIcon: _TabIcon('assets/icons/profile-active.png'),
              label: '我的',
              tooltip: '我的',
            ),
          ],
        ),
      ),
    ),
  );
}

class _TabIcon extends StatelessWidget {
  const _TabIcon(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: 25,
    height: 25,
    filterQuality: FilterQuality.medium,
  );
}
