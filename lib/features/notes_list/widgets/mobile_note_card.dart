import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/note.dart';
import '../../../data/models/note_search.dart';
import '../../../data/models/tag.dart';
import '../../../data/models/title_style_run.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/search_highlight.dart';
import '../../folders/folder_actions.dart';
import '../../folders/widgets/move_to_folder_picker.dart';

/// A note in a phone list (a row in a `MobileGroup`): title, then date and
/// the first line. Long-press opens "Move to… / Delete". Delete is a soft
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
          title: 'Move “${note.title.trim().isEmpty ? 'Untitled' : note.title}”',
          tree: ref.read(folderTreeProvider),
          current: (folderId: note.folderId),
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
    final snippet = searchTerms.isEmpty
        ? null
        : searchSnippet(note.bodyPlainText, searchTerms);

    return GestureDetector(
      onLongPressStart: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: highlightMatches(
                    buildStyledTitleSpans(
                      note.title.trim().isEmpty ? 'New Note' : note.title,
                      note.titleStyle,
                      AppTextStyles.noteTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    searchTerms,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${formatNoteDate(note.updatedAt, DateTime.now())}  ',
                      style: AppTextStyles.notePreview.copyWith(
                        fontSize: 13,
                        color: colors.textFaint,
                      ),
                    ),
                    ...highlightMatches([
                      TextSpan(
                        // While searching: the part of the note that matched.
                        text: snippet ??
                            (note.previewText.isEmpty
                                ? 'No additional text'
                                : note.previewText),
                        style: AppTextStyles.notePreview.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ], searchTerms),
                  ],
                ),
                maxLines: snippet == null ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
