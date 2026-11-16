import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:noote/app.dart';
import 'package:noote/core/router/app_router.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/providers/auth_provider.dart';
import 'package:noote/data/providers/database_provider.dart';
import 'package:noote/data/providers/notes_providers.dart';
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/repositories/notes_repository.dart';
import 'package:noote/data/sync/app_sync_status.dart';
import 'package:noote/features/note_editor/widgets/mobile_note_editor_screen.dart';
import 'package:noote/features/note_editor/widgets/note_editor_body.dart';
import 'package:noote/features/notes_list/widgets/notes_list_pane.dart';
import 'package:noote/features/folders/mobile_folders_home.dart';
import 'package:noote/features/notes_list/widgets/mobile_folder_screen.dart';
import 'package:noote/features/shell/widgets/desktop_shell.dart';

/// The real routes (without sign-in). Desktop: moving between the main
/// screens updates one page in place rather than sliding in new copies.
/// Phones: Folders → a folder → a note, each pushed, Back walking up.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;

  Future<GoRouter> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final router = GoRouter(initialLocation: '/', routes: appRoutes);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncStatusProvider.overrideWithValue(AppSyncStatus.idle),
          syncCoordinatorProvider.overrideWith((ref) {}),
          // The Settings tab shows the account; no Supabase in tests.
          currentUserProvider.overrideWithValue(null),
          goRouterProvider.overrideWithValue(router),
          // No Supabase in tests to say who's signed in.
          notesRepositoryProvider.overrideWith(
            (ref) => NotesRepository(db, ownerId: () => 'user-1'),
          ),
        ],
        child: const NooteApp(),
      ),
    );
    await settle(tester, 20);
    return router;
  }

  testWidgets('desktop: one window, kept across every route change', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final router = await pumpApp(tester, const Size(1200, 800));
      final window = tester.element(find.byType(DesktopShell));
      final list = tester.element(find.byType(NotesListPane));

      for (var i = 0; i < 10; i++) {
        router.go(i.isEven ? '/notes/api-auth-flow' : '/notes/grocery-list');
        // A single frame later there's still only one window: nothing is
        // sliding in.
        await tester.pump();
        expect(find.byType(DesktopShell), findsOneWidget);
        await settle(tester, 2);
        expect(find.byType(NoteEditorBody), findsOneWidget);

        router.go('/'); // what deleting the open note does
        await tester.pump();
        expect(find.byType(DesktopShell), findsOneWidget);
        await settle(tester, 2);
      }

      // The very same widgets, not rebuilt copies.
      expect(
        identical(tester.element(find.byType(DesktopShell)), window),
        isTrue,
      );
      expect(
        identical(tester.element(find.byType(NotesListPane)), list),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  testWidgets('desktop: no Shared anywhere until sharing exists', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpApp(tester, const Size(1200, 800));
      expect(find.text('Shared with me'), findsNothing);
      expect(find.text('Shared'), findsNothing); // the empty Shared folder
      expect(find.text('Personal'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  testWidgets(
    'mobile: Folders → folder → note and back, with no tabs, FAB or Shared',
    (tester) async {
      await tester.runAsync(() async {
        final router = await pumpApp(tester, const Size(400, 800));

        // Home is Folders: no tab bar, no floating button, no Shared.
        expect(find.byType(MobileFoldersHome), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(BottomNavigationBar), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('Shared'), findsNothing);
        expect(find.text('All Notes'), findsOneWidget);
        expect(find.text('Recently Deleted'), findsOneWidget);

        // A folder with subfolders: they're listed first.
        await tester.tap(find.text('Work'));
        await settle(tester, 10);
        expect(find.byType(MobileFolderScreen), findsOneWidget);
        expect(find.text('Engineering'), findsOneWidget);
        expect(find.text('Product Specs'), findsOneWidget);

        // Into the subfolder: Back says where it goes.
        await tester.tap(find.text('Engineering'));
        await settle(tester, 10);
        expect(find.text('4 notes'), findsOneWidget);
        expect(find.bySemanticsLabel('Back to Work'), findsOneWidget);

        // A note, then back up with the system Back (Android's back
        // button), one screen at a time.
        await tester.tap(find.text('API Auth Flow'));
        await settle(tester, 10);
        expect(find.byType(MobileNoteEditorScreen), findsOneWidget);
        expect(find.bySemanticsLabel('Back to Engineering'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await settle(tester, 10);
        expect(find.byType(MobileNoteEditorScreen), findsNothing);
        expect(find.text('API Auth Flow'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await settle(tester, 10);
        expect(find.text('Product Specs'), findsOneWidget); // Work again

        // The on-screen Back does the same.
        await tester.tap(find.bySemanticsLabel('Back to Folders'));
        await settle(tester, 10);
        expect(find.byType(MobileFoldersHome), findsOneWidget);
        expect(router.canPop(), isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    },
  );

  testWidgets('mobile: a new note goes into the open folder', (tester) async {
    await tester.runAsync(() async {
      await pumpApp(tester, const Size(400, 800));
      await tester.tap(find.text('Personal'));
      await settle(tester, 10);
      expect(find.text('2 notes'), findsOneWidget);

      await tester.tap(find.byTooltip('New note'));
      await settle(tester, 10);
      expect(find.byType(MobileNoteEditorScreen), findsOneWidget);
      expect(find.bySemanticsLabel('Back to Personal'), findsOneWidget);
      final notes = await (db.select(
        db.notesTable,
      )..where((n) => n.folderId.equals('personal'))).get();
      expect(notes, hasLength(3));

      // Back on the folder, it's counted.
      await tester.binding.handlePopRoute();
      await settle(tester, 10);
      expect(find.text('3 notes'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  testWidgets('a phone-sized stack survives the window getting wider', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpApp(tester, const Size(400, 800));
      await tester.tap(find.text('Personal'));
      await settle(tester, 10);
      await tester.tap(find.text('Grocery List'));
      await settle(tester, 10);
      expect(find.byType(MobileNoteEditorScreen), findsOneWidget);

      tester.view.physicalSize = const Size(1200, 800);
      await settle(tester, 10);
      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopShell), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}

/// Real async work (the database) plus a moving test clock (animations).
Future<void> settle(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
