import 'package:freezed_annotation/freezed_annotation.dart';

import 'title_style_run.dart';

part 'note.freezed.dart';

@freezed
sealed class Note with _$Note {
  const Note._();

  const factory Note({
    required String id,
    required String title,
    required List<TitleStyleRun> titleStyle,
    String? folderId,
    required Map<String, dynamic> body,
    required List<String> tagIds,
    required List<String> collaboratorInitials,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Note;

  /// Derived from [body] (appflowy_editor's document JSON — first body
  /// node with real text, truncated) rather than stored, so it can't drift
  /// out of sync with the real content. Headings are skipped: they're a
  /// label for the section, not a preview of what's in it.
  String get previewText {
    final children = (body['document'] as Map?)?['children'] as List?;
    if (children == null) return '';

    for (final child in children) {
      final node = child as Map;
      if (node['type'] == 'heading') continue;
      final delta = (node['data'] as Map?)?['delta'] as List?;
      if (delta == null) continue;
      final text = delta
          .map((op) => (op as Map)['insert'] as String? ?? '')
          .join();
      if (text.isNotEmpty) {
        return text.length > 140 ? '${text.substring(0, 140)}…' : text;
      }
    }
    return '';
  }

  /// Every bit of text in [body], recursively — unlike [previewText], this
  /// doesn't stop at the first match or skip headings; it's built for
  /// substring search (see `filterNotesByQuery`), not display.
  String get bodyPlainText {
    final buffer = StringBuffer();

    void walk(Map node) {
      final delta = (node['data'] as Map?)?['delta'] as List?;
      if (delta != null) {
        for (final op in delta) {
          final insert = (op as Map)['insert'];
          if (insert is String) buffer.write(insert);
        }
        buffer.write(' ');
      }
      final children = node['children'] as List?;
      if (children != null) {
        for (final child in children) {
          walk(child as Map);
        }
      }
    }

    final children = (body['document'] as Map?)?['children'] as List?;
    if (children != null) {
      for (final child in children) {
        walk(child as Map);
      }
    }
    return buffer.toString();
  }
}

/// Case-insensitive substring match over both title and full body text.
List<Note> filterNotesByQuery(List<Note> notes, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return notes;
  return notes
      .where(
        (n) =>
            n.title.toLowerCase().contains(needle) ||
            n.bodyPlainText.toLowerCase().contains(needle),
      )
      .toList();
}
