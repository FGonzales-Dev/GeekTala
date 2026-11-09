import 'note.dart';
import 'tag.dart';

/// The words of a search box query, lowercased. A word starting with `#`
/// (like `#ideas`) only matches tag names.
List<String> searchTerms(String query) => [
  for (final word in query.toLowerCase().split(RegExp(r'\s+')))
    if (word.isNotEmpty && word != '#') word,
];

/// The words to highlight in titles and text: the [searchTerms] that
/// aren't tag-only.
List<String> highlightTerms(String query) => [
  for (final term in searchTerms(query))
    if (!term.startsWith('#')) term,
];

/// Notes containing every word of [query], in any order, in the title, the
/// text, or a tag name. Notes whose title has every (non-tag) word come
/// first; otherwise [notes]' order is kept.
List<Note> searchNotes(
  List<Note> notes,
  String query, {
  Map<String, Tag> tagsById = const {},
}) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return notes;
  final textTerms = [
    for (final t in terms)
      if (!t.startsWith('#')) t,
  ];

  final titleMatches = <Note>[];
  final otherMatches = <Note>[];
  for (final note in notes) {
    final title = note.title.toLowerCase();
    final tags = [
      for (final id in note.tagIds) tagsById[id]?.name.toLowerCase() ?? '',
    ];
    String? body; // only built if the title and tags don't settle it
    bool matches(String term) {
      if (term.startsWith('#')) {
        final name = term.substring(1);
        return tags.any((tag) => tag.contains(name));
      }
      if (title.contains(term) || tags.any((tag) => tag.contains(term))) {
        return true;
      }
      return (body ??= note.bodyPlainText.toLowerCase()).contains(term);
    }

    if (!terms.every(matches)) continue;
    final inTitle = textTerms.isNotEmpty && textTerms.every(title.contains);
    (inTitle ? titleMatches : otherMatches).add(note);
  }
  return [...titleMatches, ...otherMatches];
}

/// A preview of [text] around the first of [terms] in it, so a match deep
/// in a note is visible in the list. Null if none of [terms] is in [text].
String? searchSnippet(String text, List<String> terms, {int length = 140}) {
  final lower = text.toLowerCase();
  var first = -1;
  for (final term in terms) {
    final at = lower.indexOf(term);
    if (at >= 0 && (first < 0 || at < first)) first = at;
  }
  if (first < 0) return null;

  // Start a little before the match, at a word boundary.
  var start = first <= 40 ? 0 : text.lastIndexOf(' ', first - 30) + 1;
  if (start < 0 || start > first) start = first;
  final end = (start + length).clamp(0, text.length);
  final snippet = text.substring(start, end).trim();
  return '${start > 0 ? '…' : ''}$snippet${end < text.length ? '…' : ''}';
}
