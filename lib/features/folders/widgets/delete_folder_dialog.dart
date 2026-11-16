import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/noote_dialog.dart';
import '../../../data/providers/folders_providers.dart';

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Shows the delete-folder warning (computed from a real
/// [FoldersRepository.previewDelete] call, not a generic message) and, if
/// confirmed, performs the delete. Returns `true` if the folder was
/// actually deleted, so callers can react (e.g. leave the folder's screen).
Future<bool> showDeleteFolderDialog(
  BuildContext context,
  WidgetRef ref, {
  required String folderId,
  required String folderName,
}) async {
  final repository = ref.read(foldersRepositoryProvider);
  final preview = await repository.previewDelete(folderId);
  if (!context.mounted) return false;

  final moveToPersonal = await showNooteDialog<bool>(
    context,
    builder: (context) => _DeleteFolderDialog(
      folderName: folderName,
      subfolderCount: preview.subfolderCount,
      noteCount: preview.noteCount,
    ),
  );
  if (moveToPersonal == null) return false;

  await repository.deleteFolder(folderId, moveNotesToPersonal: moveToPersonal);
  return true;
}

/// Pops `true` to keep the notes (moved to Personal), `false` to delete
/// them too, or nothing if cancelled.
class _DeleteFolderDialog extends StatefulWidget {
  const _DeleteFolderDialog({
    required this.folderName,
    required this.subfolderCount,
    required this.noteCount,
  });

  final String folderName;
  final int subfolderCount;
  final int noteCount;

  @override
  State<_DeleteFolderDialog> createState() => _DeleteFolderDialogState();
}

class _DeleteFolderDialogState extends State<_DeleteFolderDialog> {
  // The safe choice is preselected, and Enter doesn't delete: the red
  // button has to be clicked.
  var _keepNotes = true;

  void _delete() => Navigator.of(context).pop(_keepNotes);

  @override
  Widget build(BuildContext context) {
    final notes = widget.noteCount;
    final subfolders = widget.subfolderCount;
    return NooteDialog(
      icon: Icons.delete_outline,
      danger: true,
      title: 'Delete “${widget.folderName}”?',
      subtitle: subfolders > 0
          ? 'The folder and its subfolders go away.'
          : notes > 0
          ? 'The folder goes away.'
          : 'This folder is empty.',
      body: notes == 0 && subfolders == 0
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NooteFacts([
                  if (subfolders > 0)
                    _count(subfolders, 'subfolder', 'subfolders'),
                  _count(notes, 'note', 'notes'),
                ]),
                if (notes > 0) ...[
                  NooteOptionCard(
                    selected: _keepNotes,
                    recommended: true,
                    title: 'Keep the notes',
                    description: notes == 1
                        ? 'Move it to Personal.'
                        : 'Move all $notes to Personal.',
                    onTap: () => setState(() => _keepNotes = true),
                  ),
                  NooteOptionCard(
                    selected: !_keepNotes,
                    danger: true,
                    title: notes == 1
                        ? 'Delete the note too'
                        : 'Delete the notes too',
                    description:
                        'They go to Recently Deleted, where you can restore '
                        'them.',
                    onTap: () => setState(() => _keepNotes = false),
                  ),
                ],
              ],
            ),
      hint: KeyHint([const Kbd('Esc'), ' to cancel']),
      actions: [
        NooteButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        NooteButton.danger('Delete folder', onPressed: _delete),
      ],
    );
  }
}
