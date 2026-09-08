import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../note_editor/widgets/editor_pane.dart';
import '../../notes_list/widgets/notes_list_pane.dart';
import '../../trash/widgets/trash_list.dart';
import '../providers/is_viewing_trash_provider.dart';
import '../providers/pane_widths_provider.dart';
import 'app_sidebar.dart';
import 'resize_handle.dart';

/// `.app-shell` — three-pane layout shared by macOS/Windows/Web (the
/// mockup renders it identically across all three; only the window chrome
/// around it differs, and that chrome is the OS/browser's, not ours).
class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key, this.noteId});

  final String? noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewingTrash = ref.watch(isViewingTrashProvider);

    return Scaffold(
      body: Row(
        // Without this, a bare SizedBox(width: 6) (ResizeHandle's hit area)
        // sizes itself to zero height — Row's default center alignment
        // gives non-flexible children loose constraints, and SizedBox
        // doesn't grow to fill those on its own. Stretching makes every
        // child (panes and handles alike) span the full height.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSidebar(),
          ResizeHandle(
            onDrag: (dx) =>
                ref.read(sidebarWidthProvider.notifier).dragBy(dx),
          ),
          // Recently Deleted replaces the notes-list+editor region rather
          // than being threaded through NotesListPane's search/tag
          // precedence — trashed notes aren't opened in an editor.
          if (viewingTrash)
            const Expanded(child: TrashList())
          else ...[
            NotesListPane(selectedNoteId: noteId),
            ResizeHandle(
              onDrag: (dx) =>
                  ref.read(notesListWidthProvider.notifier).dragBy(dx),
            ),
            Expanded(child: EditorPane(noteId: noteId)),
          ],
        ],
      ),
    );
  }
}
