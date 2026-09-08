import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/note.dart';
import '../../../data/models/title_style_run.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../core/utils/relative_time.dart';
import 'permanent_delete_dialog.dart';

/// The "Recently Deleted" list — shared by the desktop pane-swap
/// (`DesktopShell`) and the mobile `TrashScreen`, the same way
/// `NoteEditorBody` is shared across platforms. Rows aren't tappable into
/// the editor; deleted notes are only ever Restored or permanently deleted
/// from here.
class TrashList extends ConsumerWidget {
  const TrashList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final notes = ref.watch(deletedNotesProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recently Deleted',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (notes.isNotEmpty)
                TextButton(
                  onPressed: () => _emptyTrash(ref, notes),
                  child: const Text('Empty Trash'),
                ),
            ],
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? Center(
                  child: Text(
                    'Nothing in Recently Deleted',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: colors.textFaint,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final note in notes) _TrashRow(note: note),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _emptyTrash(WidgetRef ref, List<Note> notes) async {
    final repository = ref.read(notesRepositoryProvider);
    for (final note in notes) {
      await repository.permanentlyDeleteNote(note.id);
    }
  }
}

class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final deletedAt = note.deletedAt;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
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
                const SizedBox(height: 2),
                Text(
                  note.previewText,
                  style: AppTextStyles.notePreview.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  deletedAt == null
                      ? 'Deleted'
                      : 'Deleted ${formatRelativeTime(deletedAt, DateTime.now())}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: colors.textFaint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore',
            icon: const Icon(Icons.restore, size: 18),
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: () =>
                ref.read(notesRepositoryProvider).restoreNote(note.id),
          ),
          IconButton(
            tooltip: 'Delete Forever',
            icon: const Icon(Icons.delete_forever, size: 18),
            color: theme.colorScheme.error,
            onPressed: () => showPermanentDeleteDialog(
              context,
              ref,
              noteId: note.id,
              noteTitle: note.title,
            ),
          ),
        ],
      ),
    );
  }
}
