import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/search_highlight.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/avatar_stack.dart';
import '../../../core/widgets/drag_auto_scroll.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/models/note.dart';
import '../../../data/models/note_search.dart';
import '../../../data/models/tag.dart';
import '../../../data/models/title_style_run.dart';
import '../../../data/providers/folders_providers.dart';
import '../../folders/drag_data.dart';
import '../../folders/folder_actions.dart';
import '../../folders/widgets/move_to_folder_picker.dart';

/// `.note-item` — desktop/web notes-list row. Drag it onto a sidebar
/// folder to move it, or onto Recently Deleted. Right-click opens
/// "Move to… / Delete" (mirrors `FolderTreeNode`'s right-click/long-press
/// pattern) — Delete is a soft delete with Undo, so no confirmation.
///
/// When the row is part of a multi-selection, dragging and the menu act on
/// the whole selection ([group]).
class NoteListTile extends ConsumerWidget {
  const NoteListTile({
    super.key,
    required this.note,
    this.tagsById = const {},
    required this.selected,
    required this.onTap,
    this.group = const [],
    this.searchTerms = const [],
  });

  final Note note;
  final Map<String, Tag> tagsById;
  final bool selected;
  final VoidCallback onTap;

  /// The notes dragging or the menu act on; empty means just [note].
  final List<Note> group;

  /// While searching, the words to highlight (see `highlightTerms`).
  final List<String> searchTerms;

  List<Note> get _notes => group.isEmpty ? [note] : group;

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final notes = _notes;
    final n = notes.length;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'move',
          child: Text(n == 1 ? 'Move to…' : 'Move $n Notes to…'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(n == 1 ? 'Delete' : 'Delete $n Notes'),
        ),
      ],
    );
    if (!context.mounted) return;
    final ids = [for (final n in notes) n.id];
    switch (action) {
      case 'move':
        final target = await showMoveToFolderPicker(
          context,
          title: n == 1 ? 'Move "${_label(note)}"' : 'Move $n notes',
          tree: ref.read(folderTreeProvider),
          // Not a folder they're all in already.
          isAllowed: (id) => id != null && notes.any((n) => n.folderId != id),
        );
        if (target?.folderId case final folderId? when context.mounted) {
          await moveNotesTo(context, ref, ids, folderId);
        }
      case 'delete':
        await trashNotes(context, ref, ids);
    }
  }

  static String _label(Note note) =>
      note.title.trim().isEmpty ? 'Untitled' : note.title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = _notes;
    final autoScroll = ref.read(dragAutoScrollProvider);
    final tile = _buildTile(context, ref);
    return Draggable<NooteDragData>(
      data: NotesDragData(
        noteIds: [for (final n in notes) n.id],
        folderIds: {for (final n in notes) n.folderId},
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: DragFeedbackChip(
        label: _label(note),
        icon: AppIconName.textLines,
        count: notes.length,
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: tile),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      child: tile,
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
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
                        children: highlightMatches(
                          buildStyledTitleSpans(
                            note.title,
                            note.titleStyle,
                            AppTextStyles.noteTitle.copyWith(
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
              const SizedBox(height: 4),
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
