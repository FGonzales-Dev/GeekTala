import 'package:flutter/material.dart';

/// A run of inline formatting over `[start, end)` of a note's plain-text
/// title. Kept separate from the title string itself (which stays a plain
/// column, used as-is for sorting/search/previews) — this is an overlay,
/// not a source of truth for the text content.
@immutable
class TitleStyleRun {
  const TitleStyleRun({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  factory TitleStyleRun.fromJson(Map<String, dynamic> json) => TitleStyleRun(
    start: json['start'] as int,
    end: json['end'] as int,
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    underline: json['underline'] as bool? ?? false,
    color: json['color'] as String?,
  );

  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final bool underline;

  /// `#RRGGBB`, or `null` for the default text color.
  final String? color;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (underline) 'underline': true,
    if (color != null) 'color': color,
  };
}

/// Splits [text] into [TextSpan]s according to [runs], applying [base] plus
/// each run's style over its range. Used by both the editable title field
/// (via `StyledTitleController`) and read-only previews (note list tiles),
/// so the two never drift apart.
List<TextSpan> buildStyledTitleSpans(
  String text,
  List<TitleStyleRun> runs,
  TextStyle base,
) {
  if (text.isEmpty) return [TextSpan(text: text, style: base)];

  final styles = List<TitleStyleRun?>.filled(text.length, null);
  for (final run in runs) {
    for (var i = run.start; i < run.end && i < text.length; i++) {
      styles[i] = run;
    }
  }

  final spans = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    final run = styles[i];
    var j = i + 1;
    while (j < text.length && styles[j]?.color == run?.color && styles[j]?.bold == run?.bold && styles[j]?.italic == run?.italic && styles[j]?.underline == run?.underline) {
      j++;
    }
    spans.add(TextSpan(text: text.substring(i, j), style: _resolve(base, run)));
    i = j;
  }
  return spans;
}

TextStyle _resolve(TextStyle base, TitleStyleRun? run) {
  if (run == null) return base;
  return base.copyWith(
    fontWeight: run.bold ? FontWeight.w700 : null,
    fontStyle: run.italic ? FontStyle.italic : null,
    decoration: run.underline ? TextDecoration.underline : null,
    color: run.color != null
        ? Color(int.parse(run.color!.substring(1), radix: 16) | 0xFF000000)
        : null,
  );
}
