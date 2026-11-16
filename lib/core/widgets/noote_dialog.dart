import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/breakpoints.dart';

/// Colours the dialogs use that the theme doesn't name: the mockup's
/// `--bad` (destructive) and `--ok` (recommended, sync on).
abstract final class NooteStatusColors {
  static const danger = Color(0xFFC2553F);
  static const ok = Color(0xFF7C9A78);
}

/// Shows [builder]'s widget the Noote way: on desktop a centred window over
/// a dimmed app with a short fade-and-scale in; on phones a bottom sheet.
///
/// [builder] usually returns a [NooteDialog]; the Settings window returns
/// its own [NooteDialogSurface].
Future<T?> showNooteDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  if (!isDesktop(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SheetScope(
        child: Padding(
          // Above the keyboard.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: builder(context),
        ),
      ),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x520C0C0B),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: builder(context),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Marks content shown as a phone bottom sheet by [showNooteDialog].
class _SheetScope extends InheritedWidget {
  const _SheetScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetScope>() != null;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) => false;
}

/// The window itself: surface, border, rounded corners and shadow.
class NooteDialogSurface extends StatelessWidget {
  const NooteDialogSurface({
    super.key,
    required this.child,
    this.width = 420,
    this.height,
  });

  final Widget child;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.55 : 0.16),
                  blurRadius: 60,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One designed look for every dialog: icon, title and a one-line summary
/// at the top with a close button; then [body]; then a footer with a
/// keyboard [hint] (or a quiet [footerLeading] action) on the left and
/// [actions] on the right.
///
/// <kbd>Esc</kbd> closes it and <kbd>↵</kbd> runs [onSubmit] — from a text
/// field too, but not while a button has focus (Enter presses that button)
/// or while an input method is composing.
///
/// On phones ([showNooteDialog] shows it as a sheet) the actions become
/// full-width buttons, the main one first, and the hint is left out.
class NooteDialog extends StatefulWidget {
  const NooteDialog({
    super.key,
    this.icon,
    this.danger = false,
    required this.title,
    this.subtitle,
    this.body,
    this.actions = const [],
    this.hint,
    this.footerLeading,
    this.width = 420,
    this.onSubmit,
    this.autofocus = true,
  });

  final IconData? icon;

  /// Red icon tile, for deletes.
  final bool danger;
  final String title;
  final String? subtitle;
  final Widget? body;

  /// Left to right; the last one is the main action.
  final List<Widget> actions;
  final Widget? hint;

  /// A quiet action at the far left of the footer, e.g. "Sign out anyway".
  final Widget? footerLeading;
  final double width;
  final VoidCallback? onSubmit;

  /// Focus the dialog itself so <kbd>Esc</kbd>/<kbd>↵</kbd> work. Pass
  /// false when a text field in [body] autofocuses instead.
  final bool autofocus;

  @override
  State<NooteDialog> createState() => _NooteDialogState();
}

class _NooteDialogState extends State<NooteDialog> {
  final _focusNode = FocusNode(debugLabel: 'NooteDialog');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final submit = widget.onSubmit;
      if (submit == null) return KeyEventResult.ignored;
      final focused = FocusManager.instance.primaryFocus;
      if (focused != _focusNode) {
        final field = focused?.context
            ?.findAncestorStateOfType<EditableTextState>();
        // A focused button handles Enter itself.
        if (field == null) return KeyEventResult.ignored;
        final composing = field.textEditingValue.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
      }
      submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _SheetScope.of(context);
    final content = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            icon: widget.icon,
            danger: widget.danger,
            title: widget.title,
            subtitle: widget.subtitle,
            showClose: !sheet,
          ),
          if (widget.body != null)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: widget.body,
              ),
            ),
          if (sheet)
            _SheetFooter(actions: widget.actions, leading: widget.footerLeading)
          else
            _Footer(
              actions: widget.actions,
              hint: widget.hint,
              leading: widget.footerLeading,
              extraTop: widget.body == null,
            ),
        ],
      ),
    );
    if (sheet) return SafeArea(top: false, child: content);
    return NooteDialogSurface(width: widget.width, child: content);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.danger,
    required this.title,
    required this.subtitle,
    required this.showClose,
  });

  final IconData? icon;
  final bool danger;
  final String title;
  final String? subtitle;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, showClose ? 18 : 2, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: danger
                    ? NooteStatusColors.danger.withValues(alpha: 0.12)
                    : colors.activeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: danger
                    ? NooteStatusColors.danger
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          height: 1.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showClose)
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(Icons.close, color: colors.textFaint),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.actions,
    required this.hint,
    required this.leading,
    required this.extraTop,
  });

  final List<Widget> actions;
  final Widget? hint;
  final Widget? leading;
  final bool extraTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, extraTop ? 18 : 14, 18, 16),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (hint != null)
            Flexible(child: hint!),
          const Spacer(),
          for (final (i, action) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({required this.actions, required this.leading});

  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final buttons = [...actions.reversed, ?leading];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, button) in buttons.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _FullWidth(child: button),
          ],
        ],
      ),
    );
  }
}

/// Makes a [NooteButton] stretch, with a phone-sized tap target.
class _FullWidth extends InheritedWidget {
  const _FullWidth({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FullWidth>() != null;

  @override
  bool updateShouldNotify(_FullWidth oldWidget) => false;
}

enum NooteButtonStyle { primary, secondary, danger, quiet, quietDanger }

/// The dialogs' buttons: dark [NooteButtonStyle.primary], outlined
/// secondary, red danger, and borderless quiet ones.
class NooteButton extends StatelessWidget {
  const NooteButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.style = NooteButtonStyle.secondary,
    this.icon,
  });

  const NooteButton.primary(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
  }) : style = NooteButtonStyle.primary;

  const NooteButton.danger(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
  }) : style = NooteButtonStyle.danger;

  final String label;
  final VoidCallback? onPressed;
  final NooteButtonStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full = _FullWidth.of(context);
    final (Color bg, Color fg, Color border) = switch (style) {
      NooteButtonStyle.primary => (
        scheme.onSurface,
        theme.scaffoldBackgroundColor,
        scheme.onSurface,
      ),
      NooteButtonStyle.secondary => (
        scheme.surface,
        scheme.onSurface,
        scheme.outline,
      ),
      NooteButtonStyle.danger => (
        NooteStatusColors.danger,
        Colors.white,
        NooteStatusColors.danger,
      ),
      NooteButtonStyle.quiet => (
        Colors.transparent,
        scheme.onSurfaceVariant,
        Colors.transparent,
      ),
      NooteButtonStyle.quietDanger => (
        Colors.transparent,
        NooteStatusColors.danger,
        Colors.transparent,
      ),
    };
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledForegroundColor: fg,
          disabledBackgroundColor: bg,
          overlayColor: fg,
          minimumSize: Size(0, full ? 46 : 32),
          padding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical: full ? 12 : 7,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(full ? 10 : 8),
            side: BorderSide(color: border),
          ),
          textStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: full ? 14.5 : 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              // A long name ("Move to …") is cut short, not pushed out of
              // the dialog.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: full ? double.infinity : 200,
                ),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A choice shown as a card you click, with a radio dot. The safe choice
/// is preselected and can be marked [recommended].
class NooteOptionCard extends StatelessWidget {
  const NooteOptionCard({
    super.key,
    required this.selected,
    required this.title,
    this.description,
    this.recommended = false,
    this.danger = false,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String? description;
  final bool recommended;

  /// Red title, for the destructive choice.
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: Material(
          color: selected ? colors.activeBg : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.outline,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.onSurface
                              : colors.textFaint,
                          width: selected ? 5 : 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: title,
                            children: [
                              if (recommended)
                                const TextSpan(
                                  text: '  Recommended',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: NooteStatusColors.ok,
                                  ),
                                ),
                            ],
                          ),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: danger
                                ? NooteStatusColors.danger
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        if (description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              description!,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                height: 1.45,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded facts — "3 subfolders", "83 notes" — shown before you
/// confirm.
class NooteFacts extends StatelessWidget {
  const NooteFacts(this.facts, {super.key});

  final List<String> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final fact in facts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: colors.activeBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                fact,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A key in a [KeyHint].
class Kbd {
  const Kbd(this.key);

  final String key;
}

/// The footer's keyboard hint, e.g. `KeyHint([Kbd('Esc'), ' to cancel'])`.
/// Parts are [Kbd]s and plain strings.
class KeyHint extends StatelessWidget {
  const KeyHint(this.parts, {super.key});

  final List<Object> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final textStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11.5,
      color: colors.textFaint,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final part in parts)
            if (part is Kbd)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(4),
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outline),
                      left: BorderSide(color: theme.colorScheme.outline),
                      right: BorderSide(color: theme.colorScheme.outline),
                      bottom: BorderSide(
                        color: theme.colorScheme.outline,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    part.key,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              TextSpan(text: '$part'),
        ],
      ),
      style: textStyle,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The dialogs' text field: a thin outline that darkens, with a soft ring,
/// on focus; optionally a search icon in front.
class NooteField extends StatefulWidget {
  const NooteField({
    super.key,
    required this.controller,
    this.hint,
    this.search = false,
    this.autofocus = true,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.keepFocusOnSubmit = false,
  });

  /// Stay in the field (and keep a phone's keyboard up) after submitting,
  /// e.g. to add another tag.
  final bool keepFocusOnSubmit;

  final TextEditingController controller;
  final String? hint;
  final bool search;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  State<NooteField> createState() => _NooteFieldState();
}

class _NooteFieldState extends State<NooteField> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(NooteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocusNode)?.removeListener(_changed);
      _focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_changed);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.outline,
        ),
        boxShadow: [
          if (focused) BoxShadow(color: colors.activeBg, spreadRadius: 3),
        ],
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          if (widget.search) ...[
            Icon(Icons.search, size: 16, color: colors.textFaint),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              onEditingComplete: widget.keepFocusOnSubmit ? () {} : null,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  color: colors.textFaint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
