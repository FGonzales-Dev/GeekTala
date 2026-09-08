import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_stack.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/models/note.dart';
import '../../../data/models/tag.dart';
import '../../../data/models/title_style_run.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../core/utils/relative_time.dart';

/// `.m-note-card`. Long-press opens a "Delete" menu — a soft delete, so no
/// confirmation; it lands in Recently Deleted and can be restored.
class MobileNoteCard extends ConsumerWidget {
  const MobileNoteCard({
    super.key,
    required this.note,
    this.tagsById = const {},
    required this.onTap,
  });

  final Note note;
  final Map<String, Tag> tagsById;
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
    if (action == 'delete') {
      await ref.read(notesRepositoryProvider).deleteNote(note.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;

    return GestureDetector(
      onLongPressStart: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: colors.borderSoft),
            borderRadius: BorderRadius.circular(AppRadius.normal + 1),
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
                            fontSize: 13,
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
              const SizedBox(height: 3),
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
                  padding: const EdgeInsets.only(top: 8),
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
