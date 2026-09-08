import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/app_sync_status.dart';
import '../sync/sync_coordinator.dart';
import 'auth_provider.dart';

// Self-hosted PowerSync's default Docker Compose port — see the "Online
// sync + Auth" plan's Phase E (not yet stood up/confirmed against a real
// running instance). Override with `--dart-define=POWERSYNC_URL=...`,
// same pattern as SUPABASE_URL in main.dart.
const _powerSyncUrl = String.fromEnvironment(
  'POWERSYNC_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

final syncStatusProvider = StreamProvider<AppSyncStatus>((ref) {
  return watchSyncStatus();
});

/// Connects/disconnects PowerSync as the signed-in user changes. Has no
/// meaningful return value — it exists to be watched once (from
/// `NooteApp.build()`) so its `ref.listen` side effect stays registered
/// for the app's lifetime.
final syncCoordinatorProvider = Provider<void>((ref) {
  ref.listen<User?>(
    currentUserProvider,
    (previous, user) {
      if (user != null) {
        connectSync(powerSyncUrl: _powerSyncUrl);
      } else {
        disconnectSync();
      }
    },
    fireImmediately: true,
  );
});
