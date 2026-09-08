import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/avatar_stack.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/models/note.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../markdown_io.dart';

/// `.editor-topbar` — breadcrumb, sync status, collaborators, Share button.
class EditorTopBar extends ConsumerWidget {
  const EditorTopBar({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final folders = ref.watch(allFoldersProvider).value ?? const [];
    final folder = folders.where((f) => f.id == note.folderId).firstOrNull;
    final parent = folder?.parentId == null
        ? null
        : folders.where((f) => f.id == folder!.parentId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTextStyles.breadcrumb.copyWith(
                  color: colors.textFaint,
                ),
                children: [
                  if (parent != null) TextSpan(text: '${parent.name} / '),
                  TextSpan(
                    text: folder?.name ?? '',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SyncStatusIndicator(),
          if (note.collaboratorInitials.isNotEmpty) ...[
            const SizedBox(width: 12),
            AvatarStack(initials: note.collaboratorInitials),
          ],
          const SizedBox(width: 12),
          _ShareButton(),
          const SizedBox(width: 8),
          _OverflowMenu(note: note),
        ],
      ),
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(
        Icons.more_horiz,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onSelected: (value) async {
        switch (value) {
          case 'export':
            await exportNoteAsMarkdown(context, note);
          case 'trash':
            await ref.read(notesRepositoryProvider).deleteNote(note.id);
            if (context.mounted) context.go('/');
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'export', child: Text('Export as Markdown…')),
        PopupMenuItem(value: 'trash', child: Text('Move to Trash')),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.small + 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small + 1),
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(AppRadius.small + 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIconName.share,
                size: 12,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 5),
              Text(
                'Share',
                style: AppTextStyles.shareButton.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
