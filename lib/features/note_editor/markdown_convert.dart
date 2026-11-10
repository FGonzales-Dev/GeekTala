import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown → editor document, for pasting and importing Markdown.
///
/// appflowy_editor's own `markdownToDocument`, plus fenced code blocks,
/// which it silently drops (it has no parser for them). Empty Markdown
/// gives one empty line, like a new note (the editor needs a block to put
/// the cursor in).
Document noteMarkdownToDocument(String markdown) {
  final document = markdownToDocument(
    markdown,
    markdownParsers: const [_CodeBlockParser()],
  );
  if (document.root.children.isEmpty) {
    return Document.blank(withInitialText: true);
  }
  return document;
}

/// ```` ``` ```` / `~~~` blocks → one paragraph in inline `code` style.
/// The editor has no code block type yet (noote-plan.md Build Order step 4);
/// this is the same stand-in the demo content uses.
class _CodeBlockParser extends CustomMarkdownParser {
  const _CodeBlockParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') return [];
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return [
      paragraphNode(
        delta: code.isEmpty
            ? Delta()
            : (Delta()..insert(code, attributes: {'code': true})),
      ),
    ];
  }
}

/// Whether pasted [text] is clearly Markdown — not just text that happens
/// to contain a `*` or a number at the start of a line.
///
/// Any one strong sign is enough: a heading, a code fence, a checkbox, a
/// table, `**bold**` or a `[link](url)`. Weaker signs need company: two
/// list items or quote lines, or two of `` `code` ``/`~~strike~~`/
/// `__bold__`.
bool looksLikeMarkdown(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  var listItems = 0;
  var quoteLines = 0;
  for (final line in lines) {
    if (_heading.hasMatch(line) ||
        _fence.hasMatch(line) ||
        _checkbox.hasMatch(line) ||
        _tableDivider.hasMatch(line)) {
      return true;
    }
    if (_bullet.hasMatch(line) || _numbered.hasMatch(line)) listItems++;
    if (_quote.hasMatch(line)) quoteLines++;
  }
  if (_bold.hasMatch(text) || _link.hasMatch(text)) return true;
  final weakInline = [
    _inlineCode,
    _strike,
    _underscoreBold,
  ].fold<int>(0, (sum, pattern) => sum + pattern.allMatches(text).length);
  return listItems >= 2 || quoteLines >= 2 || weakInline >= 2;
}

final _heading = RegExp(r'^ {0,3}#{1,6}[ \t]+\S');
final _fence = RegExp(r'^ {0,3}(```|~~~)');
final _checkbox = RegExp(r'^\s*[-*+][ \t]+\[[ xX]\][ \t]');
final _tableDivider = RegExp(
  r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
);
final _bullet = RegExp(r'^\s*[-*+][ \t]+\S');
final _numbered = RegExp(r'^\s*\d{1,9}[.)][ \t]+\S');
final _quote = RegExp(r'^ {0,3}>');
final _bold = RegExp(r'\*\*[^*\s][^*\n]*\*\*');
final _link = RegExp(r'\[[^\]\n]+\]\([^)\s]+\)');
final _inlineCode = RegExp(r'`[^`\n]+`');
final _strike = RegExp(r'~~[^~\n]+~~');
final _underscoreBold = RegExp(r'__[^_\s][^_\n]*__');
