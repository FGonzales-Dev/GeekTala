import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/undo_snack_bar.dart';
import '../../data/models/tag.dart';
import '../../data/providers/tags_providers.dart';
import '../../data/repositories/tags_repository.dart';
import '../folders/widgets/folder_name_dialog.dart';
import '../shell/providers/selected_tag_provider.dart';

/// Right-click / long-press menu for a tag: Rename, Delete (with Undo).
/// Used by the sidebar's tag list and the note's tag picker (which is how
/// tags are reached on mobile).
Future<void> showTagActionsMenu(
  BuildContext context,
  WidgetRef ref,
  Tag tag,
  Offset position,
) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: const [
      PopupMenuItem(value: 'rename', child: Text('Rename')),
      PopupMenuItem(value: 'delete', child: Text('Delete')),
    ],
  );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repository = ref.read(tagsRepositoryProvider);

  switch (action) {
    case 'rename':
      final name = await showFolderNameDialog(
        context,
        title: 'Rename tag',
        initialName: tag.name,
        confirmLabel: 'Rename',
      );
      if (name == null) return;
      try {
        await repository.renameTag(tag.id, name);
      } on TagNameTakenException catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    case 'delete':
      if (ref.read(selectedTagIdProvider) == tag.id) {
        ref.read(selectedTagIdProvider.notifier).clear();
      }
      final deleted = await repository.deleteTag(tag.id);
      if (deleted == null || messenger == null) return;
      final n = deleted.noteIds.length;
      showUndoSnackBar(
        messenger,
        n == 0
            ? 'Deleted tag "${tag.name}"'
            : 'Deleted tag "${tag.name}" from $n ${n == 1 ? 'note' : 'notes'}',
        () async {
          if (!await repository.restoreTag(deleted)) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Couldn\'t restore "${tag.name}": another tag has that '
                  'name now.',
                ),
              ),
            );
          }
        },
      );
  }
}
