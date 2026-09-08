import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'settings_body.dart';

/// Desktop's way into Settings — a modal dialog (opened from the sidebar's
/// gear icon), not a route: Settings is a configuration surface, not
/// something to browse, so unlike Recently Deleted it doesn't take over
/// the notes-list/editor pane.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.normal),
      ),
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: SettingsBody(),
            ),
          ],
        ),
      ),
    );
  }
}
