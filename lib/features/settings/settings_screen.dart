import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../shell/widgets/mobile_nav_bar.dart';
import 'widgets/settings_sections.dart';

/// Phone Settings: a screen opened from the gear on Folders, with the same
/// sections as the desktop window, one under another.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MobileNavBar(backLabel: 'Folders'),
            const MobileLargeTitle('Settings'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                children: [
                  for (final section in SettingsSection.values) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                      child: Text(
                        section.label.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.55,
                          color: colors.textFaint,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border.all(color: colors.borderSoft),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: section == SettingsSection.sync ? 12 : 0,
                          bottom: section == SettingsSection.about ? 8 : 0,
                        ),
                        child: SettingsSectionBody(section, compact: true),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
