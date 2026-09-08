import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/providers/folders_providers.dart';

/// Shows the delete-folder warning (computed from a real
/// [FoldersRepository.previewDelete] call, not a generic message) and, if
/// confirmed, performs the delete. Returns `true` if the folder was
/// actually deleted, so callers can react (e.g. deselect it).
Future<bool> showDeleteFolderDialog(
  BuildContext context,
  WidgetRef ref, {
  required String folderId,
  required String folderName,
}) async {
  final repository = ref.read(foldersRepositoryProvider);
  final preview = await repository.previewDelete(folderId);
  if (!context.mounted) return false;

  var moveToPersonal = true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Delete "$folderName"?'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.normal),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview.subfolderCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This will also delete ${preview.subfolderCount} '
                      '${preview.subfolderCount == 1 ? 'subfolder' : 'subfolders'}.',
                    ),
                  ),
                if (preview.noteCount > 0) ...[
                  Text(
                    'What should happen to the ${preview.noteCount} '
                    '${preview.noteCount == 1 ? 'note' : 'notes'} inside?',
                  ),
                  RadioGroup<bool>(
                    groupValue: moveToPersonal,
                    onChanged: (value) => setState(() => moveToPersonal = value!),
                    child: const Column(
                      children: [
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Move to Personal'),
                          value: true,
                        ),
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Delete the notes'),
                          value: false,
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Text('This folder is empty.'),
              ],
            ),
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
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return false;

  await repository.deleteFolder(folderId, moveNotesToPersonal: moveToPersonal);
  return true;
}
