import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// `.tag-chip`
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.onRemove});

  final String label;

  /// Shows a small "x" affordance when set — used where tags are editable
  /// (the note editor's tag picker), omitted where they're read-only
  /// (note list tiles).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Container(
      padding: EdgeInsets.only(
        left: 6,
        right: onRemove != null ? 3 : 6,
        top: 1.5,
        bottom: 1.5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.tagChip.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 10,
                  color: colors.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
