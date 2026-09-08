import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/avatar_stack.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/models/note.dart';
import '../../../data/models/tag.dart';
import '../../../data/models/title_style_run.dart';
import '../../../data/providers/notes_providers.dart';

/// `.note-item` — desktop/web notes-list row. Right-click opens a
/// "Delete" menu (mirrors `FolderTreeNode`'s right-click/long-press
/// pattern) — a soft delete, so no confirmation; it lands in Recently
/// Deleted and can be restored.
class NoteListTile extends ConsumerWidget {
  const NoteListTile({
    super.key,
    required this.note,
    this.tagsById = const {},
    required this.selected,
    required this.onTap,
  });

  final Note note;
  final Map<String, Tag> tagsById;
  final bool selected;
  final VoidCallback onTap;

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
    );
    if (action != 'delete' || !context.mounted) return;
    await ref.read(notesRepositoryProvider).deleteNote(note.id);
    if (selected && context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showMenu(context, ref, details.globalPosition),
      onLongPressStart: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? colors.activeBg : null,
            border: Border(bottom: BorderSide(color: colors.borderSoft)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: buildStyledTitleSpans(
                          note.title,
                          note.titleStyle,
                          AppTextStyles.noteTitle.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatRelativeTime(note.updatedAt, DateTime.now()),
                    style: AppTextStyles.noteTime.copyWith(
                      color: colors.textFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                note.previewText,
                style: AppTextStyles.notePreview.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (note.tagIds.isNotEmpty || note.collaboratorInitials.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      for (final tagId in note.tagIds)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TagChip(label: tagsById[tagId]?.name ?? tagId),
                        ),
                      const Spacer(),
                      if (note.collaboratorInitials.isNotEmpty)
                        AvatarStack(
                          initials: note.collaboratorInitials,
                          size: 16,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
