import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_icon.dart';
import 'widgets/trash_list.dart';

/// Mobile-only push route (`/trash`) — pushed outside the bottom-tab
/// `IndexedStack`, the same way `/notes/:noteId` is. Desktop shows
/// [TrashList] inline instead (see `DesktopShell`).
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
              child: InkWell(
                onTap: () => context.pop(),
                child: AppIcon(
                  AppIconName.chevronLeft,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: TrashList()),
          ],
        ),
      ),
    );
  }
}
