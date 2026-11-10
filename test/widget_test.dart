import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:noote/app.dart';
import 'package:noote/core/router/app_router.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/providers/database_provider.dart';
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/sync/app_sync_status.dart';

void main() {
  testWidgets('renders the notes list on a desktop-sized surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // runAsync lets real async work (Drift's background-isolate round-trip,
    // and its internal stream-debounce Timer) actually complete in real
    // time, instead of racing pumpAndSettle's fake-clock frame scheduling.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            // Both touch Supabase (real auth/network calls), which isn't
            // available under flutter test and doesn't matter for what this
            // test checks (local note rendering).
            syncStatusProvider.overrideWithValue(AppSyncStatus.idle),
            syncCoordinatorProvider.overrideWith((ref) {}),
            // The real router gates everything behind a signed-in
            // Supabase session (see app_router.dart), which needs a real
            // network round-trip `flutter test` blocks outright — this
            // test is about local note rendering, not auth, so it bypasses
            // the gate with a router that has no redirect at all.
            goRouterProvider.overrideWithValue(
              GoRouter(initialLocation: '/', routes: appRoutes),
            ),
          ],
          child: const NooteApp(),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('Engineering').evaluate().isNotEmpty) break;
      }

      expect(find.text('Engineering'), findsWidgets);
      expect(find.text('Local-First Sync Architecture'), findsWidgets);

      // Unmount (disposing the ProviderScope, which cancels Drift's
      // streams) while still inside runAsync, then give its internal
      // debounce Timer a real moment to fire before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}
