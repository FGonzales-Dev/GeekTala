import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/undo_snack_bar.dart';
import '../../data/providers/folders_providers.dart';
import '../../data/providers/notes_providers.dart';
import 'collapsed_folders_provider.dart';
import 'widgets/folder_name_dialog.dart';

// Moves and deletes shared by drag and drop and the "Move to…"/"Delete"
// menus, each followed by an Undo snack bar. The messenger and router are
// looked up before any `await`: the widget that started the action may be
// gone by the time it finishes (a moved folder's row is rebuilt elsewhere).

String _notes(int n) => n == 1 ? 'note' : '$n notes';

/// "New folder": asks for a name and where it goes ([parentId] to start
/// with), creates it, and opens its parent so it shows. Returns the new
/// folder's id, or null if cancelled.
Future<String?> createFolderFlow(
  BuildContext context,
  WidgetRef ref, {
  String? parentId,
}) async {
  final created = await showNewFolderDialog(
    context,
    tree: ref.read(folderTreeProvider),
    parentId: parentId,
  );
  if (created == null) return null;
  final id = await ref
      .read(foldersRepositoryProvider)
      .createFolder(name: created.name, parentId: created.parentId);
  if (created.parentId case final parent?) {
    ref.read(collapsedFoldersProvider.notifier).expand(parent);
  }
  return id;
}

Future<void> moveNotesTo(
  BuildContext context,
  WidgetRef ref,
  List<String> noteIds,
  String folderId,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repository = ref.read(notesRepositoryProvider);
  final folderName = ref.read(folderTreeProvider)[folderId]?.name ?? 'folder';

  final previous = await repository.moveNotes(noteIds, folderId);
  if (previous.isEmpty || messenger == null) return;
  final n = previous.length;
  showUndoSnackBar(
    messenger,
    n == 1 ? 'Moved to $folderName' : 'Moved ${_notes(n)} to $folderName',
    () => repository.undoMoveNotes(previous),
  );
}

/// Moves folder [folderId] into [parentId] (null = top level), at [index]
/// among its new siblings (null = at the end).
Future<void> moveFolderTo(
  BuildContext context,
  WidgetRef ref,
  String folderId, {
  required String? parentId,
  int? index,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repository = ref.read(foldersRepositoryProvider);
  final tree = ref.read(folderTreeProvider);
  final name = tree[folderId]?.name ?? 'Folder';
  final sameParent = tree[folderId]?.parentId == parentId;
  final collapsed = ref.read(collapsedFoldersProvider.notifier);

  final undo = await repository.moveFolder(
    folderId,
    parentId: parentId,
    index: index,
  );
  if (undo == null) return;
  // Moved into a collapsed folder: open it, so the folder doesn't vanish.
  if (parentId != null) collapsed.expand(parentId);
  if (messenger == null) return;
  showUndoSnackBar(
    messenger,
    sameParent
        ? 'Moved "$name"'
        : parentId == null
        ? 'Moved "$name" to the top level'
        : 'Moved "$name" into ${tree[parentId]?.name ?? 'folder'}',
    () => repository.undoMove(undo),
  );
}

/// Moves notes to Recently Deleted. If the open note is one of them, the
/// editor is closed (on a phone: back to the screen it was opened from).
Future<void> trashNotes(
  BuildContext context,
  WidgetRef ref,
  List<String> noteIds,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.maybeOf(context);
  final openNoteId = router?.state.pathParameters['noteId'];
  final repository = ref.read(notesRepositoryProvider);

  await repository.deleteNotes(noteIds);
  if (openNoteId != null && noteIds.contains(openNoteId)) {
    if (router!.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }
  if (messenger == null) return;
  final n = noteIds.length;
  showUndoSnackBar(
    messenger,
    n == 1
        ? 'Moved to Recently Deleted'
        : 'Moved ${_notes(n)} to Recently Deleted',
    () => repository.restoreNotes(noteIds),
  );
}
