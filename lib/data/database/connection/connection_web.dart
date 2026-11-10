import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

// Wrapped in a plain DatabaseConnection only so the signature matches the
// conditional export in connection.dart. Sync (lib/data/sync/) is plain
// Supabase + drift calls, so it works here the same as on native.
DatabaseConnection connect() {
  return DatabaseConnection(
    LazyDatabase(() async {
      final result = await WasmDatabase.open(
        databaseName: 'noote',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  );
}
