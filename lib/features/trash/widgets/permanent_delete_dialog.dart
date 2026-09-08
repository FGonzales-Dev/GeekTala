import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/providers/notes_providers.dart';

/// Confirms and performs a permanent (hard) delete — unlike the regular
/// "Delete" action (which just soft-deletes into Recently Deleted), this
/// is irreversible, so it gets a warning dialog (styled like
/// `showDeleteFolderDialog`).
Future<void> showPermanentDeleteDialog(
  BuildContext context,
  WidgetRef ref, {
  required String noteId,
  required String noteTitle,
}) async {
  final title = noteTitle.trim().isEmpty ? 'Untitled' : noteTitle;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text('Permanently delete "$title"?'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.normal),
        ),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Forever'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    await ref.read(notesRepositoryProvider).permanentlyDeleteNote(noteId);
  }
}
