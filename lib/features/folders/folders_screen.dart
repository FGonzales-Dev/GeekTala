import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/providers/folders_providers.dart';
import '../../data/providers/notes_providers.dart';
import '../shell/providers/selected_folder_provider.dart';
import 'widgets/folder_disclosure.dart';
import 'widgets/folder_name_dialog.dart';
import 'widgets/folder_tree_node.dart';

/// Mobile "Folders" tab — mirrors the desktop sidebar's folder tree.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tree = ref.watch(folderTreeProvider);
    final noteCounts = ref.watch(noteCountsByFolderProvider).value ?? const {};
    final selectedFolderId = ref.watch(selectedFolderIdProvider);
    final deletedCount = ref.watch(deletedNotesProvider).value?.length ?? 0;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Folders',
                  style: AppTextStyles.mobileScreenTitle.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                _AddFolderButton(
                  onPressed: () async {
                    final name = await showFolderNameDialog(
                      context,
                      title: 'New folder',
                      confirmLabel: 'Create',
                    );
                    if (name != null) {
                      await ref
                          .read(foldersRepositoryProvider)
                          .createFolder(name: name);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final folder in tree.roots)
                  FolderTreeNode(
                    key: ValueKey(folder.id),
                    folder: folder,
                    tree: tree,
                    depth: 0,
                    noteCounts: noteCounts,
                    selectedFolderId: selectedFolderId,
                    onSelect: (id) =>
                        ref.read(selectedFolderIdProvider.notifier).select(id),
                    rowBuilder: (
                      context, {
                      required folder,
                      required depth,
                      required selected,
                      required noteCount,
                      required onTap,
                      expanded,
                      onToggle,
                    }) {
                      return _FolderRow(
                        name: folder.name,
                        count: noteCount,
                        depth: depth,
                        selected: selected,
                        onTap: onTap,
                        expanded: expanded,
                        onToggle: onToggle,
                      );
                    },
                  ),
                const SizedBox(height: 6),
                _TrashRow(
                  count: deletedCount,
                  onTap: () => context.push('/trash'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 15, color: colors.textFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Recently Deleted',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0)
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: colors.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddFolderButton extends StatelessWidget {
  const _AddFolderButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: AppIcon(
              AppIconName.add,
              size: 13,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.count,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.expanded,
    this.onToggle,
  });

  final String name;
  final int count;
  final int depth;
  final bool selected;
  final VoidCallback onTap;
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? colors.activeBg : null,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        padding: EdgeInsets.fromLTRB(4 + depth * 18, 8, 10, 8),
        child: Row(
          children: [
            // A bigger tap target on touch screens.
            FolderDisclosure(
              expanded: expanded,
              onToggle: onToggle,
              size: 18,
              color: colors.textFaint,
            ),
            const SizedBox(width: 2),
            AppIcon(AppIconName.folder, size: 15, color: colors.textFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: colors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
