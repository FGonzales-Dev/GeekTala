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

  test('importing again can add only what is missing', () async {
    final folderPath = p.join(root.path, 'Apple Notes');
    Future<FolderImportResult> import({required bool addMissingOnly}) =>
        importMarkdownDirectory(
          folderPath,
          db: db,
          folders: folders,
          notes: notes,
          addMissingOnly: addMissingOnly,
        );
    Future<List<NoteRow>> imported() => (db.select(
      db.notesTable,
    )..where((n) => n.ownerId.equals('user-1'))).get();

    await write('Notes/Groceries.md', 'eggs');
    await write('Notes/Old idea.md', 'maybe');
    await write('Upang/Schedule.md', 'Mon');
    final first = await import(addMissingOnly: false);
    expect(first.notes, 3);

    // In Noote since: one note edited, one moved to Recently Deleted.
    final rows = {for (final r in await imported()) r.title: r};
    await db.notesDao.updateNote(
      rows['Groceries']!.id,
      NotesTableCompanion(
        title: const Value('Groceries'),
        bodyJson: Value({
          'document': {'type': 'page', 'children': <Object>[]},
        }),
      ),
    );
    await notes.deleteNote(rows['Old idea']!.id);

    // In Apple Notes since: two new notes, one in a new nested folder.
    await write('Notes/Tickets.md', 'seat 12A');
    await write('Pivotly/jfb/Plan.md', 'ship it');

    final second = await import(addMissingOnly: true);

    expect(second.rootFolderId, first.rootFolderId);
    expect(second.notes, 3); // Tickets, Plan, and Old idea (was deleted)
    expect(second.skippedNotes, 2); // Groceries, Schedule
    expect(second.folders, 2); // Pivotly, jfb
    expect(second.failedFiles, isEmpty);

    final tree = FolderTree(await folders.watchAllFolders().first);
    expect([
      for (final f in tree.childrenOf(first.rootFolderId)) f.name,
    ], unorderedEquals(['Notes', 'Pivotly', 'Upang']));
    expect(tree.roots.where((f) => f.name == 'Apple Notes'), hasLength(1));

    final after = await imported();
    final active = [
      for (final r in after)
        if (!r.isDeleted) r.title,
    ];
    expect(
      active,
      unorderedEquals(['Groceries', 'Old idea', 'Schedule', 'Tickets', 'Plan']),
    );
    // The note edited in Noote is untouched.
    final groceries = after.singleWhere((r) => r.title == 'Groceries');
    expect(groceries.bodyJson['document']['children'], isEmpty);
  });
}
