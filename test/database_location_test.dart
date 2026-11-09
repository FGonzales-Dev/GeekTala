import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noote/data/database/connection/connection_native.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String documents;
  late String support;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('noote_db_location');
    documents = p.join(root.path, 'Documents');
    support = p.join(root.path, 'Support');
    await Directory(documents).create();
    await Directory(support).create();
  });

  tearDown(() => root.delete(recursive: true));

  File file(String dir, String name) => File(p.join(dir, name));

  test('an old database in Documents is moved, side files too', () async {
    await file(documents, 'noote_local.sqlite').writeAsString('db');
    await file(documents, 'noote_local.sqlite-wal').writeAsString('wal');

    await moveFromDocumentsIfNeeded(from: documents, to: support);

    expect(await file(support, 'noote_local.sqlite').readAsString(), 'db');
    expect(await file(support, 'noote_local.sqlite-wal').readAsString(), 'wal');
    expect(await file(documents, 'noote_local.sqlite').exists(), isFalse);
    expect(await file(documents, 'noote_local.sqlite-wal').exists(), isFalse);
  });

  test('an existing database in the new place is never replaced', () async {
    await file(documents, 'noote_local.sqlite').writeAsString('old');
    await file(support, 'noote_local.sqlite').writeAsString('current');

    await moveFromDocumentsIfNeeded(from: documents, to: support);

    expect(await file(support, 'noote_local.sqlite').readAsString(), 'current');
    expect(await file(documents, 'noote_local.sqlite').exists(), isTrue);
  });

  test('nothing to move is fine', () async {
    await moveFromDocumentsIfNeeded(from: documents, to: support);
    expect(await file(support, 'noote_local.sqlite').exists(), isFalse);
  });
}
