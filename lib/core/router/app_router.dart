import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_screen.dart';
import '../utils/breakpoints.dart';
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
final List<RouteBase> appRoutes = [
  GoRoute(path: '/sign-in', builder: (context, state) => const AuthScreen()),
  GoRoute(path: '/trash', builder: (context, state) => const TrashScreen()),
  GoRoute(
    path: '/',
    pageBuilder: (context, state) =>
        _mainPage(context, state, const AdaptiveShellScreen(currentPath: '/')),
  ),
  GoRoute(
    path: '/notes/:noteId',
    pageBuilder: (context, state) => _mainPage(
      context,
      state,
      AdaptiveShellScreen(
        currentPath: '/',
        noteId: state.pathParameters['noteId'],
      ),
      fullScreenOnMobile: true,
    ),
  ),
  for (final tab in const ['/folders', '/shared', '/settings'])
    GoRoute(
      path: tab,
      pageBuilder: (context, state) =>
          _mainPage(context, state, AdaptiveShellScreen(currentPath: tab)),
    ),
];

/// The page for one of the main screen's routes.
///
/// These routes are one screen shown different ways, so they share a page:
/// same key and type means the Navigator updates the existing page in place
/// when the route changes, rather than sliding in a fresh copy of the whole
/// window (which also threw away scroll positions and selection).
/// - Desktop: all of them are the same window (sidebar, list, editor).
/// - Mobile: the bottom-nav tabs share one page (so the tabs' IndexedStack
///   keeps their state); a note opens full screen on its own page, with the
///   usual slide.
Page<void> _mainPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  bool fullScreenOnMobile = false,
}) {
  if (isDesktop(context)) {
    return NoTransitionPage(key: const ValueKey('main-window'), child: child);
  }
  if (!fullScreenOnMobile) {
    return NoTransitionPage(key: const ValueKey('mobile-tabs'), child: child);
  }
  return MaterialPage(key: state.pageKey, name: state.name, child: child);
}
