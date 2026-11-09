import 'package:flutter/material.dart';

/// Background for search matches in the notes list.
const searchHighlightColor = Color(0x59FFC107); // amber, ~35%

/// Splits [spans] so every case-insensitive occurrence of [terms] gets a
/// [searchHighlightColor] background, keeping each span's own style.
List<TextSpan> highlightMatches(List<TextSpan> spans, List<String> terms) {
  if (terms.isEmpty) return spans;
  final text = spans.map((s) => s.text ?? '').join();
  final lower = text.toLowerCase();

  // Which characters are part of a match.
  final hit = List.filled(text.length, false);
  for (final term in terms) {
    if (term.isEmpty) continue;
    for (
      var at = lower.indexOf(term);
      at >= 0;
      at = lower.indexOf(term, at + 1)
    ) {
      for (var i = at; i < at + term.length && i < hit.length; i++) {
        hit[i] = true;
      }
    }
  }
  if (!hit.contains(true)) return spans;

  final result = <TextSpan>[];
  var offset = 0;
  for (final span in spans) {
    final spanText = span.text ?? '';
    var i = 0;
    while (i < spanText.length) {
      final highlighted = hit[offset + i];
      var j = i + 1;
      while (j < spanText.length && hit[offset + j] == highlighted) {
        j++;
      }
      result.add(
        TextSpan(
          text: spanText.substring(i, j),
          style: highlighted
              ? (span.style ?? const TextStyle()).copyWith(
                  backgroundColor: searchHighlightColor,
                )
              : span.style,
        ),
      );
      i = j;
    }
    offset += spanText.length;
  }
  return result;
}
