import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Emits on every sign-in/sign-out/token-refresh. `app_router.dart`'s
/// `GoRouterRefreshStream` listens to the same underlying stream directly
/// (redirect logic can't depend on a provider), so this is for widgets
/// that just need to react to auth state — e.g. `SettingsBody`.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// The signed-in user, or `null`. Falls back to the synchronous
/// `currentUser` getter so there's a correct value before the stream's
/// first event (session restore already happened in `main()`, before
/// `runApp` — see `Supabase.initialize()` there).
final currentUserProvider = Provider<User?>((ref) {
  final fromStream = ref.watch(authStateChangesProvider).value;
  if (fromStream != null) return fromStream.session?.user;
  return ref.watch(supabaseClientProvider).auth.currentUser;
});
