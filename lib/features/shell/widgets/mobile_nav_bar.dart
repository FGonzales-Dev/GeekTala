import 'package:flutter/material.dart';

import '../../../core/router/navigation.dart';
import '../../../core/theme/app_colors.dart';

// The phone screens' shared pieces (noote-mobile-redesign.html): a top bar
// with Back and actions, a large title, grouped rows, and a bottom bar in
// place of tabs and a floating button.

/// Top bar: "‹ [backLabel]" on the left (when given) and [actions] on the
/// right.
class MobileNavBar extends StatelessWidget {
  const MobileNavBar({
    super.key,
    this.backLabel,
    this.onBack,
    this.actions = const [],
    this.middle,
  });

  final String? backLabel;

  /// Defaults to [goBack].
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// Shown between Back and the actions, e.g. the sync status.
  final Widget? middle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (backLabel != null)
            Flexible(
              child: Semantics(
                button: true,
                label: 'Back to $backLabel',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onBack ?? () => goBack(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_left,
                          size: 24,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        Flexible(
                          child: Text(
                            backLabel!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 12),
          const Spacer(),
          ?middle,
          ...actions,
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// An icon button for [MobileNavBar] and [MobileBottomBar].
class MobileBarButton extends StatelessWidget {
  const MobileBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 22,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: size,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      icon: Icon(icon),
    );
  }
}

/// The screen's big title, with an optional line under it ("83 notes").
class MobileLargeTitle extends StatelessWidget {
  const MobileLargeTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.15,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: context.nooteColors.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bar along the bottom: [leading] and [trailing] buttons with a short
/// status ([center]) between them.
class MobileBottomBar extends StatelessWidget {
  const MobileBottomBar({super.key, this.leading, this.center, this.trailing});

  final Widget? leading;
  final Widget? center;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooteColors;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: colors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 6),
              SizedBox(width: 48, child: leading),
              Expanded(
                child: Center(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: colors.textFaint,
                    ),
                    child: center ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              SizedBox(width: 48, child: trailing),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small uppercase label above a [MobileGroup] ("FOLDERS").
class MobileGroupLabel extends StatelessWidget {
  const MobileGroupLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 7),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.55,
          color: context.nooteColors.textFaint,
        ),
      ),
    );
  }
}

/// Rows in one rounded box, with hairlines between them.
class MobileGroup extends StatelessWidget {
  const MobileGroup({super.key, required this.children, this.dividers = true});

  final List<Widget> children;

  /// False when the rows draw their own ([MobileRow.topDivider]), e.g. a
  /// folder tree whose rows are nested.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: colors.borderSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0 && dividers)
              Divider(height: 1, thickness: 1, color: colors.borderSoft),
            child,
          ],
        ],
      ),
    );
  }
}

/// A row in a [MobileGroup]: optional disclosure ([leading]), icon, name,
/// count and a chevron. Tapping it opens what it names.
class MobileRow extends StatelessWidget {
  const MobileRow({
    super.key,
    this.leading,
    required this.icon,
    required this.label,
    this.count,
    this.depth = 0,
    this.selected = false,
    this.dropHighlight = false,
    required this.onTap,
    this.onLongPress,
    this.topDivider = false,
  });

  /// A hairline above the row, inside a `MobileGroup(dividers: false)`.
  final bool topDivider;

  /// E.g. the show/hide-subfolders arrow; a gap of the same width if null.
  final Widget? leading;
  final IconData icon;
  final String label;
  final int? count;
  final int depth;
  final bool selected;
  final bool dropHighlight;
  final VoidCallback onTap;
  final void Function(Offset position)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Material(
      color: dropHighlight || selected ? colors.activeBg : Colors.transparent,
      shape: topDivider
          ? Border(top: BorderSide(color: colors.borderSoft))
          : null,
      child: InkWell(
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: onLongPress == null
              ? null
              : (details) => onLongPress!(details.globalPosition),
          child: Padding(
            padding: EdgeInsets.fromLTRB(6 + depth * 18.0, 11, 10, 11),
            child: Row(
              children: [
                SizedBox(width: 26, child: Center(child: leading)),
                Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13.5,
                      color: colors.textFaint,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: colors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
