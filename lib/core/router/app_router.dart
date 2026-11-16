import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/folders/mobile_folders_home.dart';
import '../../features/note_editor/widgets/mobile_note_editor_screen.dart';
import '../../features/notes_list/widgets/mobile_folder_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/adaptive_shell_screen.dart';
import '../../features/trash/trash_screen.dart';

/// Adapts a Stream into a Listenable so go_router's `redirect` re-runs on
/// every auth change — go_router polls `refreshListenable`, not a stream
/// or a Riverpod provider, directly.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// A provider (not a bare top-level singleton) so tests can override it
/// with an auth-free router — `Supabase.instance` requires a real network
/// round-trip to sign in, which `flutter test` blocks outright (it stubs
/// every HttpClient), so widget tests unrelated to auth need to bypass
/// this entirely rather than trying to authenticate for real.
final goRouterProvider = Provider<GoRouter>((ref) => _buildRouter());

GoRouter _buildRouter() => GoRouter(
  refreshListenable: GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  ),
  redirect: (context, state) {
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    final goingToSignIn = state.matchedLocation == '/sign-in';
    if (!signedIn && !goingToSignIn) return '/sign-in';
    if (signedIn && goingToSignIn) return '/';
    return null;
  },
  routes: appRoutes,
);

/// Every route, without the sign-in redirect — widget tests build a router
/// from these directly.
///
/// On phones the app drills down like Apple Notes — Folders (`/`) → a
/// folder (`/folders/:id`, `all` for All Notes) or tag (`/tags/:id`) → a
/// note — with each screen pushed over the last (see
/// `core/router/navigation.dart`), so Back walks back up. Settings and
/// Recently Deleted are pushed screens too. Desktop shows all of it in one
/// window, whatever the route.
final List<RouteBase> appRoutes = [
  GoRoute(path: '/sign-in', builder: (context, state) => const AuthScreen()),
  GoRoute(path: '/trash', builder: (context, state) => const TrashScreen()),
  GoRoute(
    path: '/',
    pageBuilder: (context, state) => _mainPage(
      context,
      state,
      const AdaptiveShellScreen(mobile: MobileFoldersHome()),
    ),
  ),
  GoRoute(
    path: '/notes/:noteId',
    pageBuilder: (context, state) {
      final noteId = state.pathParameters['noteId']!;
      return _mainPage(
        context,
        state,
        AdaptiveShellScreen(
          noteId: noteId,
          mobile: MobileNoteEditorScreen(
            noteId: noteId,
            backLabel: state.extra as String?,
          ),
        ),
      );
    },
  ),
  GoRoute(
    path: '/folders/:folderId',
    pageBuilder: (context, state) {
      final id = state.pathParameters['folderId']!;
      return _mainPage(
        context,
        state,
        AdaptiveShellScreen(
          mobile: MobileFolderScreen(
            scope: id == 'all' ? const AllNotesScope() : FolderScope(id),
            backLabel: state.extra as String?,
          ),
        ),
      );
    },
  ),
  GoRoute(
    path: '/tags/:tagId',
    pageBuilder: (context, state) => _mainPage(
      context,
      state,
      AdaptiveShellScreen(
        mobile: MobileFolderScreen(
          scope: TagScope(state.pathParameters['tagId']!),
          backLabel: state.extra as String?,
        ),
      ),
    ),
  ),
  GoRoute(
    path: '/settings',
    pageBuilder: (context, state) => _mainPage(
      context,
      state,
      const AdaptiveShellScreen(mobile: SettingsScreen()),
    ),
  ),
];

/// Whether [state]'s page was pushed (`context.push`) rather than reached
/// with `go`. go_router keys a `go` page by its route path (which starts
/// with `/`) and a pushed one with a random key.
bool _wasPushed(GoRouterState state) => !state.pageKey.value.startsWith('/');

/// The page for one of the main routes.
///
/// Every page reached with `go` is the same page (`main-window`): same key
/// and type means the Navigator updates it in place when the route changes,
/// instead of sliding in a fresh copy (which threw away scroll positions and
/// selection). That's how desktop works — one window (sidebar, list,
/// editor) for every route — and it also means a window resized between
/// phone and desktop width keeps its pages rather than replacing them.
///
/// Phones push each screen they drill into; those get their own key, and
/// the usual transition.
Page<void> _mainPage(BuildContext context, GoRouterState state, Widget child) {
  return MaterialPage(
    key: _wasPushed(state) ? state.pageKey : const ValueKey('main-window'),
    name: state.name,
    child: child,
  );
}
