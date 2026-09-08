/// A trimmed-down, platform-agnostic view of PowerSync's own `SyncStatus` —
/// kept separate so `sync_coordinator.dart`'s public API (used from shared
/// UI code) doesn't leak a PowerSync-specific type into files that need to
/// compile on platforms where sync isn't wired up yet (see
/// `sync_coordinator_unsupported.dart`).
class AppSyncStatus {
  const AppSyncStatus({
    required this.connected,
    required this.uploading,
    required this.downloading,
    required this.lastSyncedAt,
    required this.hasError,
  });

  static const disconnected = AppSyncStatus(
    connected: false,
    uploading: false,
    downloading: false,
    lastSyncedAt: null,
    hasError: false,
  );

  final bool connected;
  final bool uploading;
  final bool downloading;
  final DateTime? lastSyncedAt;
  final bool hasError;
}
