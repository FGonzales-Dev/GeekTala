import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

// Defaults point at the local Supabase stack (`supabase start`) — never
// the hosted project, per noote-plan.md §9. Override with
// `--dart-define=SUPABASE_URL=...` / `SUPABASE_ANON_KEY=...` for
// staging/prod. Android emulators can't reach the host's `127.0.0.1`
// directly — use `--dart-define=SUPABASE_URL=http://10.0.2.2:54321`
// there instead.
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  runApp(const ProviderScope(child: NooteApp()));
}
