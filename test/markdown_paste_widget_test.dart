import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:noote/app.dart';
import 'package:noote/core/router/app_router.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/providers/database_provider.dart';
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/sync/app_sync_status.dart';

/// Pasting Markdown in the real desktop editor (see widget_test.dart for
/// why everything runs inside `runAsync`).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() => AppFlowyClipboard.mockSetData(null));

  testWidgets('paste Markdown, then switch it to the raw text', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    Future<void> settle([int frames = 6]) async {
      for (var i = 0; i < frames; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<String> savedBody() async {
      final note = (await db.notesDao.getNotesByIds(['grocery-list'])).single;
      return [
        for (final child in note.bodyJson['document']['children'] as List)
          ((child as Map)['data']?['delta'] as List? ?? [])
              .map((op) => (op as Map)['insert'])
              .join(),
      ].join('\n');
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncStatusProvider.overrideWithValue(AppSyncStatus.idle),
            syncCoordinatorProvider.overrideWith((ref) {}),
            goRouterProvider.overrideWithValue(
              GoRouter(
                initialLocation: '/notes/grocery-list',
                routes: appRoutes,
              ),
            ),
          ],
          child: const NooteApp(),
        ),
      );
      for (
        var i = 0;
        i < 40 && find.text('Eggs', findRichText: true).evaluate().isEmpty;
        i++
      ) {
        await settle(1);
      }

      // Click at the end of the last list item, then paste.
      final eggs = tester.getRect(find.text('Eggs', findRichText: true).last);
      await tester.tapAt(eggs.centerRight + const Offset(-1, 0));
      await settle();
      AppFlowyClipboard.mockSetData(
        AppFlowyClipboardData(text: '## Also\n- **ripe** tomatoes\n- bread'),
      );
      // The editor picks ⌘V or Ctrl+V from the OS the test runs on.
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(modifier);
      await settle();

      expect(find.text('Pasted as formatted text'), findsOneWidget);
      expect(
        find.text('Also', findRichText: true),
        findsOneWidget,
      ); // a heading, no "##"

      await tester.tap(find.text('Show as Markdown'));
      await settle(10); // past the 500 ms save debounce
      expect(find.text('Pasted as Markdown text'), findsOneWidget);
      expect(await savedBody(), contains('- **ripe** tomatoes'));

      await tester.tap(find.text('Show formatted'));
      await settle(10);
      final body = await savedBody();
      expect(body, contains('ripe tomatoes'));
      expect(body, isNot(contains('**')));

      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}
