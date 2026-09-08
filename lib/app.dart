import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers/sync_provider.dart';
import 'features/settings/theme_mode_provider.dart';

class NooteApp extends ConsumerWidget {
  const NooteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    // Keeps syncCoordinatorProvider's ref.listen (connect/disconnect
    // PowerSync as auth state changes) alive for the app's lifetime.
    ref.watch(syncCoordinatorProvider);

    return MaterialApp.router(
      title: 'Noote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: ref.watch(goRouterProvider),
      localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
    );
  }
}
