import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/models/folder_tree.dart';
import 'package:noote/data/repositories/folders_repository.dart';
import 'package:noote/data/repositories/notes_repository.dart';
import 'package:noote/features/note_editor/folder_import/folder_import.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late Directory root;
  late AppDatabase db;
  late FoldersRepository folders;
  late NotesRepository notes;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('noote_import');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    folders = FoldersRepository(db, ownerId: () => 'user-1');
    notes = NotesRepository(db, ownerId: () => 'user-1');
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> write(String relative, String text, {DateTime? modified}) async {
    final file = File(p.join(root.path, 'Apple Notes', relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
    if (modified != null) await file.setLastModified(modified);
  }

  test('a folder of Markdown becomes folders and notes', () async {
    final date = DateTime(2024, 3, 5, 9, 30);
    await write(
      'Recipes/Pasta.md',
      '# Sauce\n\n- tomatoes\n- basil',
      modified: date,
    );
    await write('Recipes/Desserts/Cake.markdown', 'Bake **40** minutes');
    await write('Todo.txt', 'Plain text');
    await write('Only a title.md', '');
    await write('.DS_Store', 'junk');
    await write('photo.png', 'not text');
    await Directory(p.join(root.path, 'Apple Notes', 'Empty folder')).create();

    final result = await importMarkdownDirectory(
      p.join(root.path, 'Apple Notes'),
      db: db,
      folders: folders,
      notes: notes,
    );

    expect(result.folderName, 'Apple Notes');
    expect(result.notes, 4);
    expect(result.folders, 4); // Apple Notes, Desserts, Empty folder, Recipes
    expect(result.failedFiles, isEmpty);

    final tree = FolderTree(await folders.watchAllFolders().first);
    final top = tree[result.rootFolderId]!;
    expect(top.parentId, isNull);
    expect(
      [for (final f in tree.childrenOf(top.id)) f.name],
      ['Empty folder', 'Recipes'],
    );
    final recipes = tree.childrenOf(top.id).last;
    expect([for (final f in tree.childrenOf(recipes.id)) f.name], ['Desserts']);

    final rows = await (db.select(
      db.notesTable,
    )..where((n) => n.ownerId.equals('user-1'))).get();
    final byTitle = {for (final r in rows) r.title: r};
    expect(
      byTitle.keys,
      unorderedEquals(['Pasta', 'Cake', 'Todo', 'Only a title']),
    );

    final pasta = byTitle['Pasta']!;
    expect(pasta.folderId, recipes.id);
    expect(pasta.updatedAt, date);
    final types = [
      for (final b in pasta.bodyJson['document']['children'] as List) b['type'],
    ];
    expect(types, ['heading', 'bulleted_list', 'bulleted_list']);

    // An empty file still gets a line to type in.
    final empty = byTitle['Only a title']!.bodyJson['document']['children'];
    expect(empty, hasLength(1));

    // Everything is queued for upload.
    expect(await db.syncDao.pendingCount(), greaterThan(4 + 6));
  });
}
