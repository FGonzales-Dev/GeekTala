import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/breakpoints.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/models/folder_tree.dart';

/// Where to move notes or a folder: a dialog on desktop, a bottom sheet on
/// mobile (where notes and folders are on separate tabs, so there's no
/// dragging between them). Returns the chosen folder — `(folderId: null)`
/// for the top level — or null if cancelled.
///
/// Folders [isAllowed] rejects are shown greyed out.
Future<({String? folderId})?> showMoveToFolderPicker(
  BuildContext context, {
  required String title,
  required FolderTree tree,
  required bool Function(String? folderId) isAllowed,
  bool offerTopLevel = false,
}) {
  final list = _FolderPickerList(
    tree: tree,
    isAllowed: isAllowed,
    offerTopLevel: offerTopLevel,
  );

  if (isDesktop(context)) {
    return showDialog<({String? folderId})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.normal),
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 340,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: list,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  return showModalBottomSheet<({String? folderId})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: list,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FolderPickerList extends StatelessWidget {
  const _FolderPickerList({
    required this.tree,
    required this.isAllowed,
    required this.offerTopLevel,
  });

  final FolderTree tree;
  final bool Function(String? folderId) isAllowed;
  final bool offerTopLevel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        if (offerTopLevel)
          _PickerRow(
            icon: Icons.vertical_align_top,
            label: 'Top level',
            depth: 0,
            enabled: isAllowed(null),
            onTap: () => Navigator.of(context).pop((folderId: null)),
          ),
        for (final (:folder, :depth) in tree.flatten())
          _PickerRow(
            label: folder.name,
            depth: depth,
            enabled: isAllowed(folder.id),
            onTap: () => Navigator.of(context).pop((folderId: folder.id)),
          ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    this.icon,
    required this.label,
    required this.depth,
    required this.enabled,
    required this.onTap,
  });

  /// Defaults to the folder icon.
  final IconData? icon;
  final String label;
  final int depth;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final fg = enabled
        ? theme.colorScheme.onSurface
        : colors.textFaint.withValues(alpha: 0.6);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10 + depth * 18.0, 9, 10, 9),
        child: Row(
          children: [
            if (icon != null)
              Icon(icon, size: 15, color: fg)
            else
              AppIcon(AppIconName.folder, size: 15, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.navItem.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
