import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/features/note_editor/markdown_convert.dart';
import 'package:noote/features/note_editor/markdown_paste.dart';

const sample = '''# Shopping
Get **oat milk** and [coffee](https://example.com).

- basil
- parmesan

```
final x = 1;
print(x);
```''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('looksLikeMarkdown', () {
    test('recognises Markdown', () {
      for (final text in [
        '# Heading',
        '## Notes\nsome text',
        '```\ncode\n```',
        '- [ ] task',
        '| a | b |\n|---|---|\n| 1 | 2 |',
        'Some **bold** words',
        'See [the docs](https://example.com)',
        '- one\n- two',
        '1. first\n2. second',
        '> quoted\n> still quoted',
        'use `a` and `b`',
      ]) {
        expect(looksLikeMarkdown(text), isTrue, reason: text);
      }
    });

    test('leaves ordinary text alone', () {
      for (final text in [
        'Just a sentence.',
        'https://example.com/page',
        'someone@example.com',
        '1. Only one numbered line',
        '- a single dash item',
        '#hashtag',
        'Price: 5 * 3 = 15',
        'one `code` mention',
        'Line one\nLine two',
      ]) {
        expect(looksLikeMarkdown(text), isFalse, reason: text);
      }
    });
  });

  test('the converter keeps fenced code blocks', () {
    final nodes = noteMarkdownToDocument(sample).root.children;
    expect(nodes.map((n) => n.type), [
      'heading',
      'paragraph',
      'bulleted_list',
      'bulleted_list',
      'paragraph',
    ]);
    final code = nodes.last.delta!.toJson().single as Map;
    expect(code['insert'], 'final x = 1;\nprint(x);');
    expect(code['attributes'], {'code': true});
  });

  group('MarkdownPaste', () {
    late EditorState editorState;
    late MarkdownPaste paste;
    var formattedByDefault = true;

    setUp(() {
      formattedByDefault = true;
      editorState = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(text: 'Before after')]),
      );
      paste = MarkdownPaste(
        editorState,
        formattedByDefault: () => formattedByDefault,
      );
      // Cursor between "Before " and "after".
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 7),
      );
    });

    tearDown(() {
      paste.dispose();
      editorState.dispose();
      AppFlowyClipboard.mockSetData(null);
    });

    List<String> types() => [
      for (final n in editorState.document.root.children) n.type,
    ];
    List<String> texts() => [
      for (final n in editorState.document.root.children)
        n.delta?.toPlainText() ?? '',
    ];

    Future<void> pressPaste() async {
      final shortcut = paste.commandShortcutEvents.last;
      expect(shortcut.key, pasteCommand.key);
      shortcut.handler(editorState);
      await pumpEventQueue();
    }

    test('⌘V pastes Markdown formatted, and offers the raw text', () async {
      AppFlowyClipboard.mockSetData(AppFlowyClipboardData(text: sample));
      await pressPaste();

      expect(types(), [
        'heading',
        'paragraph',
        'bulleted_list',
        'bulleted_list',
        'paragraph',
      ]);
      // Merged into the paragraph that was there.
      expect(texts().first, 'Before Shopping');
      expect(texts().last, 'final x = 1;\nprint(x);after');
      expect(paste.lastPasteFormatted, isTrue);
    });

    test('swapping shows the Markdown text, and back again', () async {
      await paste.paste(sample, formatted: true);

      await paste.swap();
      expect(paste.lastPasteFormatted, isFalse);
      expect(types().toSet(), {'paragraph'});
      expect(texts(), [
        'Before # Shopping',
        'Get **oat milk** and [coffee](https://example.com).',
        '',
        '- basil',
        '- parmesan',
        '',
        '```',
        'final x = 1;',
        'print(x);',
        '```after',
      ]);

      await paste.swap();
      expect(paste.lastPasteFormatted, isTrue);
      expect(texts().first, 'Before Shopping');
      expect(types().first, 'heading');
    });

    test('pasted at the end of a line, Markdown starts a new line', () async {
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 12),
      );
      await paste.paste('## Also\n- bread', formatted: true);
      expect(types(), ['paragraph', 'heading', 'bulleted_list']);
      expect(texts(), ['Before after', 'Also', 'bread']);
      // Cursor after the pasted text.
      expect(editorState.selection!.end.path, [2]);

      await paste.swap();
      expect(texts(), ['Before after', '## Also', '- bread']);
    });

    test('the Settings preference decides how ⌘V pastes', () async {
      formattedByDefault = false;
      AppFlowyClipboard.mockSetData(AppFlowyClipboardData(text: '# Title'));
      await pressPaste();

      expect(texts(), ['Before # Titleafter']);
      expect(paste.lastPasteFormatted, isFalse);
    });

    test('ordinary text pastes as before, with nothing to swap', () async {
      AppFlowyClipboard.mockSetData(AppFlowyClipboardData(text: 'plain '));
      await pressPaste();

      expect(texts(), ['Before plain after']);
      expect(paste.lastPasteFormatted, isNull);
    });

    test('editing after a paste ends the offer', () async {
      await paste.paste(sample, formatted: true);
      expect(paste.lastPasteFormatted, isTrue);

      await editorState.insertTextAtCurrentSelection('!');
      expect(paste.lastPasteFormatted, isNull);
    });
  });
}
