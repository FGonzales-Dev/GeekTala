import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/folder.dart';
import '../../../data/providers/folders_providers.dart';
import 'delete_folder_dialog.dart';
import 'folder_name_dialog.dart';

/// Renders [folder] via [rowBuilder], then recurses into its children —
/// arbitrary depth, not hardcoded to one level. Shared by the desktop
/// sidebar and the mobile Folders screen; each supplies its own row visual
/// via [rowBuilder] so this widget only owns the tree structure and the
/// long-press/right-click "New subfolder / Rename / Delete" menu.
class FolderTreeNode extends ConsumerWidget {
  const FolderTreeNode({
    super.key,
    required this.folder,
    required this.allFolders,
    required this.depth,
    required this.noteCounts,
    required this.selectedFolderId,
    required this.onSelect,
    required this.rowBuilder,
  });

  final Folder folder;
  final List<Folder> allFolders;
  final int depth;
  final Map<String, int> noteCounts;
  final String? selectedFolderId;
  final ValueChanged<String> onSelect;
  final Widget Function(
    BuildContext context, {
    required Folder folder,
    required int depth,
    required bool selected,
    required int noteCount,
    required VoidCallback onTap,
  })
  rowBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = allFolders.where((f) => f.parentId == folder.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onSecondaryTapDown: (details) =>
              _showActionsMenu(context, ref, details.globalPosition),
          onLongPressStart: (details) =>
              _showActionsMenu(context, ref, details.globalPosition),
          child: rowBuilder(
            context,
            folder: folder,
            depth: depth,
            selected: folder.id == selectedFolderId,
            noteCount: noteCounts[folder.id] ?? 0,
            onTap: () => onSelect(folder.id),
          ),
        ),
        for (final child in children)
          FolderTreeNode(
            folder: child,
            allFolders: allFolders,
            depth: depth + 1,
            noteCounts: noteCounts,
            selectedFolderId: selectedFolderId,
            onSelect: onSelect,
            rowBuilder: rowBuilder,
          ),
      ],
    );
  }

  Future<void> _showActionsMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final repository = ref.read(foldersRepositoryProvider);
    final protected = repository.isProtected(folder.id);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'new_subfolder', child: Text('New subfolder')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (!protected) const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'new_subfolder':
        final name = await showFolderNameDialog(
          context,
          title: 'New subfolder',
          confirmLabel: 'Create',
        );
        if (name != null) {
          await repository.createFolder(name: name, parentId: folder.id);
        }
      case 'rename':
        final name = await showFolderNameDialog(
          context,
          title: 'Rename folder',
          initialName: folder.name,
          confirmLabel: 'Rename',
        );
        if (name != null) await repository.renameFolder(folder.id, name);
      case 'delete':
        await showDeleteFolderDialog(
          context,
          ref,
          folderId: folder.id,
          folderName: folder.name,
        );
    }
  }
}
