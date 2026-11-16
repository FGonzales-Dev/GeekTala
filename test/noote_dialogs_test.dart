import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/core/app_info.dart';
import 'package:noote/core/theme/app_theme.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/providers/auth_provider.dart';
import 'package:noote/data/providers/database_provider.dart';
import 'package:noote/data/providers/device_settings_provider.dart';
import 'package:noote/data/providers/folders_providers.dart';
import 'package:noote/data/providers/notes_providers.dart';
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/providers/tags_providers.dart';
import 'package:noote/data/repositories/folders_repository.dart';
import 'package:noote/data/repositories/notes_repository.dart';
import 'package:noote/data/repositories/tags_repository.dart';
import 'package:noote/data/sync/app_sync_status.dart';
import 'package:noote/features/folders/folder_actions.dart';
import 'package:noote/features/folders/widgets/delete_folder_dialog.dart';
import 'package:noote/features/folders/widgets/move_to_folder_picker.dart';
import 'package:noote/features/note_editor/widgets/note_tag_picker.dart';
import 'package:noote/features/settings/widgets/settings_dialog.dart';
import 'package:noote/features/trash/widgets/permanent_delete_dialog.dart';

/// The dialogs (desktop size): what they show before you confirm, their
/// keyboard behaviour, and what they change — against an in-memory
/// database with the demo content.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late WidgetRef ref;
  late BuildContext context;

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpHost(WidgetTester tester, {Widget? child}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncStatusProvider.overrideWithValue(AppSyncStatus.idle),
          currentUserProvider.overrideWithValue(null),
          foldersRepositoryProvider.overrideWith(
            (ref) => FoldersRepository(db, ownerId: () => 'u'),
          ),
          notesRepositoryProvider.overrideWith(
            (ref) => NotesRepository(db, ownerId: () => 'u'),
          ),
          tagsRepositoryProvider.overrideWith(
            (ref) => TagsRepository(db, ownerId: () => 'u'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Consumer(
              builder: (c, r, _) {
                ref = r;
                context = c;
                // Keep the folder tree loaded, as the app does.
                r.watch(folderTreeProvider);
                return child ?? const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<int> notesIn(String folderId) async =>
      (await (db.select(db.notesTable)..where(
                (n) => n.folderId.equals(folderId) & n.isDeleted.equals(false),
              ))
              .get())
          .length;

  testWidgets('delete folder: counts first, keeps the notes unless asked', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpHost(tester);
      unawaited(
        showDeleteFolderDialog(
          context,
          ref,
          folderId: 'work',
          folderName: 'Work',
        ),
      );
      await settle(tester);

      expect(find.text('Delete “Work”?'), findsOneWidget);
      expect(find.text('2 subfolders'), findsOneWidget);
      expect(find.text('4 notes'), findsOneWidget);
      expect(find.textContaining('Recommended'), findsOneWidget);

      // Enter doesn't delete: the red button has to be clicked.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Delete “Work”?'), findsOneWidget);

      // Esc closes without deleting.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Delete “Work”?'), findsNothing);
      expect(ref.read(folderTreeProvider).contains('work'), isTrue);

      // Keep the notes (the default): they move to Personal.
      final personalBefore = await notesIn('personal');
      unawaited(
        showDeleteFolderDialog(
          context,
          ref,
          folderId: 'engineering',
          folderName: 'Engineering',
        ),
      );
      await settle(tester);
      expect(find.text('The folder goes away.'), findsOneWidget);
      await tester.tap(find.text('Delete folder'));
      await settle(tester);
      expect(await notesIn('personal'), personalBefore + 4);
      expect(ref.read(folderTreeProvider).contains('engineering'), isFalse);

      await unmount(tester);
    });
  });

  testWidgets('new folder: Enter creates it where "Inside" says', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpHost(tester);
      unawaited(createFolderFlow(context, ref, parentId: 'work'));
      await settle(tester);

      expect(find.text('New subfolder'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget); // the "Inside" selector
      // Nothing typed: Create is off, Enter does nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('New subfolder'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Site visits');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('New subfolder'), findsNothing);
      final tree = ref.read(folderTreeProvider);
      expect(
        tree.childrenOf('work').map((f) => f.name),
        contains('Site visits'),
      );

      await unmount(tester);
    });
  });

  testWidgets('move to: type to find, current folder marked, Enter moves', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpHost(tester);
      final tree = ref.read(folderTreeProvider);
      final picked = showMoveToFolderPicker(
        context,
        title: 'Move “Grocery List”',
        tree: tree,
        current: (folderId: 'personal'),
        isAllowed: (id) => id != null && id != 'personal',
      );
      await settle(tester);

      expect(find.text('From Personal'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Shared'), findsNothing); // hidden until sharing
      expect(find.text('Move'), findsOneWidget); // nothing picked yet

      await tester.enterText(find.byType(TextField), 'spec');
      await settle(tester);
      expect(find.text('Work / Product Specs'), findsOneWidget);
      expect(find.text('Move to Product Specs'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(await picked, (folderId: 'product-specs'));

      await unmount(tester);
    });
  });

  testWidgets('tags: one field searches, creates and ticks', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(
        tester,
        child: const NoteTagPicker(noteId: 'grocery-list'),
      );
      await tester.tap(find.text('Tag'));
      await settle(tester);
      expect(find.text('For “Grocery List”'), findsOneWidget);
      expect(find.text('ideas'), findsOneWidget);

      // A new name: Enter creates it and puts it on the note.
      await tester.enterText(find.byType(TextField), '#inspections');
      await settle(tester);
      expect(find.text('Create “inspections”'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      // An existing name: Enter ticks that one instead of making another.
      await tester.enterText(find.byType(TextField), 'ideas');
      await settle(tester);
      expect(find.textContaining('Create'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      final tags = await (db.select(db.tagsTable)).get();
      expect(tags.where((t) => t.name == 'inspections'), hasLength(1));
      expect(tags.where((t) => t.name == 'ideas'), hasLength(1));
      final links = await (db.select(
        db.notesTagsTable,
      )..where((t) => t.noteId.equals('grocery-list'))).get();
      final names = {for (final t in tags) t.id: t.name};
      expect(
        links.map((l) => names[l.tagId]),
        containsAll(['inspections', 'ideas']),
      );

      // Empty field: Enter closes.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('For “Grocery List”'), findsNothing);

      await unmount(tester);
    });
  });

  testWidgets('delete forever: only the red button deletes', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(tester);
      unawaited(
        showPermanentDeleteDialog(
          context,
          ref,
          noteId: 'grocery-list',
          noteTitle: 'Grocery List',
        ),
      );
      await settle(tester);
      expect(find.text('Delete “Grocery List” forever?'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Delete “Grocery List” forever?'), findsOneWidget);

      await tester.tap(find.text('Delete forever'));
      await settle(tester);
      final left = await (db.select(
        db.notesTable,
      )..where((n) => n.id.equals('grocery-list'))).get();
      expect(left, isEmpty);

      await unmount(tester);
    });
  });

  testWidgets('settings window: sections, and settings are remembered', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpHost(tester);
      unawaited(showSettingsWindow(context));
      await settle(tester);

      // Appearance first: the theme previews.
      expect(find.text('How Noote looks on this device.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dark theme'));
      await settle(tester);

      await tester.tap(find.text('Editor'));
      await settle(tester);
      expect(find.text('PDFs in notes'), findsOneWidget);
      await tester.tap(find.text('Card'));
      await settle(tester);

      await tester.tap(find.text('About'));
      await settle(tester);
      expect(find.text(appVersion), findsOneWidget);
      expect(find.textContaining('6 notes'), findsOneWidget);

      final settings = await db.syncDao.watchState().first;
      expect(settings[DeviceSettingKeys.themeMode], 'dark');
      expect(settings[DeviceSettingKeys.pdfView], 'card');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('About Noote'), findsNothing);

      await unmount(tester);
    });
  });

  test('the version in About matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
