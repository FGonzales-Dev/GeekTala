import 'app_sync_status.dart';

// Web isn't wired to PowerSync yet (see the "Online sync + Auth" plan's
// Phase C note) — these are no-ops rather than throwing, so the app still
// runs on web, just without sync, instead of crashing on startup.
Future<void> connectSync({required String powerSyncUrl}) async {}

Future<void> disconnectSync() async {}

Stream<AppSyncStatus> watchSyncStatus() => Stream.value(AppSyncStatus.disconnected);
