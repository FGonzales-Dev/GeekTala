import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

// The production Supabase project. The publishable key is meant to ship
// inside apps (row-level security protects the data), so it lives here.
// To run against another project — e.g. the local stack from
// `supabase start` — override both with `--dart-define=SUPABASE_URL=…
// --dart-define=SUPABASE_PUBLISHABLE_KEY=…` or `--dart-define-from-file`.
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://aascyfarypophesyvwqg.supabase.co',
);
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_7UAIh5sGuOVclJOX7gTATQ__1taeYb7',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  runApp(const ProviderScope(child: NooteApp()));
}
