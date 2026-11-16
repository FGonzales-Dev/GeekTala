import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/noote_dialog.dart';
import '../../../data/models/note.dart';
import '../../../data/providers/notes_providers.dart';

/// Confirms and performs a permanent (hard) delete — unlike the regular
/// "Delete" action (which just soft-deletes into Recently Deleted), this
/// is irreversible, so it gets a warning dialog. Enter doesn't confirm it.
Future<void> showPermanentDeleteDialog(
  BuildContext context,
  WidgetRef ref, {
  required String noteId,
  required String noteTitle,
}) async {
  final title = noteTitle.trim().isEmpty ? 'Untitled' : noteTitle;
  final confirmed = await showNooteDialog<bool>(
    context,
    builder: (context) => NooteDialog(
      icon: Icons.warning_amber_rounded,
      danger: true,
      width: 380,
      title: 'Delete “$title” forever?',
      subtitle: 'It\'s removed from all your devices. This can\'t be undone.',
      hint: KeyHint([const Kbd('Esc'), ' to cancel']),
      actions: [
        NooteButton(
          'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NooteButton.danger(
          'Delete forever',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await ref.read(notesRepositoryProvider).permanentlyDeleteNote(noteId);
  }
}

/// "Empty Trash": deletes every note in Recently Deleted forever, after
/// asking. Enter doesn't confirm it.
Future<void> emptyTrashFlow(
  BuildContext context,
  WidgetRef ref,
  List<Note> notes,
) async {
  final n = notes.length;
  final confirmed = await showNooteDialog<bool>(
    context,
    builder: (context) => NooteDialog(
      icon: Icons.warning_amber_rounded,
      danger: true,
      width: 380,
      title: n == 1 ? 'Delete 1 note forever?' : 'Delete all $n notes forever?',
      subtitle:
          'Everything in Recently Deleted is removed from all your devices. '
          'This can\'t be undone.',
      hint: KeyHint([const Kbd('Esc'), ' to cancel']),
      actions: [
        NooteButton(
          'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NooteButton.danger(
          'Empty Trash',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final repository = ref.read(notesRepositoryProvider);
  for (final note in notes) {
    await repository.permanentlyDeleteNote(note.id);
  }
}
