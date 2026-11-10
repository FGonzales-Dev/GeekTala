import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/database/daos/sync_dao.dart';
import 'package:noote/data/sync/sync_remote.dart';
import 'package:noote/data/sync/sync_service.dart';

/// Stands in for Supabase: records what was pushed, serves canned rows.
class FakeRemote implements SyncRemote {
  final pushes = <List<Map<String, Object?>>>[];
  final server = <String, List<Map<String, dynamic>>>{
    'folders': [],
    'tags': [],
    'notes': [],
    'notes_tags': [],
  };
  Future<void> Function()? onPush;
  Object? failWith;

  List<Map<String, Object?>> get allPushed => [for (final p in pushes) ...p];

  @override
  Future<int> pushChanges(List<Map<String, Object?>> changes) async {
    if (failWith case final error?) throw error;
    pushes.add(changes);
    final hook = onPush;
    onPush = null;
    await hook?.call();
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async =>
      server[table]!;
}

/// The demo seed: 5 folders, 3 tags, 6 notes, 2 note–tag links.
const seededRows = 16;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late FakeRemote remote;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = FakeRemote();
    sync = SyncService(db, remote);
  });

  tearDown(() => db.close());

  int indexOf(String table, String id) =>
      remote.allPushed.indexWhere((c) => c['table'] == table && c['id'] == id);

  Future<void> addNote(String id, {String folderId = 'personal'}) {
    final now = DateTime.now();
    return db.notesDao.insertNote(
      NotesTableCompanion.insert(
        id: id,
        folderId: Value(folderId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('first launch queues the demo content for upload', () async {
    expect(await db.syncDao.pendingCount(), seededRows);
  });

  test('upload sends rows before the rows that point at them', () async {
    final result = await sync.upload();

    expect(result.uploaded, seededRows);
    expect(await db.syncDao.pendingCount(), 0);
    // Parent folder before its child, folders before notes, notes before
    // their tag links.
    expect(indexOf('folders', 'work'), lessThan(indexOf('folders', 'engineering')));
    expect(indexOf('folders', 'engineering'), lessThan(indexOf('notes', 'sync-architecture')));
    expect(indexOf('tags', 'architecture'), lessThan(indexOf('notes_tags', 'sync-architecture::architecture')));
    expect(indexOf('notes', 'sync-architecture'), lessThan(indexOf('notes_tags', 'sync-architecture::architecture')));

    final note = remote.allPushed[indexOf('notes', 'grocery-list')];
    expect(note['op'], 'upsert');
    final row = note['row']! as Map<String, Object?>;
    expect(row['folder_id'], 'personal');
    expect(row['is_deleted'], false);
    expect(row['body_json'], isA<Map<String, dynamic>>());
    expect(row['updated_at'], endsWith('Z'));

    expect(await db.syncDao.readState(SyncDao.lastUploadedAtKey), isNotNull);

    // Nothing left: a second upload sends nothing.
    await sync.upload();
    expect(remote.pushes, hasLength(1));
  });

  test('trash is uploaded as a flag; delete forever as a delete', () async {
    await sync.upload();
    remote.pushes.clear();

    await db.notesDao.softDeleteNote('grocery-list');
    await db.notesDao.permanentlyDeleteNote('sync-architecture');
    await sync.upload();

    final trashed = remote.allPushed[indexOf('notes', 'grocery-list')];
    expect(trashed['op'], 'upsert');
    expect((trashed['row']! as Map)['is_deleted'], true);

    final link = remote.allPushed[indexOf('notes_tags', 'sync-architecture::architecture')];
    expect(link['op'], 'delete');
    expect(link['row'], {'note_id': 'sync-architecture', 'tag_id': 'architecture'});
    expect(remote.allPushed[indexOf('notes', 'sync-architecture')]['op'], 'delete');
  });

  test('a note edited while uploading stays queued', () async {
    remote.onPush = () => db.notesDao.updateNote(
          'grocery-list',
          NotesTableCompanion(
            title: const Value('Edited mid-upload'),
            updatedAt: Value(DateTime.now()),
          ),
        );

    await sync.upload();

    final left = await db.syncDao.outboxEntries();
    expect(left.map((e) => (e.entity, e.recordId)), [('notes', 'grocery-list')]);
  });

  test('a failed upload keeps everything queued', () async {
    remote.failWith = Exception('offline');

    await expectLater(sync.upload(), throwsException);
    expect(await db.syncDao.pendingCount(), seededRows);
  });

  test('large uploads are split into several requests', () async {
    for (var i = 0; i < 150; i++) {
      await addNote('bulk-$i');
    }

    await sync.upload();

    expect(remote.pushes.length, greaterThan(1));
    expect(remote.pushes.every((p) => p.length <= SyncService.maxBatchChanges), isTrue);
    expect(remote.allPushed, hasLength(seededRows + 150));
    expect(await db.syncDao.pendingCount(), 0);
  });

  test('download replaces local data with the server copy', () async {
    await sync.upload();
    const owner = '00000000-0000-0000-0000-000000000001';
    remote.server['folders'] = [
      {'owner_id': owner, 'id': 'personal', 'name': 'Personal', 'parent_id': null, 'updated_at': '2026-11-09T10:00:00+00:00', 'is_deleted': false},
    ];
    remote.server['tags'] = [
      {'owner_id': owner, 'id': 't1', 'name': 'server-tag'},
    ];
    remote.server['notes'] = [
      {
        'owner_id': owner,
        'id': 'n1',
        'folder_id': 'personal',
        'title': 'From the server',
        'title_style_json': <Object>[],
        'body_json': {'document': {'type': 'page', 'children': <Object>[]}},
        'created_at': '2026-11-09T10:00:00+00:00',
        'updated_at': '2026-11-09T11:00:00+00:00',
        'is_deleted': false,
        'deleted_at': null,
      },
    ];
    remote.server['notes_tags'] = [
      {'owner_id': owner, 'note_id': 'n1', 'tag_id': 't1'},
    ];

    await sync.download();

    final notes = await db.select(db.notesTable).get();
    expect(notes.map((n) => n.title), ['From the server']);
    expect(notes.single.updatedAt.toUtc(), DateTime.utc(2026, 11, 9, 11));
    final links = await db.select(db.notesTagsTable).get();
    expect(links.single.id, 'n1::t1');
    // "Shared" wasn't on the server: recreated locally and queued, since
    // the app needs it to exist.
    final folders = await db.select(db.foldersTable).get();
    expect(folders.map((f) => f.id), unorderedEquals(['personal', 'shared']));
    final queued = await db.syncDao.outboxEntries();
    expect(queued.map((e) => (e.entity, e.recordId)), [('folders', 'shared')]);
    expect(await db.syncDao.readState(SyncDao.lastDownloadedAtKey), isNotNull);
  });

  test('download refuses to drop changes that are not uploaded', () async {
    await expectLater(
      sync.download(),
      throwsA(isA<UnsyncedChangesException>()),
    );
    expect(await db.select(db.notesTable).get(), hasLength(6));

    await sync.download(discardLocalChanges: true);
    expect(await db.select(db.notesTable).get(), isEmpty);
  });

  test('another account signing in never inherits local notes', () async {
    expect(await sync.adoptAccount('user-a'), isFalse);
    expect(await db.select(db.notesTable).get(), hasLength(6));
    expect(await sync.adoptAccount('user-a'), isFalse);

    expect(await sync.adoptAccount('user-b'), isTrue);
    expect(await db.select(db.notesTable).get(), isEmpty);
    final folders = await db.select(db.foldersTable).get();
    expect(folders.map((f) => f.id), unorderedEquals(['personal', 'shared']));

    // Nothing on the server for user-b: they get the demo content.
    await sync.downloadForNewAccount();
    expect(await db.select(db.notesTable).get(), hasLength(6));
    expect(await db.syncDao.pendingCount(), seededRows);
  });

  test('the pending count updates live as notes change', () async {
    final counts = expectLater(
      db.syncDao.watchPendingCount(),
      emitsInOrder([seededRows, seededRows + 1]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await addNote('live');
    await counts;
  });
}
