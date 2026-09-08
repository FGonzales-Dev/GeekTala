import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/providers/notes_providers.dart';
import '../markdown_io.dart';
import 'note_editor_body.dart';

/// `.m-editor-topbar` + `.m-editor-scroll` + `.m-toolbar` — pushed
/// full-screen when a note is opened on mobile (no bottom nav visible).
class MobileNoteEditorScreen extends ConsumerWidget {
  const MobileNoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final note = ref.watch(noteByIdProvider(noteId)).value;

    if (note == null) {
      return const Scaffold(body: Center(child: Text('Note not found')));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    child: AppIcon(
                      AppIconName.chevronLeft,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      const SyncStatusIndicator(),
                      const SizedBox(width: 14),
                      AppIcon(
                        AppIconName.share,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: Icon(
                          Icons.more_horiz,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (value) async {
                          switch (value) {
                            case 'export':
                              await exportNoteAsMarkdown(context, note);
                            case 'trash':
                              await ref
                                  .read(notesRepositoryProvider)
                                  .deleteNote(noteId);
                              if (context.mounted) context.go('/');
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'export',
                            child: Text('Export as Markdown…'),
                          ),
                          PopupMenuItem(
                            value: 'trash',
                            child: Text('Move to Trash'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: NoteEditorBody(noteId: noteId, desktop: false)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  AppIcon(AppIconName.bold, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  AppIcon(AppIconName.textLines, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  AppIcon(AppIconName.image, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  AppIcon(AppIconName.code, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  AppIcon(AppIconName.grid, size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
