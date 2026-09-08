import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

// Not yet wired to PowerSync — web sync support needs a currency check
// (see the "Online sync + Auth" plan's Phase C note) before repeating the
// native connection_native.dart treatment here. Wrapped in a plain
// DatabaseConnection only so the signature matches the conditional export
// in connection.dart; behavior is otherwise unchanged from before Phase C.
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
