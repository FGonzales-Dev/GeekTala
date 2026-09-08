import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/models/note.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/search_provider.dart';
import '../../../data/providers/tags_providers.dart';
import '../../note_editor/markdown_io.dart';
import '../../shell/providers/pane_widths_provider.dart';
import '../../shell/providers/selected_folder_provider.dart';
import '../../shell/providers/selected_tag_provider.dart';
import 'note_list_tile.dart';

/// `.notes-list` — desktop/web pane between the sidebar and the editor.
/// [selectedNoteId] comes from the current route (`/notes/:noteId`) — the
/// URL is the source of truth for which note is open, not local state.
class NotesListPane extends ConsumerWidget {
  const NotesListPane({super.key, this.selectedNoteId});

  final String? selectedNoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folderId = ref.watch(selectedFolderIdProvider);
    final folders = ref.watch(allFoldersProvider).value ?? const [];
    final folder = folders.where((f) => f.id == folderId).firstOrNull;
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final tagsById = {for (final t in tags) t.id: t};
    final query = ref.watch(searchQueryProvider);
    final searching = query.trim().isNotEmpty;
    final selectedTagId = ref.watch(selectedTagIdProvider);
    final taggedTag = tagsById[selectedTagId];

    // Precedence: search > tag > folder — search and tag are both global
    // (sidebar-level) filters, so either one takes over from the current
    // folder scope; typing in search additionally takes over from a tag.
    final List<Note> notes;
    final String headerLabel;
    if (searching) {
      notes = filterNotesByQuery(
        ref.watch(allNotesProvider).value ?? const [],
        query,
      );
      headerLabel = 'Search results';
    } else if (taggedTag != null) {
      notes = (ref.watch(allNotesProvider).value ?? const [])
          .where((n) => n.tagIds.contains(taggedTag.id))
          .toList();
      headerLabel = '#${taggedTag.name}';
    } else {
      notes = ref.watch(notesInFolderProvider(folderId)).value ?? const [];
      headerLabel = folder?.name ?? 'Notes';
    }
    final showEmptyState = notes.isEmpty && (searching || taggedTag != null);
    final width = ref.watch(notesListWidthProvider);

    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  headerLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (!searching && taggedTag == null) ...[
                  _ImportMarkdownButton(folderId: folderId),
                  const SizedBox(width: 6),
                  _NewNoteButton(folderId: folderId),
                ],
              ],
            ),
          ),
          Expanded(
            child: showEmptyState
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        searching
                            ? 'No notes match "$query"'
                            : 'No notes tagged $headerLabel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: context.nooteColors.textFaint,
                        ),
                      ),
                    ),
                  )
                : ListView(
              children: [
                for (final note in notes)
                  NoteListTile(
                    note: note,
                    tagsById: tagsById,
                    selected: note.id == selectedNoteId,
                    onTap: () => context.go('/notes/${note.id}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportMarkdownButton extends ConsumerWidget {
  const _ImportMarkdownButton({required this.folderId});

  final String? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nooteColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: () => importMarkdownNote(context, ref, folderId: folderId),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Icon(
              Icons.file_upload_outlined,
              size: 14,
              color: colors.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewNoteButton extends ConsumerWidget {
  const _NewNoteButton({required this.folderId});

  final String? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: () async {
          final id = await ref
              .read(notesRepositoryProvider)
              .createNote(folderId: folderId);
          if (context.mounted) context.go('/notes/$id');
        },
        child: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: AppIcon(
              AppIconName.add,
              size: 12,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
