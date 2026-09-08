import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_screen.dart';
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
  routes: [
    GoRoute(
      path: '/sign-in',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/trash',
      builder: (context, state) => const TrashScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const AdaptiveShellScreen(currentPath: '/'),
    ),
    GoRoute(
      path: '/notes/:noteId',
      builder: (context, state) => AdaptiveShellScreen(
        currentPath: '/',
        noteId: state.pathParameters['noteId'],
      ),
    ),
    GoRoute(
      path: '/folders',
      builder: (context, state) =>
          const AdaptiveShellScreen(currentPath: '/folders'),
    ),
    GoRoute(
      path: '/shared',
      builder: (context, state) =>
          const AdaptiveShellScreen(currentPath: '/shared'),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) =>
          const AdaptiveShellScreen(currentPath: '/settings'),
    ),
  ],
);
