import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/features/note_editor/clipboard_html.dart';
import 'package:noote/features/note_editor/html_convert.dart';

import 'support/clipboard_html_samples.dart';

List<String> types(List<Node> nodes) => [for (final n in nodes) n.type];
List<String> texts(List<Node> nodes) => [
  for (final n in nodes) n.delta?.toPlainText() ?? '',
];

/// [delta]'s runs as [text, attributes] pairs (lists, which `expect`
/// compares deeply).
List<List<Object>> runs(Delta? delta) => [
  for (final op in delta ?? Delta())
    if (op is TextInsert)
      [
        op.text,
        <String, dynamic>{...?op.attributes},
      ],
];

Map<String, dynamic> attributesOf(List<Object> run) =>
    run[1] as Map<String, dynamic>;

List<Node> convert(String html) => htmlToNoteNodes(html);

void main() {
  group('clipboardHtmlFragment', () {
    test('takes the copied part out of Windows "HTML Format"', () {
      final html = clipboardHtmlFragment(claudeCodeCopy)!;
      expect(html, startsWith('<p style='));
      expect(html, endsWith('<br class="Apple-interchange-newline">'));
      expect(html, isNot(contains('\u0000')));
      expect(html, isNot(contains('Version:')));
    });

    test('uses the byte offsets when there are no markers', () {
      const fragment = '<p>Café <b>crème</b></p>';
      const head = '<html><body>';
      String header(int start, int end) =>
          'Version:0.9\r\nStartFragment:${'$start'.padLeft(10, '0')}\r\n'
          'EndFragment:${'$end'.padLeft(10, '0')}\r\n';
      final length = header(0, 0).length; // all ASCII
      final start = length + head.length;
      final end = start + utf8.encode(fragment).length;
      final raw = '${header(start, end)}$head$fragment</body></html>';
      expect(clipboardHtmlFragment(raw), fragment);
    });

    test('leaves other HTML as it is', () {
      expect(clipboardHtmlFragment('<p>Hi</p>'), '<p>Hi</p>');
      expect(clipboardHtmlFragment(null), isNull);
    });
  });

  group('a Claude Code answer', () {
    late List<Node> nodes;
    setUp(() => nodes = convert(clipboardHtmlFragment(claudeCodeCopy)!));

    test('keeps paragraphs, the table and the bullets', () {
      expect(types(nodes), [
        'paragraph',
        'paragraph',
        'paragraph',
        'paragraph',
        'table',
        'paragraph',
        'paragraph',
        'bulleted_list',
        'bulleted_list',
        'bulleted_list',
        'paragraph',
        'bulleted_list',
      ]);
      expect(
        texts(nodes)[1],
        'What prd has: the whole app (domains, picklists, data views, '
        'reports, app pages, both apps, roles and reference data), the 8 '
        'projects with their setup, 29 users with roles and memberships, '
        'and 15 signatures.',
      );
      expect(htmlHasFormatting(nodes), isTrue);
    });

    test('bolds only what was bold', () {
      expect(runs(nodes[1].delta).first, [
        'What prd has:',
        {'bold': true},
      ]);
      expect(attributesOf(runs(nodes[1].delta)[1]), isEmpty);
      expect(runs(nodes[2].delta), [
        [
          "What's left",
          {'bold': true},
        ],
      ]);
    });

    test('keeps code as code, asterisks and all', () {
      final secrets = nodes[7];
      expect(
        secrets.delta!.toPlainText(),
        'the vendor secrets in prd: app-envdaily-hydrovu-*, '
        'app-envdaily-wqdatalive-api-key and app-envdaily-ecomzen-*;',
      );
      expect(
        runs(secrets.delta)
            .where((r) => attributesOf(r)['code'] == true)
            .map((r) => r[0]),
        [
          'app-envdaily-hydrovu-*',
          'app-envdaily-wqdatalive-api-key',
          'app-envdaily-ecomzen-*',
        ],
      );
      expect(texts(nodes)[5], contains('the 6_dredge, 7_monitoring and'));
    });

    test('makes the table 2 columns by 4 rows, header first', () {
      final table = TableNode(node: nodes[4]);
      expect(table.colsLen, 2);
      expect(table.rowsLen, 4);
      String cell(int col, int row) =>
          table.getCell(col, row).children.single.delta!.toPlainText();
      expect([cell(0, 0), cell(1, 0)], ['Setting', 'Projects']);
      expect(
        cell(1, 1),
        'Fountain Lake, Kalamazoo, Lake Pepin, Penobscot, Torch Lake, Weigand',
      );
      expect(cell(0, 3), 'Placement chart');
      // Header cells are bold, like on screen.
      expect(runs(table.getCell(0, 0).children.single.delta).single[1], {
        'bold': true,
      });
      // Long text widens its column, up to a limit.
      expect(table.getColWidth(1), 320);
    });

    test("leaves out the page's colors and fonts", () {
      const allowed = {'bold', 'italic', 'underline', 'strikethrough', 'code'};
      void check(Node node) {
        for (final run in runs(node.delta)) {
          expect(
            allowed.containsAll(attributesOf(run).keys),
            isTrue,
            reason: '$run',
          );
        }
        node.children.forEach(check);
      }

      nodes.forEach(check);
    });
  });

  test('lists: start number, nesting and checkboxes', () {
    final nodes = convert(
      '<ol start="2"><li><p>Live monitoring</p>'
      '<ul><li>secrets</li><li>a schedule</li></ul></li>'
      '<li>Small items</li></ol>'
      '<ul><li><input type="checkbox" checked disabled> done</li>'
      '<li><input type="checkbox"> to do</li></ul>',
    );
    expect(types(nodes), [
      'numbered_list',
      'numbered_list',
      'todo_list',
      'todo_list',
    ]);
    expect(nodes[0].attributes['number'], 2);
    expect(texts(nodes[0].children.toList()), ['secrets', 'a schedule']);
    expect(types(nodes[0].children.toList()), [
      'bulleted_list',
      'bulleted_list',
    ]);
    expect(texts(nodes).sublist(2), ['done', 'to do']);
    expect(nodes[2].attributes['checked'], isTrue);
    expect(nodes[3].attributes['checked'], isFalse);
  });

  test('headings, quotes, dividers and links', () {
    final nodes = convert(
      '<h2>Plan</h2><blockquote><p>Quoted</p><p>more</p></blockquote><hr>'
      '<p><a href="https://example.com">site</a> and '
      '<a href="javascript:alert(1)">not a link</a></p>',
    );
    expect(types(nodes), ['heading', 'quote', 'divider', 'paragraph']);
    expect(nodes[0].attributes['level'], 2);
    expect(texts(nodes)[1], 'Quoted');
    expect(texts(nodes[1].children.toList()), ['more']);
    expect(runs(nodes[3].delta), [
      [
        'site',
        {'href': 'https://example.com'},
      ],
      [' and not a link', <String, dynamic>{}],
    ]);
  });

  test('line breaks and spaces, as a browser shows them', () {
    final nodes = convert(
      '<p>one<br>two</p><p><br></p>'
      '<p>\n   spaced   \n out  </p>'
      '<div style="white-space: pre-wrap">kept  spaces\nnext line</div>',
    );
    expect(texts(nodes), [
      'one',
      'two',
      '',
      'spaced out',
      'kept  spaces',
      'next line',
    ]);
  });

  test('code blocks: one code-styled paragraph, without the Copy button', () {
    final nodes = convert(
      '<p>Run:</p><div class="code"><button>Copy</button>'
      '<pre><code><span class="k">final</span> x = 1;\n'
      'print(x);\n</code></pre></div>',
    );
    expect(types(nodes), ['paragraph', 'paragraph']);
    expect(runs(nodes[1].delta), [
      ['final x = 1;\nprint(x);', {'code': true}],
    ]);
  });

  test('Google Docs: bold only where it says so', () {
    final nodes = convert(googleDocsCopy);
    expect(runs(nodes.single.delta), [
      ['Plain then ', <String, dynamic>{}],
      [
        'bold',
        {'bold': true},
      ],
      [
        ' and italic',
        {'italic': true},
      ],
    ]);
    expect(htmlHasFormatting(nodes), isTrue);
  });

  test('tables: spans padded, one-column layout tables unwrapped', () {
    final wide = convert(
      '<table><tr><td colspan="2">Both</td></tr><tr><td>a</td><td>b</td>'
      '</tr></table>',
    );
    final table = TableNode(node: wide.single);
    expect([table.colsLen, table.rowsLen], [2, 2]);
    expect(table.getCell(1, 0).children.single.delta!.toPlainText(), '');
    expect(table.getColWidth(1), 80); // short text: the narrowest

    final layout = convert(
      '<table><tr><td><h1>News</h1><p>Hello</p></td></tr></table>',
    );
    expect(types(layout), ['heading', 'paragraph']);
  });

  group('htmlHasFormatting', () {
    test('no for plain text, all code, or a code editor', () {
      expect(htmlHasFormatting(convert('<span>Just text</span>')), isFalse);
      expect(htmlHasFormatting(convert('<p>One</p><p>Two</p>')), isFalse);
      expect(
        htmlHasFormatting(convert('<pre><code># Title</code></pre>')),
        isFalse,
      );
      final vsCode = convert(vsCodeEditorCopy);
      expect(htmlHasFormatting(vsCode), isFalse);
      expect(texts(vsCode), ['## Also\n- **ripe** tomatoes\n\n- bread']);
    });

    test('yes for structure or formatting', () {
      expect(htmlHasFormatting(convert('<ul><li>a</li></ul>')), isTrue);
      expect(htmlHasFormatting(convert('<p>a <em>b</em></p>')), isTrue);
      expect(htmlHasFormatting(convert('<p>use <code>x</code></p>')), isTrue);
    });
  });
}
