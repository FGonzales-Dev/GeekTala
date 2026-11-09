import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/core/utils/search_highlight.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/models/note.dart';
import 'package:noote/data/models/note_search.dart';
import 'package:noote/data/models/tag.dart';
import 'package:noote/data/repositories/tags_repository.dart';

Note note(
  String id,
  String title,
  String body, {
  List<String> tags = const [],
}) {
  return Note(
    id: id,
    title: title,
    titleStyle: const [],
    body: {
      'document': {
        'type': 'page',
        'children': [
          {
            'type': 'paragraph',
            'data': {
              'delta': [
                {'insert': body},
              ],
            },
          },
        ],
      },
    },
    tagIds: tags,
    collaboratorInitials: const [],
    updatedAt: DateTime(2026, 11, 9),
  );
}

List<String> ids(List<Note> notes) => [for (final n in notes) n.id];

void main() {
  group('search', () {
    final tags = {
      't1': const Tag(id: 't1', name: 'recipes'),
      't2': const Tag(id: 't2', name: 'ideas'),
    };
    final notes = [
      note('a', 'Weekend plans', 'Buy coffee beans and basil', tags: ['t1']),
      note('b', 'Coffee beans', 'Ethiopian is best'),
      note('c', 'Sync design', 'Upload then download', tags: ['t2']),
    ];

    List<String> search(String q) => ids(searchNotes(notes, q, tagsById: tags));

    test('every word must match, in any order', () {
      expect(search('beans coffee'), ['b', 'a']);
      expect(search('basil coffee'), ['a']);
      expect(search('coffee download'), isEmpty);
    });

    test('notes with every word in the title come first', () {
      expect(search('coffee'), ['b', 'a']);
    });

    test('tag names are searched; #word only matches tags', () {
      expect(search('recipes'), ['a']);
      expect(search('#idea'), ['c']);
      expect(search('#sync'), isEmpty); // in a title, but not a tag
      expect(search('#ideas upload'), ['c']);
    });

    test('a blank query matches everything', () {
      expect(search('   '), ['a', 'b', 'c']);
      expect(highlightTerms('#ideas coffee'), ['coffee']);
    });

    test('the snippet shows where a deep match is', () {
      final text = '${'word ' * 30}the important part is here';
      final snippet = searchSnippet(text, ['important'])!;
      expect(snippet, startsWith('…'));
      expect(snippet, contains('the important part'));
      expect(searchSnippet('short text', ['short']), 'short text');
      expect(searchSnippet('short text', ['missing']), isNull);
    });

    test('matches are highlighted without losing the original styles', () {
      const bold = TextStyle(fontWeight: FontWeight.bold);
      final spans = highlightMatches(
        [
          const TextSpan(text: 'Coffee '),
          const TextSpan(text: 'beans', style: bold),
        ],
        ['fee', 'bea'],
      );

      expect([for (final s in spans) s.text], ['Cof', 'fee', ' ', 'bea', 'ns']);
      expect(spans[1].style?.backgroundColor, searchHighlightColor);
      expect(spans[3].style?.backgroundColor, searchHighlightColor);
      expect(spans[3].style?.fontWeight, FontWeight.bold);
      expect(spans[4].style, bold);
    });
  });

  group('tags', () {
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

    late AppDatabase db;
    late TagsRepository tags;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      tags = TagsRepository(db, ownerId: () => 'user-1');
      await db.syncDao.clearOutbox();
    });
    tearDown(() => db.close());

    Future<Map<String, String>> names() async => {
      for (final t in await db.select(db.tagsTable).get()) t.id: t.name,
    };
    Future<List<String>> tagsOf(String noteId) async => [
      for (final l in await (db.select(
        db.notesTagsTable,
      )..where((l) => l.noteId.equals(noteId))).get())
        l.tagId,
    ];

    test('rename keeps the tag on its notes, and is uploaded', () async {
      await tags.renameTag('ideas', 'thoughts');

      expect((await names())['ideas'], 'thoughts');
      expect(await tagsOf('book-notes-deep-work'), ['ideas']);
      final queued = await db.syncDao.outboxEntries();
      expect(queued.map((e) => (e.entity, e.recordId)), [('tags', 'ideas')]);
    });

    test('a name another tag has is refused', () async {
      await expectLater(
        tags.renameTag('ideas', 'recipes'),
        throwsA(isA<TagNameTakenException>()),
      );
      expect((await names())['ideas'], 'ideas');
    });

    test(
      'a new tag with a renamed tag\'s old name is a separate tag',
      () async {
        final first = await tags.createTag('travel');
        await tags.renameTag(first, 'trips');
        final second = await tags.createTag('travel');

        expect(second, isNot(first));
        expect((await names())[first], 'trips');
        expect((await names())[second], 'travel');
        // An existing name is reused rather than duplicated.
        expect(await tags.createTag('travel'), second);
      },
    );

    test('delete removes it from notes (which stay); undo restores', () async {
      final deleted = await tags.deleteTag('architecture');

      expect(deleted!.noteIds, ['sync-architecture']);
      expect((await names()).containsKey('architecture'), isFalse);
      expect(await tagsOf('sync-architecture'), isEmpty);
      expect(
        await db.notesDao.getNotesByIds(['sync-architecture']),
        hasLength(1),
      );
      final queued = await db.syncDao.outboxEntries();
      expect(
        queued.map((e) => (e.entity, e.recordId, e.op)),
        unorderedEquals([
          ('notes_tags', 'sync-architecture::architecture', 'delete'),
          ('tags', 'architecture', 'delete'),
        ]),
      );

      expect(await tags.restoreTag(deleted), isTrue);
      expect((await names())['architecture'], 'architecture');
      expect(await tagsOf('sync-architecture'), ['architecture']);
    });
  });
}
