import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_icon.dart';

class MobileTab {
  const MobileTab(this.icon, this.label);

  final AppIconName icon;
  final String label;
}

const mobileTabs = [
  MobileTab(AppIconName.listLines, 'Notes'),
  MobileTab(AppIconName.grid, 'Folders'),
  MobileTab(AppIconName.people, 'Shared'),
  MobileTab(AppIconName.clock, 'Settings'),
];

/// `.m-tabbar`
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < mobileTabs.length; i++)
              _TabButton(
                tab: mobileTabs[i],
                active: i == currentIndex,
                onTap: () => onTap(i),
                activeColor: theme.colorScheme.onSurface,
                inactiveColor: colors.textFaint,
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

  final MobileTab tab;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(tab.icon, size: 19, color: color),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
