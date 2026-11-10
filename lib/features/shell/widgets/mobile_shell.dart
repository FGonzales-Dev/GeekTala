import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../data/providers/notes_providers.dart';
import '../../folders/folders_screen.dart';
import '../../notes_list/widgets/mobile_notes_list_screen.dart';
import '../../settings/settings_screen.dart';
import '../../sharing/shared_screen.dart';
import 'mobile_bottom_nav.dart';

const _tabPaths = ['/', '/folders', '/shared', '/settings'];

/// Mobile bottom-nav shell — the four top-level tabs, driven by the current
/// route so `/folders`, `/shared`, `/settings` are real, linkable URLs.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.currentPath});

  final String currentPath;

  int get _currentIndex {
    final index = _tabPaths.indexOf(currentPath);
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          MobileNotesListScreen(),
          FoldersScreen(),
          SharedScreen(),
          SettingsScreen(),
        ],
      ),
      floatingActionButton: index == 0 ? const _NewNoteFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: MobileBottomNav(
        currentIndex: index,
        onTap: (i) => context.go(_tabPaths[i]),
      ),
    );
  }
}

class _NewNoteFab extends ConsumerWidget {
  const _NewNoteFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: FloatingActionButton(
        // No hero flight: the note screen has no matching button, and the
        // tabs share one page, so while the button animates back in on the
        // Notes tab two copies briefly exist — which breaks hero animations
        // if a note opens in that moment.
        heroTag: null,
        onPressed: () async {
          final id = await ref.read(notesRepositoryProvider).createNote();
          if (context.mounted) context.go('/notes/$id');
        },
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        shape: const CircleBorder(),
        child: AppIcon(
          AppIconName.add,
          size: 20,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
