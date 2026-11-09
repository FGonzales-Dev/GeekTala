import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:noote/app.dart';
import 'package:noote/core/router/app_router.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/models/folder_tree.dart';
import 'package:noote/data/providers/database_provider.dart';
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/repositories/folders_repository.dart';
import 'package:noote/data/sync/app_sync_status.dart';
import 'package:noote/features/folders/drag_data.dart';
import 'package:noote/features/shell/adaptive_shell_screen.dart';

/// Drag and drop in the real desktop shell, against an in-memory database
/// with the demo content. Database work is real async, so each test runs
/// inside `runAsync` and waits by polling (see widget_test.dart).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;

  /// Lets real async work (the database) run, and moves the test clock on
  /// so animations (page transitions, the snack bar) finish.
  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(
    WidgetTester tester,
    Future<bool> Function() done,
  ) async {
    for (var i = 0; i < 40; i++) {
      if (await done()) return;
      await settle(tester, 1);
    }
    fail('Timed out');
  }

  Future<void> pumpApp(WidgetTester tester) async {
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
          syncCoordinatorProvider.overrideWith((ref) {}),
          goRouterProvider.overrideWithValue(
            GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const AdaptiveShellScreen(currentPath: '/'),
                ),
                GoRoute(
                  path: '/notes/:noteId',
                  builder: (context, state) => AdaptiveShellScreen(
                    currentPath: '/',
                    noteId: state.pathParameters['noteId'],
                  ),
                ),
              ],
            ),
          ),
        ],
        child: const NooteApp(),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await settle(tester, 1);
      if (find.text('API Auth Flow').evaluate().isNotEmpty) break;
    }
    expect(find.text('API Auth Flow'), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  /// A mouse drag in small steps, as a real one would be.
  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 12)!);
      await tester.pump();
    }
    await gesture.up();
    await gesture.removePointer();
    await settle(tester);
  }

  /// The sidebar row (its drop target) holding [label].
  Rect sidebarRow(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(DragTarget<NooteDragData>),
        )
        .first,
  );

  Future<NoteRow> note(String id) async =>
      (await db.notesDao.getNotesByIds([id])).single;

  Future<FolderTree> tree() async =>
      FolderTree(await FoldersRepository(db).watchAllFolders().first);

  testWidgets('drag a note onto a folder; Undo moves it back', (tester) async {
    await tester.runAsync(() async {
      await pumpApp(tester);

      await drag(
        tester,
        tester.getCenter(find.text('API Auth Flow')),
        sidebarRow(tester, 'Personal').center,
      );
      await waitFor(
        tester,
        () async => (await note('api-auth-flow')).folderId == 'personal',
      );
      expect(find.text('Moved to Personal'), findsOneWidget);
      expect(
        find.text('API Auth Flow'),
        findsNothing,
      ); // left Engineering's list

      await tester.tap(find.text('Undo'));
      await waitFor(
        tester,
        () async => (await note('api-auth-flow')).folderId == 'engineering',
      );

      await unmount(tester);
    });
  });

  testWidgets('⌘/Ctrl-click two notes and drag both to Recently Deleted', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpApp(tester);

      await tester.tap(find.text('API Auth Flow')); // opens it
      await settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Sprint Retro — Aug 18'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);

      await drag(
        tester,
        tester.getCenter(find.text('Sprint Retro — Aug 18')),
        sidebarRow(tester, 'Recently Deleted').center,
      );
      await waitFor(
        tester,
        () async => (await note('api-auth-flow')).isDeleted,
      );
      expect((await note('sprint-retro-aug-18')).isDeleted, isTrue);
      expect((await note('sync-architecture')).isDeleted, isFalse);
      expect(find.text('Moved 2 notes to Recently Deleted'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('drop a folder on the top edge of another to reorder', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpApp(tester);

      final work = sidebarRow(tester, 'Work');
      await drag(
        tester,
        sidebarRow(tester, 'Product Specs').center,
        Offset(work.center.dx, work.top + 3),
      );
      await waitFor(
        tester,
        () async => (await tree()).parentOf('product-specs') == null,
      );
      expect(
        [for (final f in (await tree()).roots) f.id],
        ['product-specs', 'work', 'personal', 'shared'],
      );
      expect(
        find.text('Moved "Product Specs" to the top level'),
        findsOneWidget,
      );

      await unmount(tester);
    });
  });

  testWidgets('a folder dropped onto its own subfolder stays put', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpApp(tester);

      await drag(
        tester,
        sidebarRow(tester, 'Work').center,
        sidebarRow(tester, 'Engineering').center,
      );
      await settle(tester);
      final t = await tree();
      expect(t.parentOf('work'), isNull);
      expect(t.parentOf('engineering'), 'work');
      expect(find.byType(SnackBar), findsNothing);
      expect(await db.syncDao.pendingCount(), 16); // just the seed

      await unmount(tester);
    });
  });
}
