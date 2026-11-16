import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/noote_dialog.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import 'settings_sections.dart';

/// Desktop's Settings: a window with its sections down the side (opened
/// from the sidebar's gear). On phones Settings is a screen instead — see
/// `SettingsScreen`.
Future<void> showSettingsWindow(
  BuildContext context, {
  SettingsSection section = SettingsSection.appearance,
}) {
  return showNooteDialog<void>(
    context,
    builder: (_) => SettingsWindow(initialSection: section),
  );
}

class SettingsWindow extends ConsumerStatefulWidget {
  const SettingsWindow({
    super.key,
    this.initialSection = SettingsSection.appearance,
  });

  final SettingsSection initialSection;

  @override
  ConsumerState<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends ConsumerState<SettingsWindow> {
  late var _section = widget.initialSection;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final size = MediaQuery.sizeOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: NooteDialogSurface(
        width: 760,
        height: (size.height - 48).clamp(360, 520),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 196,
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                border: Border(right: BorderSide(color: colors.borderSoft)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  for (final section in SettingsSection.values)
                    _NavButton(
                      section: section,
                      selected: section == _section,
                      onTap: () => setState(() => _section = section),
                    ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: SyncStatusIndicator(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                      child: IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.close, color: colors.textFaint),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey(_section),
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _section == SettingsSection.about
                                ? 'About Noote'
                                : _section.label,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _section.lead,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Divider(height: 1, color: colors.borderSoft),
                          SettingsSectionBody(_section),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final fg = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Semantics(
            selected: selected,
            button: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(section.icon, size: 16, color: fg),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      section.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
