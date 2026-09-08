import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import '../../sync/powersync_schema.dart';

PowerSyncDatabase? _instance;

/// The single [PowerSyncDatabase] backing the app — shared between [connect]
/// (which Drift reads/writes through) and `sync_coordinator_native.dart`
/// (which calls `.connect()`/`.disconnect()` on it as auth state changes).
/// PowerSync's own docs are explicit that only one instance per database
/// file should be open at a time, so this is deliberately a singleton
/// rather than something each call site opens independently.
Future<PowerSyncDatabase> getPowerSyncDatabase() async {
  final existing = _instance;
  if (existing != null) return existing;

  final dbFolder = await getApplicationDocumentsDirectory();
  // A distinct filename from the pre-sync `noote.sqlite` — PowerSync
  // bootstraps its own internal bookkeeping tables in this file alongside
  // the schema-defined views, so it shouldn't share a file with one created
  // by a plain `NativeDatabase` that never knew about PowerSync (pre-dates
  // this — local dev data from before this change is left behind, not
  // migrated forward; nothing worth carrying over yet at this stage).
  final path = p.join(dbFolder.path, 'noote.powersync.sqlite');
  final db = PowerSyncDatabase(schema: powerSyncSchema, path: path);
  await db.initialize();
  _instance = db;
  return db;
}

DatabaseConnection connect() {
  return DatabaseConnection.delayed(
    getPowerSyncDatabase().then(SqliteAsyncDriftConnection.new),
  );
}
