import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/tags_providers.dart';
import '../../folders/widgets/folder_name_dialog.dart';
import '../../folders/widgets/folder_tree_node.dart';
import '../../settings/widgets/settings_dialog.dart';
import '../providers/is_viewing_trash_provider.dart';
import '../providers/pane_widths_provider.dart';
import '../providers/selected_folder_provider.dart';
import '../providers/selected_tag_provider.dart';

/// `.sidebar` — folder tree, tags, footer sync status. Desktop/web only.
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
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                  for (final folder in folders.where((f) => f.parentId == null))
                    FolderTreeNode(
                      folder: folder,
                      allFolders: folders,
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
                      }) {
                        return _NavItem(
                          icon: AppIconName.folder,
                          label: folder.name,
                          trailing: '$noteCount',
                          selected: selected,
                          depth: depth,
                          onTap: onTap,
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
                    _NavItem(
                      icon: AppIconName.tag,
                      label: tag.name,
                      selected: tag.id == selectedTagId,
                      onTap: () {
                        ref.read(selectedTagIdProvider.notifier).toggle(tag.id);
                        ref.read(selectedFolderIdProvider.notifier).select(null);
                        ref.read(isViewingTrashProvider.notifier).exit();
                      },
                    ),
                  const SizedBox(height: 6),
                  _NavItem(
                    materialIcon: Icons.delete_outline,
                    label: 'Recently Deleted',
                    trailing: deletedCount > 0 ? '$deletedCount' : null,
                    selected: viewingTrash,
                    onTap: () {
                      ref.read(isViewingTrashProvider.notifier).enter();
                      ref.read(selectedFolderIdProvider.notifier).select(null);
                      ref.read(selectedTagIdProvider.notifier).clear();
                    },
                  ),
                ],
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
          color: selected ? colors.activeBg : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
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
