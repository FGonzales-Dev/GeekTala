import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/models/folder_tree.dart';
import 'package:noote/data/repositories/folders_repository.dart';
import 'package:noote/data/repositories/notes_repository.dart';
import 'package:noote/data/sync/sync_remote.dart';
import 'package:noote/data/sync/sync_service.dart';

class RecordingRemote implements SyncRemote {
  final pushed = <Map<String, Object?>>[];
  final server = <String, List<Map<String, dynamic>>>{};

  @override
  Future<int> pushChanges(List<Map<String, Object?>> changes) async {
    pushed.addAll(changes);
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async =>
      server[table] ?? [];
}

/// The local schema before folder order existed (schema version 1).
const _v1Schema = [
  'CREATE TABLE "folders_table" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL DEFAULT \'\', "name" TEXT NOT NULL, "parent_id" TEXT NULL, "updated_at" TEXT NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"))',
  'CREATE TABLE "notes_table" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL DEFAULT \'\', "folder_id" TEXT NULL, "title" TEXT NOT NULL DEFAULT \'\', "title_style_json" TEXT NOT NULL DEFAULT \'[]\', "body_json" TEXT NOT NULL DEFAULT \'{}\', "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "deleted_at" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "tags_table" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL DEFAULT \'\', "name" TEXT NOT NULL UNIQUE, PRIMARY KEY ("id"))',
  'CREATE TABLE "notes_tags_table" ("id" TEXT NOT NULL, "note_id" TEXT NOT NULL, "tag_id" TEXT NOT NULL, "owner_id" TEXT NOT NULL DEFAULT \'\', PRIMARY KEY ("id"))',
  'CREATE TABLE "sync_outbox" ("seq" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "entity" TEXT NOT NULL, "record_id" TEXT NOT NULL, "op" TEXT NOT NULL, UNIQUE(entity, record_id))',
  'CREATE TABLE "sync_state" ("name" TEXT NOT NULL PRIMARY KEY, "value" TEXT NOT NULL)',
  "CREATE TRIGGER folders_outbox_insert AFTER INSERT ON folders_table BEGIN INSERT OR REPLACE INTO sync_outbox (entity, record_id, op) VALUES ('folders', new.id, 'upsert');END",
  "CREATE TRIGGER folders_outbox_update AFTER UPDATE ON folders_table BEGIN INSERT OR REPLACE INTO sync_outbox (entity, record_id, op) VALUES ('folders', new.id, 'upsert');END",
];

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late FoldersRepository folders;
  late NotesRepository notes;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    folders = FoldersRepository(db);
    notes = NotesRepository(db);
    await db.syncDao.clearOutbox(); // ignore the seed; check what moves queue
  });

  tearDown(() => db.close());

  Future<FolderTree> tree() async =>
      FolderTree(await folders.watchAllFolders().first);

  Future<List<String>> order(String? parentId) async => [
    for (final f in (await tree()).childrenOf(parentId)) f.id,
  ];

  Future<List<(String, String)>> queued() async => [
    for (final e in await db.syncDao.outboxEntries()) (e.entity, e.recordId),
  ];

  Future<NoteRow> note(String id) async =>
      (await db.notesDao.getNotesByIds([id])).single;

  group('folders', () {
    test('dropped into another folder, it goes last and is queued', () async {
      expect(
        await folders.moveFolder('product-specs', parentId: 'personal'),
        isNotNull,
      );

      expect(await order('personal'), ['product-specs']);
      expect(await order('work'), ['engineering']);
      expect(await queued(), [('folders', 'product-specs')]);
    });

    test('reordering writes only the moved folder', () async {
      await folders.moveFolder('shared', parentId: null, index: 0);
      expect(await order(null), ['shared', 'work', 'personal']);

      await folders.moveFolder('shared', parentId: null, index: 1);
      expect(await order(null), ['work', 'shared', 'personal']);
      expect(await queued(), [('folders', 'shared')]);
    });

    test('dropping a folder where it already is changes nothing', () async {
      expect(
        await folders.moveFolder('personal', parentId: null, index: 1),
        isNull,
      );
      expect(
        await folders.moveFolder('product-specs', parentId: 'work'),
        isNull,
      );
      expect(await queued(), isEmpty);
    });

    test('forbidden moves are refused', () async {
      await expectLater(
        folders.moveFolder('work', parentId: 'engineering'),
        throwsArgumentError,
      );
      await expectLater(
        folders.moveFolder('personal', parentId: 'work'),
        throwsArgumentError,
      );
      expect(await queued(), isEmpty);
    });

    test(
      'tied neighbours are renumbered, and undo restores all of it',
      () async {
        await db.foldersDao.setSortOrder('personal', 0); // ties with Work
        final before = await order(null);
        expect(before, ['personal', 'work', 'shared']); // tie broken by name

        final undo = await folders.moveFolder(
          'shared',
          parentId: null,
          index: 1,
        );
        expect(await order(null), ['personal', 'shared', 'work']);
        expect([for (final f in (await tree()).roots) f.sortOrder], [0, 1, 2]);

        await folders.undoMove(undo!);
        expect(await order(null), before);
      },
    );

    test('undo puts a folder back in its old parent and place', () async {
      final undo = await folders.moveFolder(
        'engineering',
        parentId: null,
        index: 0,
      );
      expect(await order(null), ['engineering', 'work', 'personal', 'shared']);

      await folders.undoMove(undo!);
      expect(await order('work'), ['engineering', 'product-specs']);
      expect(await order(null), ['work', 'personal', 'shared']);
    });
  });

  group('notes', () {
    test('moving several notes skips those already there; undo', () async {
      final previous = await notes.moveNotes([
        'sync-architecture',
        'grocery-list',
      ], 'personal');

      expect(previous, {'sync-architecture': 'engineering'});
      expect((await note('sync-architecture')).folderId, 'personal');
      expect(await queued(), [('notes', 'sync-architecture')]);

      await notes.undoMoveNotes(previous);
      expect((await note('sync-architecture')).folderId, 'engineering');
    });

    test('deleting several notes at once, and restoring them', () async {
      await notes.deleteNotes(['grocery-list', 'api-auth-flow']);
      expect((await note('grocery-list')).isDeleted, isTrue);
      expect((await note('api-auth-flow')).isDeleted, isTrue);

      await notes.restoreNotes(['grocery-list', 'api-auth-flow']);
      expect((await note('grocery-list')).isDeleted, isFalse);
      expect((await note('api-auth-flow')).isDeleted, isFalse);
    });
  });

  group('sync', () {
    test('upload sends the folder order', () async {
      await folders.moveFolder('shared', parentId: null, index: 0);
      final remote = RecordingRemote();

      await SyncService(db, remote).upload();

      final row = remote.pushed.single['row']! as Map;
      expect(row['sort_order'], -1.0); // before Work (0)
      expect(row['parent_id'], isNull);
    });

    test('download keeps the server order; a missing one becomes 0', () async {
      final remote = RecordingRemote()
        ..server['folders'] = [
          {
            'owner_id': 'u',
            'id': 'personal',
            'name': 'Personal',
            'parent_id': null,
            'updated_at': '2026-11-09T10:00:00Z',
            'is_deleted': false,
            'sort_order': 3.5,
          },
          {
            'owner_id': 'u',
            'id': 'shared',
            'name': 'Shared',
            'parent_id': null,
            'updated_at': '2026-11-09T10:00:00Z',
            'is_deleted': false,
          },
        ];

      await SyncService(db, remote).download(discardLocalChanges: true);

      final byId = {for (final f in (await tree()).roots) f.id: f.sortOrder};
      expect(byId, {'personal': 3.5, 'shared': 0});
    });
  });

  test(
    'upgrading a version-1 database keeps the folders in the same order',
    () async {
      await db.close();
      db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            for (final statement in _v1Schema) {
              raw.execute(statement);
            }
            // Shown in creation order before: Work, Personal, Shared at the
            // top; Engineering, Product Specs under Work.
            for (final (id, parent) in [
              ('work', null),
              ('engineering', 'work'),
              ('personal', null),
              ('product-specs', 'work'),
              ('shared', null),
            ]) {
              raw.execute(
                'INSERT INTO folders_table (id, name, parent_id, updated_at) '
                'VALUES (?, ?, ?, ?)',
                [id, id, parent, '2026-11-09T10:00:00.000'],
              );
            }
            raw.execute('DELETE FROM sync_outbox');
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      folders = FoldersRepository(db);

      expect(await order(null), ['work', 'personal', 'shared']);
      expect(await order('work'), ['engineering', 'product-specs']);
      expect(
        {
          for (final f in (await tree()).flatten())
            f.folder.id: f.folder.sortOrder,
        },
        {
          'work': 0,
          'engineering': 0,
          'product-specs': 1,
          'personal': 1,
          'shared': 2,
        },
      );
      // Later upgrades ran too (version 3: attachments).
    expect(await db.attachmentsDao.all(), isEmpty);
    // The new order is queued for upload.
      expect(
        (await queued()).map((e) => e.$2),
        unorderedEquals([
          'work',
          'engineering',
          'personal',
          'product-specs',
          'shared',
        ]),
      );
    },
  );
}
