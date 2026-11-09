import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/undo_snack_bar.dart';
import '../../data/providers/folders_providers.dart';
import '../../data/providers/notes_providers.dart';

// Moves and deletes shared by drag and drop and the "Move to…"/"Delete"
// menus, each followed by an Undo snack bar. The messenger and router are
// looked up before any `await`: the widget that started the action may be
// gone by the time it finishes (a moved folder's row is rebuilt elsewhere).

String _notes(int n) => n == 1 ? 'note' : '$n notes';

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

  final undo = await repository.moveFolder(
    folderId,
    parentId: parentId,
    index: index,
  );
  if (undo == null || messenger == null) return;
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
/// editor is closed.
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
  if (openNoteId != null && noteIds.contains(openNoteId)) router!.go('/');
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
