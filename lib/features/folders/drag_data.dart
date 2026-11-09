import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_icon.dart';

/// What's being dragged between the notes list and the folder tree.
sealed class NooteDragData {
  const NooteDragData();
}

/// One or more notes from the desktop notes list.
class NotesDragData extends NooteDragData {
  const NotesDragData({required this.noteIds, required this.folderIds});

  final List<String> noteIds;

  /// The folders those notes are in now. A folder they're all already in
  /// isn't a drop target.
  final Set<String?> folderIds;
}

/// A folder from the desktop sidebar.
class FolderDragData extends NooteDragData {
  const FolderDragData(this.folderId);

  final String folderId;
}

/// What follows the pointer while dragging: the item's name, plus a count
/// when several notes are dragged together.
class DragFeedbackChip extends StatelessWidget {
  const DragFeedbackChip({
    super.key,
    required this.label,
    required this.icon,
    this.count = 1,
  });

  final String label;
  final AppIconName icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    // The pointer sits at the chip's top-left corner; nudge the chip off it
    // so the cursor doesn't cover the label.
    return Transform.translate(
      offset: const Offset(14, 10),
      child: Material(
        elevation: 6,
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 13, color: colors.textFaint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.navItem.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (count > 1) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
