import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noote/data/attachments/attachment_refs.dart';
import 'package:noote/data/attachments/attachment_store.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/repositories/folders_repository.dart';
import 'package:noote/data/repositories/notes_repository.dart';
import 'package:noote/data/sync/sync_remote.dart';
import 'package:noote/data/sync/sync_service.dart';
import 'package:noote/features/note_editor/folder_import/folder_import.dart';
import 'package:noote/features/note_editor/insert_images.dart';
import 'package:path/path.dart' as p;

import 'support/fake_attachments.dart';

Uint8List png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

class NullSyncRemote implements SyncRemote {
  var pushes = 0;

  @override
  Future<int> pushChanges(List<Map<String, Object?>> changes) async {
    pushes++;
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late AttachmentStore store;
  late FakeAttachmentRemote remote;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    (store, remote, dir) = await testAttachmentStore(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  String idOf(String ref) => attachmentIdOf(ref)!;
  File fileOf(String ref) => File(p.join(dir.path, idOf(ref)));

  group('references', () {
    test('ids are found anywhere in a note', () {
      const a = '0d7a3f7e-1111-4c5e-9f00-000000000001.png';
      const b = '0d7a3f7e-2222-4c5e-9f00-000000000002.jpg';
      final body = {
        'document': {
          'type': 'page',
          'children': [
            {
              'type': 'image',
              'data': {'url': attachmentRef(a)},
            },
            {
              'type': 'bulleted_list',
              'children': [
                {
                  'type': 'image',
                  'data': {'url': attachmentRef(b)},
                },
              ],
            },
            {
              'type': 'image',
              'data': {'url': 'https://example.com/x.png'},
            },
          ],
        },
      };
      expect(attachmentIdsIn(body), {a, b});
      expect(attachmentIdOf('attachment://../../etc/passwd'), isNull);
    });

    test('pasted images are recognised by their bytes', () {
      expect(imageExtensionOf(png(1, 1)), 'png');
      expect(
        imageExtensionOf(img.encodeJpg(img.Image(width: 1, height: 1))),
        'jpg',
      );
      expect(
        imageExtensionOf(img.encodeBmp(img.Image(width: 1, height: 1))),
        'bmp',
      );
      expect(imageExtensionOf([1, 2, 3]), isNull);
    });
  });

  group('store', () {
    test('an added image is saved on the device, waiting to upload', () async {
      final ref = await store.addImage(png(10, 10), fileName: 'dot.png');

      expect(fileOf(ref).existsSync(), isTrue);
      final row = (await db.attachmentsDao.byId(idOf(ref)))!;
      expect(row.uploaded, isFalse);
      expect(row.mimeType, 'image/png');
      expect(row.originalName, 'dot.png');
    });

    test('large photos are scaled down; BMPs become PNGs', () async {
      final big = await store.addImage(png(3000, 1000), fileName: 'wide.png');
      final shrunk = img.decodeImage(fileOf(big).readAsBytesSync())!;
      expect((shrunk.width, shrunk.height), (2560, 853));

      final bmp = await store.addImage(
        img.encodeBmp(img.Image(width: 4, height: 4)),
        fileName: 'Pasted image',
      );
      expect(bmp, endsWith('.png'));
    });

    test(
      'uploads are sent before notes; a failed one stops the sync',
      () async {
        final ref = await store.addImage(png(5, 5), fileName: 'a.png');
        final notesRemote = NullSyncRemote();
        final sync = SyncService(db, notesRemote, attachments: store);

        remote.failWith = Exception('offline');
        await expectLater(sync.upload(), throwsException);
        expect(notesRemote.pushes, 0);
        expect((await db.attachmentsDao.byId(idOf(ref)))!.uploaded, isFalse);

        remote.failWith = null;
        await sync.upload();
        expect(remote.files.keys, [idOf(ref)]);
        expect((await db.attachmentsDao.byId(idOf(ref)))!.uploaded, isTrue);
        expect(notesRemote.pushes, greaterThan(0));
      },
    );

    test('another device downloads a file once, when first shown', () async {
      const id = '0d7a3f7e-3333-4c5e-9f00-000000000003.png';
      remote.files[id] = png(3, 3);

      final paths = await Future.wait([
        store.ensureLocalPath(id),
        store.ensureLocalPath(id),
      ]);
      expect(paths.toSet(), hasLength(1));
      expect(File(paths.first!).existsSync(), isTrue);
      expect((await db.attachmentsDao.byId(id))!.uploaded, isTrue);

      remote.failWith = Exception('offline');
      expect(await store.ensureLocalPath(id), isNotNull); // already here
      expect(
        await store.ensureLocalPath('0d7a3f7e-4444-4c5e-9f00-000000000004.png'),
        isNull,
      );
    });

    test('files no note uses are cleaned up, except recent ones', () async {
      final used = await store.addImage(png(2, 2), fileName: 'used.png');
      final unused = await store.addImage(png(2, 2), fileName: 'unused.png');
      await db.notesDao.updateNote(
        'grocery-list',
        NotesTableCompanion(
          bodyJson: Value({
            'document': {
              'type': 'page',
              'children': [
                {
                  'type': 'image',
                  'data': {'url': used},
                },
              ],
            },
          }),
        ),
      );

      await store.collectGarbage(); // both too new to remove
      expect(fileOf(unused).existsSync(), isTrue);

      await store.collectGarbage(grace: Duration.zero);
      expect(fileOf(unused).existsSync(), isFalse);
      expect(await db.attachmentsDao.byId(idOf(unused)), isNull);
      expect(fileOf(used).existsSync(), isTrue);
    });

    test('another account signing in clears this one\'s files', () async {
      final ref = await store.addImage(png(2, 2), fileName: 'mine.png');
      final sync = SyncService(db, NullSyncRemote(), attachments: store);

      await sync.adoptAccount('user-a');
      expect(fileOf(ref).existsSync(), isTrue);
      await sync.adoptAccount('user-b');
      expect(fileOf(ref).existsSync(), isFalse);
      expect(await db.attachmentsDao.all(), isEmpty);
    });
  });

  group('inserting into a note', () {
    late EditorState editorState;

    List<String> types() => [
      for (final n in editorState.document.root.children) n.type,
    ];

    setUp(() {
      editorState = EditorState(
        document: Document.blank()
          ..insert([0], [paragraphNode(text: 'Hello'), paragraphNode()]),
      );
    });
    tearDown(() => editorState.dispose());

    test('an empty line is replaced by the images', () async {
      editorState.selection = Selection.collapsed(Position(path: [1]));
      await insertImageNodes(editorState, ['attachment://a', 'attachment://b']);

      expect(types(), ['paragraph', 'image', 'image', 'paragraph']);
      expect(editorState.selection!.end.path, [3]);
    });

    test('after text, they go on the next line', () async {
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 5),
      );
      await insertImages(store, editorState, [
        (bytes: png(4, 4), name: 'x.png'),
      ]);

      expect(types(), ['paragraph', 'image', 'paragraph']);
      final url = editorState.document.root.children[1].attributes['url'];
      expect(isAttachmentRef(url), isTrue);
    });
  });

  test('Import Folder brings in images notes link to', () async {
    final root = await Directory.systemTemp.createTemp('noote_import_images');
    addTearDown(() => root.delete(recursive: true));
    final notes = Directory(p.join(root.path, 'Trip'));
    await Directory(p.join(notes.path, '_attachments')).create(recursive: true);
    File(p.join(notes.path, '_attachments', 'beach day.png'))
        .writeAsBytesSync(png(6, 6));
    File(p.join(notes.path, 'Day 1.md')).writeAsStringSync(
      'Swim\n\n![](_attachments/beach%20day.png)\n\n'
      '![](https://example.com/x.png)\n\n![](_attachments/missing.png)\n',
    );

    final result = await importMarkdownDirectory(
      notes.path,
      db: db,
      folders: FoldersRepository(db, ownerId: () => 'u'),
      notes: NotesRepository(db, ownerId: () => 'u'),
      attachments: store,
    );

    expect(result.folders, 1); // _attachments isn't a Noote folder
    final note = (await (db.select(
      db.notesTable,
    )..where((n) => n.title.equals('Day 1'))).getSingle());
    final urls = [
      for (final b in note.bodyJson['document']['children'] as List)
        if (b['type'] == 'image') b['data']['url'],
    ];
    expect(urls, hasLength(3));
    expect(isAttachmentRef(urls[0]), isTrue);
    expect(urls[1], 'https://example.com/x.png');
    expect(urls[2], '_attachments/missing.png');
    expect(fileOf(urls[0] as String).existsSync(), isTrue);
  });
}
