import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Clipboard HTML → note blocks, for pasting text copied from web pages,
/// chat apps and documents with its formatting.
///
/// Keeps headings, lists (with checkboxes and nesting), quotes, tables,
/// code, dividers, and bold/italic/underline/strikethrough/code/links. Leaves
/// out colors, fonts and sizes (a page's colors would clash with the
/// note's theme) and pictures.
///
/// Our own converter rather than appflowy_editor's `htmlToDocument`, which
/// numbers `<thead>` and `<tbody>` rows separately (so the header row and
/// the first row collide), drops text beside formatting in table cells,
/// makes a whole span bold when only part of it is, and loses `<br>`,
/// `<pre>` and `<hr>`.
List<Node> htmlToNoteNodes(String html) {
  final body = html_parser.parse(html).body;
  if (body == null) return [];
  final nodes = _blocks(body.nodes, const _Flow());
  bool blank(Node n) => n.delta?.isEmpty == true && n.children.isEmpty;
  while (nodes.isNotEmpty && blank(nodes.first)) {
    nodes.removeAt(0);
  }
  while (nodes.isNotEmpty && blank(nodes.last)) {
    nodes.removeLast();
  }
  return nodes;
}

/// Whether pasting [nodes] (from [htmlToNoteNodes]) formatted keeps
/// anything a plain-text paste would lose: a heading, list, table…, or
/// bold, a link, code….
///
/// Not when everything is code: a selection inside one code block, or a
/// code editor's or terminal's copy (VS Code puts the raw text on the
/// clipboard as colored `white-space: pre` HTML). Those paste as text, so
/// Markdown copied from them is still recognised as Markdown.
bool htmlHasFormatting(List<Node> nodes) {
  var formatted = false;
  var allCode = true;
  void visit(Node node) {
    if (node.type != ParagraphBlockKeys.type) {
      formatted = true;
      allCode = false;
    }
    for (final op in node.delta ?? Delta()) {
      if (op is! TextInsert || op.text.trim().isEmpty) continue;
      final attributes = op.attributes ?? const {};
      if (attributes.isNotEmpty) formatted = true;
      if (attributes[AppFlowyRichTextKeys.code] != true) allCode = false;
    }
    node.children.forEach(visit);
  }

  nodes.forEach(visit);
  return formatted && !allCode;
}

/// The text of [nodes], one line per block: the plain version of an HTML
/// paste when the clipboard had no plain text.
String plainTextOfNodes(List<Node> nodes) {
  final lines = <String>[];
  void visit(Node node) {
    final delta = node.delta;
    if (delta != null) lines.add(delta.toPlainText());
    node.children.forEach(visit);
  }

  nodes.forEach(visit);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Walking the HTML
// ---------------------------------------------------------------------------

/// Inline formatting and whitespace rules in effect at a point in the HTML.
class _Flow {
  const _Flow({
    this.style = const {},
    this.keepSpaces = false,
    this.keepNewlines = false,
  });

  /// appflowy_editor text attributes (bold, italic, code, href…).
  final Attributes style;

  /// `white-space: pre-wrap` and the like: spaces and line breaks in the
  /// text are shown as typed.
  final bool keepSpaces;
  final bool keepNewlines;

  _Flow enter(dom.Element element) {
    final css = _css(element);
    final style = {...this.style};

    switch (element.localName) {
      case 'b' || 'strong' || 'th':
        style[AppFlowyRichTextKeys.bold] = true;
      case 'i' || 'em' || 'cite' || 'var' || 'dfn':
        style[AppFlowyRichTextKeys.italic] = true;
      case 'u' || 'ins':
        style[AppFlowyRichTextKeys.underline] = true;
      case 's' || 'strike' || 'del':
        style[AppFlowyRichTextKeys.strikethrough] = true;
      case 'code' || 'kbd' || 'samp' || 'tt':
        style[AppFlowyRichTextKeys.code] = true;
      case 'a':
        final href = element.attributes['href']?.trim();
        if (href != null && _linkSchemes.hasMatch(href)) {
          style[AppFlowyRichTextKeys.href] = href;
        }
    }

    // Inline CSS wins, as it does on screen. Google Docs, for one, wraps
    // everything in `<b style="font-weight:normal">` and marks bold text
    // with `font-weight:700`.
    final weight = _fontWeight(css['font-weight']);
    if (weight != null && weight >= 600) {
      style[AppFlowyRichTextKeys.bold] = true;
    } else if (weight != null && weight < 500) {
      style.remove(AppFlowyRichTextKeys.bold);
    }
    switch (css['font-style']) {
      case 'italic' || 'oblique':
        style[AppFlowyRichTextKeys.italic] = true;
      case 'normal':
        style.remove(AppFlowyRichTextKeys.italic);
    }
    final decoration = css['text-decoration-line'] ?? css['text-decoration'];
    if (decoration != null) {
      if (decoration.contains('underline')) {
        style[AppFlowyRichTextKeys.underline] = true;
      }
      if (decoration.contains('line-through')) {
        style[AppFlowyRichTextKeys.strikethrough] = true;
      }
      if (decoration.startsWith('none')) {
        style
          ..remove(AppFlowyRichTextKeys.underline)
          ..remove(AppFlowyRichTextKeys.strikethrough);
      }
    }

    final whiteSpace = css['white-space'];
    final collapse = css['white-space-collapse'];
    final keepsWhitespace =
        const {'pre-wrap', 'break-spaces'}.contains(whiteSpace) ||
        const {'preserve', 'break-spaces'}.contains(collapse);
    final keepsNewlines =
        keepsWhitespace ||
        whiteSpace == 'pre-line' ||
        collapse == 'preserve-breaks';
    final normal = whiteSpace == 'normal' || whiteSpace == 'nowrap';
    return _Flow(
      style: style,
      keepSpaces: normal ? false : (keepsWhitespace || keepSpaces),
      keepNewlines: normal ? false : (keepsNewlines || keepNewlines),
    );
  }
}

final _linkSchemes = RegExp(r'^(https?:|mailto:)', caseSensitive: false);

int? _fontWeight(String? value) => switch (value) {
  null => null,
  'bold' || 'bolder' => 700,
  'normal' || 'lighter' => 400,
  _ => int.tryParse(value),
};

/// Where the blocks found so far go, and the line of text being built.
class _Out {
  final nodes = <Node>[];
  final line = _Line();

  /// Ends the current line, if there is one, as a paragraph.
  void flush() {
    final delta = line.take();
    if (delta != null) nodes.add(paragraphNode(delta: delta));
  }
}

List<Node> _blocks(Iterable<dom.Node> domNodes, _Flow flow) {
  final out = _Out();
  for (final node in domNodes) {
    _visit(node, flow, out);
  }
  out.flush();
  return out.nodes;
}

void _visit(dom.Node node, _Flow flow, _Out out) {
  if (node is dom.Text) {
    if (!flow.keepNewlines) {
      out.line.add(node.text, flow.style, keepSpaces: flow.keepSpaces);
      return;
    }
    final lines = node.text.split(_newline);
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) out.flush();
      out.line.add(lines[i], flow.style, keepSpaces: flow.keepSpaces);
    }
    return;
  }
  if (node is! dom.Element) return; // comments
  final tag = node.localName ?? '';
  if (_skipped.contains(tag) || _hidden(node)) return;

  if (_isCode(node)) {
    out
      ..flush()
      ..nodes.addAll(_codeBlock(node));
    return;
  }

  final inner = flow.enter(node);
  switch (tag) {
    case 'br':
      // A <br> on its own (`<p><br></p>`, or the second of two) is an
      // empty line.
      if (out.line.isEmpty) {
        out.nodes.add(paragraphNode());
      } else {
        out.flush();
      }
      return;
    case 'hr':
      out
        ..flush()
        ..nodes.add(dividerNode());
      return;
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      out
        ..flush()
        ..nodes.addAll(_heading(node, int.parse(tag.substring(1)), inner));
      return;
    case 'ul' || 'ol' || 'menu':
      out
        ..flush()
        ..nodes.addAll(_list(node, inner));
      return;
    case 'li':
      // Outside a list.
      out
        ..flush()
        ..nodes.add(_listItem(node, inner, BulletedListBlockKeys.type));
      return;
    case 'blockquote':
      out.flush();
      final quote = _withFirstLine(_blocks(node.nodes, inner), quoteNode);
      if (quote != null) out.nodes.add(quote);
      return;
    case 'table':
      out
        ..flush()
        ..nodes.addAll(_table(node, inner));
      return;
  }

  final block =
      _blockTags.contains(tag) ||
      _blockDisplays.contains(_css(node)['display']);
  if (block) out.flush();
  for (final child in node.nodes) {
    _visit(child, inner, out);
  }
  if (block) out.flush();
}

final _newline = RegExp(r'\r\n?|\n');

/// Never pasted: page furniture, form controls, media and pictures.
const _skipped = {
  'head',
  'script',
  'style',
  'meta',
  'link',
  'title',
  'template',
  'noscript',
  'button',
  'input',
  'select',
  'option',
  'textarea',
  'svg',
  'math',
  'canvas',
  'iframe',
  'object',
  'embed',
  'video',
  'audio',
  'img',
  'picture',
  'source',
  'map',
  'area',
  'caption',
  'colgroup',
  'col',
};

/// Elements that start and end a line (the rest flow inline).
const _blockTags = {
  'address',
  'article',
  'aside',
  'body',
  'center',
  'dd',
  'details',
  'dialog',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'header',
  'hgroup',
  'html',
  'legend',
  'main',
  'nav',
  'p',
  'section',
  'summary',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
};

const _blockDisplays = {'block', 'flex', 'grid', 'list-item', 'table'};

bool _hidden(dom.Element element) =>
    element.attributes.containsKey('hidden') ||
    _css(element)['display'] == 'none';

/// `<pre>`, or anything shown like it (`white-space: pre`).
bool _isCode(dom.Element element) {
  if (const {
    'pre',
    'xmp',
    'listing',
    'plaintext',
  }.contains(element.localName)) {
    return true;
  }
  final css = _css(element);
  if (css['white-space'] == 'pre') return true;
  final wrap = css['text-wrap-mode'] ?? css['text-wrap'];
  return css['white-space-collapse'] == 'preserve' && wrap == 'nowrap';
}

/// The element's inline `style`, with lowercase names and values.
Map<String, String> _css(dom.Element element) {
  final style = element.attributes['style'];
  if (style == null || style.isEmpty) return const {};
  final css = <String, String>{};
  for (final declaration in style.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon <= 0) continue;
    final value = declaration
        .substring(colon + 1)
        .replaceAll('!important', '')
        .trim()
        .toLowerCase();
    css[declaration.substring(0, colon).trim().toLowerCase()] = value;
  }
  return css;
}

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------

Iterable<Node> _heading(dom.Element element, int level, _Flow flow) {
  final blocks = _blocks(element.nodes, flow);
  if (blocks.isEmpty) return const [];
  final first = blocks.first;
  if (first.type != ParagraphBlockKeys.type) return blocks;
  return [headingNode(level: level, delta: first.delta), ...blocks.skip(1)];
}

/// A block whose text is [blocks]' first paragraph, with the rest of
/// [blocks] under it (how list items and quotes hold more than a line).
Node? _withFirstLine(
  List<Node> blocks,
  Node Function({Delta? delta, Iterable<Node>? children}) make,
) {
  if (blocks.isEmpty) return null;
  final first = blocks.first;
  if (first.type == ParagraphBlockKeys.type) {
    return make(delta: first.delta, children: blocks.skip(1));
  }
  return make(delta: Delta(), children: blocks);
}

List<Node> _list(dom.Element element, _Flow flow) {
  final type = element.localName == 'ol'
      ? NumberedListBlockKeys.type
      : BulletedListBlockKeys.type;
  final start = int.tryParse(element.attributes['start']?.trim() ?? '');
  final items = <Node>[];
  for (final child in element.nodes) {
    if (child is dom.Element && child.localName == 'li') {
      items.add(
        _listItem(child, flow, type, number: items.isEmpty ? start : null),
      );
      continue;
    }
    // A list straight inside a list (no <li> around it), or stray text:
    // goes under the item before it.
    final extra = _blocks([child], flow);
    if (items.isEmpty) {
      items.addAll(extra);
    } else {
      extra.forEach(items.last.insert);
    }
  }
  return items;
}

Node _listItem(dom.Element li, _Flow flow, String type, {int? number}) {
  final checked = _checked(li);
  final blocks = _blocks(li.nodes, flow);
  Node make({Delta? delta, Iterable<Node>? children}) {
    if (checked != null) {
      return todoListNode(checked: checked, delta: delta, children: children);
    }
    if (type == NumberedListBlockKeys.type) {
      return numberedListNode(delta: delta, number: number, children: children);
    }
    return bulletedListNode(delta: delta, children: children);
  }

  return _withFirstLine(blocks, make) ?? make(delta: Delta());
}

/// Whether a checklist item is ticked (GitHub's `<input type=checkbox>`,
/// or `data-checked` from Tiptap and similar editors); null for an
/// ordinary list item.
bool? _checked(dom.Element li) {
  final data = li.attributes['data-checked'];
  if (data != null) return data == 'true';
  bool? find(dom.Element element) {
    for (final child in element.children) {
      final tag = child.localName;
      if (tag == 'ul' || tag == 'ol') continue; // a nested item's box
      if (tag == 'input' &&
          child.attributes['type']?.toLowerCase() == 'checkbox') {
        return child.attributes.containsKey('checked');
      }
      final found = find(child);
      if (found != null) return found;
    }
    return null;
  }

  return find(li);
}

/// A `<pre>` → one paragraph in inline `code` style, like a Markdown code
/// block (see `_CodeBlockParser` in markdown_convert.dart).
List<Node> _codeBlock(dom.Element element) {
  final text = StringBuffer();
  var last = '\n';
  void write(String s) {
    if (s.isEmpty) return;
    text.write(s);
    last = s[s.length - 1];
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      write(node.text.replaceAll('\r\n', '\n'));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (_skipped.contains(tag) || _hidden(node)) return; // e.g. "Copy"
    if (tag == 'br') {
      write('\n');
      return;
    }
    // Code editors put each line in its own <div>.
    final line = _blockTags.contains(tag) || tag == 'li';
    if (line && last != '\n') write('\n');
    node.nodes.forEach(walk);
    if (line && last != '\n') write('\n');
  }

  element.nodes.forEach(walk);
  var code = text.toString().replaceAll(' ', ' ');
  code = code
      .replaceFirst(RegExp(r'^\n'), '')
      .replaceFirst(RegExp(r'\n+$'), '');
  if (code.trim().isEmpty) return const [];
  return [
    paragraphNode(
      delta: Delta()
        ..insert(code, attributes: {AppFlowyRichTextKeys.code: true}),
    ),
  ];
}

List<Node> _table(dom.Element element, _Flow flow) {
  final rows = <dom.Element>[];
  void collect(dom.Element parent) {
    for (final child in parent.children) {
      switch (child.localName) {
        case 'tr':
          rows.add(child);
        case 'thead' || 'tbody' || 'tfoot':
          collect(child);
      }
    }
  }

  collect(element);
  final grid = <List<List<Node>>>[];
  for (final row in rows) {
    final cells = <List<Node>>[];
    for (final cell in row.children) {
      if (cell.localName != 'td' && cell.localName != 'th') continue;
      cells.add(_blocks(cell.nodes, flow.enter(cell)));
      final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
      for (var i = 1; i < math.min(span, 50); i++) {
        cells.add(const []);
      }
    }
    if (cells.isNotEmpty) grid.add(cells);
  }
  if (grid.isEmpty) return const [];

  final columns = grid.map((row) => row.length).reduce(math.max);
  // A one-column table is page layout, not data (e-mails and older sites
  // are built from them): keep what's in it, without the table.
  if (columns == 1) return [for (final row in grid) ...row.single];

  final table = TableNode.fromList<Node>([
    for (var c = 0; c < columns; c++)
      [
        for (final row in grid)
          paragraphNode(delta: c < row.length ? _oneLine(row[c]) : Delta()),
      ],
  ]).node;
  _fitColumns(table, columns);
  return [table];
}

/// A table cell holds one line: [blocks]' text joined by spaces.
Delta _oneLine(List<Node> blocks) {
  final delta = Delta();
  void add(Node node) {
    final text = node.delta;
    if (text != null && text.isNotEmpty) {
      if (delta.isNotEmpty) delta.insert(' ');
      for (final op in text) {
        if (op is TextInsert) delta.insert(op.text, attributes: op.attributes);
      }
    }
    node.children.forEach(add);
  }

  blocks.forEach(add);
  return delta;
}

/// Widens columns with long text (the default is 160 px for every
/// column), up to a limit so a table still fits beside the notes list.
void _fitColumns(Node table, int columns) {
  for (var c = 0; c < columns; c++) {
    final cells = [
      for (final cell in table.children)
        if (cell.attributes[TableCellBlockKeys.colPosition] == c) cell,
    ];
    final longest = cells
        .map((cell) => cell.children.firstOrNull?.delta?.length ?? 0)
        .fold(0, math.max);
    final width = (longest * 7.0 + 24).clamp(80.0, 320.0);
    for (final cell in cells) {
      cell.updateAttributes({TableCellBlockKeys.width: width});
    }
  }
}

// ---------------------------------------------------------------------------
// Lines of text
// ---------------------------------------------------------------------------

/// The text of one line, with its formatting, collapsing spaces the way a
/// browser shows them.
class _Line {
  final _parts = <(String, Attributes)>[];

  bool get isEmpty => _parts.isEmpty;

  void add(String text, Attributes style, {bool keepSpaces = false}) {
    if (!keepSpaces) {
      text = text.replaceAll(_spaces, ' ');
      if (text.startsWith(' ') &&
          (_parts.isEmpty || _parts.last.$1.endsWith(' '))) {
        text = text.substring(1);
      }
    }
    text = text.replaceAll(' ', ' ');
    if (text.isEmpty) return;
    _parts.add((text, style));
  }

  /// The line so far, without trailing spaces, and starts a new one.
  /// Null when there's no text.
  Delta? take() {
    while (_parts.isNotEmpty) {
      final (text, style) = _parts.last;
      final trimmed = text.trimRight();
      if (trimmed.isNotEmpty) {
        _parts.last = (trimmed, style);
        break;
      }
      _parts.removeLast();
    }
    if (_parts.isEmpty) return null;
    final delta = Delta();
    for (final (text, style) in _parts) {
      final attributes = {...style};
      // Links are underlined anyway.
      if (attributes.containsKey(AppFlowyRichTextKeys.href)) {
        attributes.remove(AppFlowyRichTextKeys.underline);
      }
      delta.insert(text, attributes: attributes.isEmpty ? null : attributes);
    }
    _parts.clear();
    return delta;
  }
}

final _spaces = RegExp(r'[ \t\r\n\f]+');
