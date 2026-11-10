/// Everything the UI shows about sync: what's waiting to upload, whether
/// an upload/download is running, and how the last one went.
class AppSyncStatus {
  const AppSyncStatus({
    required this.pendingChanges,
    required this.uploading,
    required this.downloading,
    required this.lastUploadedAt,
    required this.lastDownloadedAt,
    required this.error,
    required this.notice,
  });

  static const idle = AppSyncStatus(
    pendingChanges: 0,
    uploading: false,
    downloading: false,
    lastUploadedAt: null,
    lastDownloadedAt: null,
    error: null,
    notice: null,
  );

  /// Records changed locally since the last upload.
  final int pendingChanges;
  final bool uploading;
  final bool downloading;
  final DateTime? lastUploadedAt;
  final DateTime? lastDownloadedAt;

  /// Why the last upload/download failed, if it did.
  final String? error;

  /// Something worth telling the user after a successful run, e.g. that
  /// some notes were newer on the server.
  final String? notice;

  bool get busy => uploading || downloading;
  bool get hasError => error != null;

  DateTime? get lastSyncedAt {
    final up = lastUploadedAt;
    final down = lastDownloadedAt;
    if (up == null) return down;
    if (down == null) return up;
    return up.isAfter(down) ? up : down;
  }
}
