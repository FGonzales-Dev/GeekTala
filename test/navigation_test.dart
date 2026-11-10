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
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/sync/app_sync_status.dart';
import 'package:noote/features/note_editor/widgets/mobile_note_editor_screen.dart';
import 'package:noote/features/note_editor/widgets/note_editor_body.dart';
import 'package:noote/features/notes_list/widgets/notes_list_pane.dart';
import 'package:noote/features/shell/widgets/desktop_shell.dart';
import 'package:noote/features/shell/widgets/mobile_shell.dart';

/// The real routes (without sign-in): moving between the main screens
/// updates one page in place rather than sliding in new copies.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<GoRouter> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
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

  testWidgets('mobile: tabs share a page; a note opens on its own', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final router = await pumpApp(tester, const Size(400, 800));
      final tabs = tester.element(find.byType(MobileShell));

      for (final tab in ['/folders', '/settings', '/shared', '/']) {
        router.go(tab);
        await tester.pump();
        expect(find.byType(MobileShell), findsOneWidget);
        expect(
          identical(tester.element(find.byType(MobileShell)), tabs),
          isTrue,
        );
      }

      router.go('/notes/grocery-list');
      await settle(tester, 10);
      expect(find.byType(MobileNoteEditorScreen), findsOneWidget);
      expect(find.byType(MobileShell), findsNothing);

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
