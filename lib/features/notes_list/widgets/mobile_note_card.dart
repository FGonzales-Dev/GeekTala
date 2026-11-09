import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_stack.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/models/note.dart';
import '../../../data/models/note_search.dart';
import '../../../data/models/tag.dart';
import '../../../data/models/title_style_run.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/search_highlight.dart';
import '../../folders/folder_actions.dart';
import '../../folders/widgets/move_to_folder_picker.dart';

/// `.m-note-card`. Long-press opens "Move to… / Delete". Delete is a soft
/// delete with Undo, so no confirmation; it lands in Recently Deleted.
class MobileNoteCard extends ConsumerWidget {
  const MobileNoteCard({
    super.key,
    required this.note,
    this.tagsById = const {},
    required this.onTap,
    this.searchTerms = const [],
  });

  final Note note;
  final Map<String, Tag> tagsById;
  final VoidCallback onTap;

  /// While searching, the words to highlight (see `highlightTerms`).
  final List<String> searchTerms;

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
      items: const [
        PopupMenuItem(value: 'move', child: Text('Move to…')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case 'move':
        final target = await showMoveToFolderPicker(
          context,
          title: 'Move "${note.title.trim().isEmpty ? 'Untitled' : note.title}"',
          tree: ref.read(folderTreeProvider),
          isAllowed: (id) => id != null && id != note.folderId,
        );
        if (target?.folderId case final folderId? when context.mounted) {
          await moveNotesTo(context, ref, [note.id], folderId);
        }
      case 'delete':
        await trashNotes(context, ref, [note.id]);
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
                        children: highlightMatches(
                          buildStyledTitleSpans(
                            note.title,
                            note.titleStyle,
                            AppTextStyles.noteTitle.copyWith(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          searchTerms,
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
              Text.rich(
                TextSpan(
                  children: highlightMatches([
                    TextSpan(
                      // While searching: the part of the note that matched.
                      text: (searchTerms.isEmpty
                              ? null
                              : searchSnippet(note.bodyPlainText, searchTerms)) ??
                          note.previewText,
                      style: AppTextStyles.notePreview.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ], searchTerms),
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
