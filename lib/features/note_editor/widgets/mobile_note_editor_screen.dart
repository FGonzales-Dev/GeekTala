import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../../folders/folder_actions.dart';
import '../../folders/widgets/move_to_folder_picker.dart';
import '../../shell/widgets/mobile_nav_bar.dart';
import '../markdown_io.dart';
import '../markdown_paste.dart';
import 'note_editor_body.dart';

/// A note on a phone, pushed over the folder it was opened from: Back
/// (to that folder), the sync status and a ••• menu; the bar above the
/// keyboard is in [NoteEditorBody].
class MobileNoteEditorScreen extends ConsumerWidget {
  const MobileNoteEditorScreen({
    super.key,
    required this.noteId,
    this.backLabel,
  });

  final String noteId;

  /// What Back says: the screen it returns to. Defaults to the note's
  /// folder.
  final String? backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final note = ref.watch(noteByIdProvider(noteId)).value;
    final tree = ref.watch(folderTreeProvider);
    final back =
        backLabel ??
        (note?.folderId == null ? null : tree[note!.folderId!]?.name) ??
        'Folders';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            MobileNavBar(
              backLabel: back,
              middle: note == null
                  ? null
                  : const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SyncStatusIndicator(),
                    ),
              actions: [
                if (note != null)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: Icon(
                      Icons.more_horiz,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (value) async {
                      switch (value) {
                        case 'paste_markdown':
                          // The phone's own paste menu bypasses the
                          // editor's paste handling, so it's here.
                          final pasted =
                              await ref
                                  .read(markdownPasteTargetsProvider)[noteId]
                                  ?.pasteClipboardFormatted() ??
                              false;
                          if (!pasted && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Nothing to paste')),
                            );
                          }
                        case 'move':
                          final target = await showMoveToFolderPicker(
                            context,
                            title:
                                'Move “${note.title.trim().isEmpty ? 'New Note' : note.title}”',
                            tree: ref.read(folderTreeProvider),
                            current: (folderId: note.folderId),
                            isAllowed: (id) =>
                                id != null && id != note.folderId,
                          );
                          if (target?.folderId case final folderId?
                              when context.mounted) {
                            await moveNotesTo(context, ref, [noteId], folderId);
                          }
                        case 'export':
                          await exportNoteAsMarkdown(context, note);
                        case 'trash':
                          // Closes this screen, with Undo.
                          await trashNotes(context, ref, [noteId]);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'paste_markdown',
                        child: Text('Paste Markdown'),
                      ),
                      PopupMenuItem(value: 'move', child: Text('Move to…')),
                      PopupMenuItem(
                        value: 'export',
                        child: Text('Export as Markdown…'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'trash', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            Expanded(
              child: note == null
                  ? const Center(child: Text('Note not found'))
                  : NoteEditorBody(noteId: noteId, desktop: false),
            ),
          ],
        ),
      ),
    );
  }
}
