import 'package:flutter/material.dart';

import '../../../data/models/title_style_run.dart';

/// Per-character formatting, mirrored 1:1 against [TextEditingController]'s
/// plain `text` by index. Kept as a flat array (not compressed runs) while
/// editing — title strings are short, so an O(n) rebuild per keystroke is
/// cheap, and it sidesteps range-splitting logic entirely: any insert or
/// delete just shifts/copies array slots. Compressed into [TitleStyleRun]s
/// only when reading out for persistence via [runs].
class StyledTitleController extends TextEditingController {
  StyledTitleController({required String text, List<TitleStyleRun> runs = const []})
    : _charStyles = _expand(text, runs),
      super(text: text);

  List<_CharStyle?> _charStyles;

  static List<_CharStyle?> _expand(String text, List<TitleStyleRun> runs) {
    final styles = List<_CharStyle?>.filled(text.length, null);
    for (final run in runs) {
      final style = _CharStyle(
        bold: run.bold,
        italic: run.italic,
        underline: run.underline,
        color: run.color,
      );
      for (var i = run.start; i < run.end && i < text.length; i++) {
        styles[i] = style;
      }
    }
    return styles;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldText = text;
    final newText = newValue.text;
    if (oldText != newText) {
      _charStyles = _diffApply(oldText, newText, _charStyles);
    }
    super.value = newValue;
  }

  static List<_CharStyle?> _diffApply(
    String oldText,
    String newText,
    List<_CharStyle?> oldStyles,
  ) {
    var prefix = 0;
    final minLen = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < minLen && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    // Style new characters like the one immediately before the insertion
    // point (typing at the end of a bold word stays bold), or unstyled at
    // the very start of the field.
    final insertStyle = prefix > 0 ? oldStyles[prefix - 1] : null;
    return [
      ...oldStyles.sublist(0, prefix),
      for (var i = prefix; i < newEnd; i++) insertStyle,
      ...oldStyles.sublist(oldEnd),
    ];
  }

  bool get _hasSelection => selection.isValid && !selection.isCollapsed;

  bool _selectionAllSatisfy(bool Function(_CharStyle?) test) {
    for (var i = selection.start; i < selection.end; i++) {
      if (!test(_charStyles[i])) return false;
    }
    return true;
  }

  void _mapSelection(_CharStyle? Function(_CharStyle?) transform) {
    if (!_hasSelection) return;
    for (var i = selection.start; i < selection.end; i++) {
      _charStyles[i] = transform(_charStyles[i]);
    }
    notifyListeners();
  }

  bool get selectionIsBold =>
      _hasSelection && _selectionAllSatisfy((s) => s?.bold ?? false);
  bool get selectionIsItalic =>
      _hasSelection && _selectionAllSatisfy((s) => s?.italic ?? false);
  bool get selectionIsUnderline =>
      _hasSelection && _selectionAllSatisfy((s) => s?.underline ?? false);

  void toggleBold() {
    final allBold = selectionIsBold;
    _mapSelection((s) => (s ?? const _CharStyle()).copyWith(bold: !allBold));
  }

  void toggleItalic() {
    final allItalic = selectionIsItalic;
    _mapSelection(
      (s) => (s ?? const _CharStyle()).copyWith(italic: !allItalic),
    );
  }

  void toggleUnderline() {
    final allUnderline = selectionIsUnderline;
    _mapSelection(
      (s) => (s ?? const _CharStyle()).copyWith(underline: !allUnderline),
    );
  }

  /// `null` clears the color back to the default.
  void applyColor(String? hex) {
    _mapSelection((s) => (s ?? const _CharStyle()).copyWith(color: hex));
  }

  /// Compressed for storage — only non-default runs are kept, so a plain
  /// title round-trips to `[]`.
  List<TitleStyleRun> get runs {
    final result = <TitleStyleRun>[];
    var i = 0;
    while (i < text.length) {
      final style = _charStyles[i];
      var j = i + 1;
      while (j < text.length && _charStyles[j] == style) {
        j++;
      }
      if (style != null) {
        result.add(
          TitleStyleRun(
            start: i,
            end: j,
            bold: style.bold,
            italic: style.italic,
            underline: style.underline,
            color: style.color,
          ),
        );
      }
      i = j;
    }
    return result;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    return TextSpan(style: base, children: buildStyledTitleSpans(text, runs, base));
  }
}

@immutable
class _CharStyle {
  const _CharStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final String? color;

  _CharStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    Object? color = _unset,
  }) => _CharStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    color: identical(color, _unset) ? this.color : color as String?,
  );

  static const _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is _CharStyle &&
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      color == other.color;

  @override
  int get hashCode => Object.hash(bold, italic, underline, color);
}
