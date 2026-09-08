import 'package:powersync/powersync.dart' as powersync;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/connection/connection_native.dart';
import 'app_sync_status.dart';
import 'sync_connector.dart';

/// Connects PowerSync to the sync service, using the current Supabase
/// session for auth (see `SupabaseSyncConnector.fetchCredentials`).
/// Call on sign-in; call [disconnectSync] on sign-out.
Future<void> connectSync({required String powerSyncUrl}) async {
  final db = await getPowerSyncDatabase();
  await db.connect(
    connector: SupabaseSyncConnector(
      Supabase.instance.client,
      powerSyncUrl: powerSyncUrl,
    ),
  );
}

Future<void> disconnectSync() async {
  final db = await getPowerSyncDatabase();
  await db.disconnect();
}

Stream<AppSyncStatus> watchSyncStatus() async* {
  final db = await getPowerSyncDatabase();
  yield _toAppStatus(db.currentStatus);
  yield* db.statusStream.map(_toAppStatus);
}

AppSyncStatus _toAppStatus(powersync.SyncStatus status) {
  return AppSyncStatus(
    connected: status.connected,
    uploading: status.uploading,
    downloading: status.downloading,
    lastSyncedAt: status.lastSyncedAt,
    hasError: status.uploadError != null || status.downloadError != null,
  );
}
