import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/drag_auto_scroll.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/models/folder_tree.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/tags_providers.dart';
import '../../folders/drag_data.dart';
import '../../folders/folder_actions.dart';
import '../../folders/widgets/delete_folder_dialog.dart';
import '../../folders/widgets/folder_disclosure.dart';
import '../../folders/widgets/folder_name_dialog.dart';
import '../../folders/widgets/folder_tree_node.dart';
import '../../settings/widgets/settings_dialog.dart';
import '../../tags/tag_actions.dart';
import '../providers/is_viewing_trash_provider.dart';
import '../providers/pane_widths_provider.dart';
import '../providers/selected_folder_provider.dart';
import '../providers/selected_tag_provider.dart';

/// `.sidebar` — folder tree, tags, footer sync status. Desktop/web only.
///
/// Drag and drop: notes from the notes list and folders from the tree can
/// be dropped on a folder (see `FolderTreeNode`), folders on the "Folders"
/// heading (to the top of the top level), and either on Recently Deleted.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final selectedFolderId = ref.watch(selectedFolderIdProvider);
    final selectedTagId = ref.watch(selectedTagIdProvider);
    final viewingTrash = ref.watch(isViewingTrashProvider);
    final folders = ref.watch(allFoldersProvider).value ?? const [];
    final tree = ref.watch(folderTreeProvider);
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final noteCounts = ref.watch(noteCountsByFolderProvider).value ?? const {};
    final deletedCount = ref.watch(deletedNotesProvider).value?.length ?? 0;
    final width = ref.watch(sidebarWidthProvider);

    // If the selected folder was deleted (directly or as a descendant of a
    // deleted folder), fall back rather than pointing at nothing.
    if (selectedFolderId != null &&
        folders.isNotEmpty &&
        !folders.any((f) => f.id == selectedFolderId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedFolderIdProvider.notifier).select(null);
      });
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SearchField(hint: 'Search'),
          const SizedBox(height: 14),
          // Folders/tags/trash can outgrow the sidebar's height (arbitrary
          // depth, arbitrary tag count) — scroll that middle section
          // instead of overflowing past the footer.
          Expanded(
            child: DragAutoScrollRegion(
              builder: (context, scrollController) => SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopLevelDropTarget(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SectionLabel('Folders'),
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
                    for (final folder in tree.roots)
                      FolderTreeNode(
                        key: ValueKey(folder.id),
                        folder: folder,
                        tree: tree,
                        dragAndDrop: true,
                        depth: 0,
                        noteCounts: noteCounts,
                        selectedFolderId: selectedFolderId,
                        onSelect: (id) {
                          ref.read(selectedFolderIdProvider.notifier).select(id);
                          ref.read(selectedTagIdProvider.notifier).clear();
                          ref.read(isViewingTrashProvider.notifier).exit();
                        },
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
                          return _NavItem(
                            icon: AppIconName.folder,
                            label: folder.name,
                            trailing: '$noteCount',
                            selected: selected,
                            depth: depth,
                            onTap: onTap,
                            leading: FolderDisclosure(
                              expanded: expanded,
                              onToggle: onToggle,
                              size: 12,
                              color: context.nooteColors.textFaint,
                            ),
                          );
                        },
                      ),
                    _NavItem(
                      icon: AppIconName.people,
                      label: 'Shared with me',
                      trailing: '3',
                    ),
                    const SizedBox(height: 6),
                    _SectionLabel('Tags'),
                    for (final tag in tags)
                      // Right-click / long-press: Rename, Delete.
                      GestureDetector(
                        onSecondaryTapDown: (details) => showTagActionsMenu(
                          context,
                          ref,
                          tag,
                          details.globalPosition,
                        ),
                        onLongPressStart: (details) => showTagActionsMenu(
                          context,
                          ref,
                          tag,
                          details.globalPosition,
                        ),
                        child: _NavItem(
                          icon: AppIconName.tag,
                          label: tag.name,
                          selected: tag.id == selectedTagId,
                          onTap: () {
                            ref.read(selectedTagIdProvider.notifier).toggle(tag.id);
                            ref.read(selectedFolderIdProvider.notifier).select(null);
                            ref.read(isViewingTrashProvider.notifier).exit();
                          },
                        ),
                      ),
                    const SizedBox(height: 6),
                    DragTarget<NooteDragData>(
                      onWillAcceptWithDetails: (details) => switch (details.data) {
                        NotesDragData() => true,
                        FolderDragData(:final folderId) =>
                          !FolderTree.isProtected(folderId),
                      },
                      onAcceptWithDetails: (details) {
                        switch (details.data) {
                          case NotesDragData(:final noteIds):
                            trashNotes(context, ref, noteIds);
                          case FolderDragData(:final folderId):
                            // Same confirmation as the folder's Delete menu.
                            showDeleteFolderDialog(
                              context,
                              ref,
                              folderId: folderId,
                              folderName: tree[folderId]?.name ?? 'folder',
                            );
                        }
                      },
                      builder: (context, candidates, _) => _NavItem(
                        materialIcon: Icons.delete_outline,
                        label: 'Recently Deleted',
                        trailing: deletedCount > 0 ? '$deletedCount' : null,
                        selected: viewingTrash,
                        dropHighlight: candidates.isNotEmpty,
                        onTap: () {
                          ref.read(isViewingTrashProvider.notifier).enter();
                          ref.read(selectedFolderIdProvider.notifier).select(null);
                          ref.read(selectedTagIdProvider.notifier).clear();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSoft)),
            ),
            child: Row(
              children: [
                const Expanded(child: SyncStatusIndicator()),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const SettingsDialog(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 14,
                      color: colors.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Folders" heading: dropping a folder here puts it first at the top
/// level.
class _TopLevelDropTarget extends ConsumerWidget {
  const _TopLevelDropTarget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(folderTreeProvider);

    bool accepts(NooteDragData data) {
      if (data is! FolderDragData) return false;
      final id = data.folderId;
      final alreadyFirst =
          tree[id]?.parentId == null && tree.roots.firstOrNull?.id == id;
      return tree.canMove(id, into: null) && !alreadyFirst;
    }

    return DragTarget<NooteDragData>(
      onWillAcceptWithDetails: (details) => accepts(details.data),
      onAcceptWithDetails: (details) => moveFolderTo(
        context,
        ref,
        (details.data as FolderDragData).folderId,
        parentId: null,
        index: 0,
      ),
      builder: (context, candidates, _) => Container(
        foregroundDecoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
        child: child,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.navSectionLabel.copyWith(
          color: context.nooteColors.textFaint,
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
    final colors = context.nooteColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AppIcon(AppIconName.add, size: 12, color: colors.textFaint),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    this.icon,
    this.materialIcon,
    required this.label,
    this.trailing,
    this.selected = false,
    this.depth = 0,
    this.onTap,
    this.dropHighlight = false,
    this.leading,
  }) : assert(icon != null || materialIcon != null);

  final AppIconName? icon;

  /// Used where no custom SVG exists (e.g. trash) instead of extending
  /// [AppIconName] for a single one-off row.
  final IconData? materialIcon;
  final String label;
  final String? trailing;
  final bool selected;
  final int depth;
  final VoidCallback? onTap;

  /// Something droppable is hovering over this row.
  final bool dropHighlight;

  /// Before the icon — a folder's show/hide-subfolders arrow.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final fg = selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: EdgeInsets.fromLTRB(8 + depth * 16, 6, 8, 6),
        decoration: BoxDecoration(
          color: dropHighlight
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : selected
              ? colors.activeBg
              : null,
          border: dropHighlight
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 2)],
            if (materialIcon != null)
              Icon(materialIcon, size: 14, color: fg.withValues(alpha: 0.85))
            else
              AppIcon(icon!, size: 14, color: fg.withValues(alpha: 0.85)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.navItem.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
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
