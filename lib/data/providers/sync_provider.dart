import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/daos/sync_dao.dart';
import '../sync/app_sync_status.dart';
import '../sync/pending_writes.dart';
import '../sync/sync_remote.dart';
import '../sync/sync_service.dart';
import 'attachments_provider.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'device_settings_provider.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(appDatabaseProvider),
    SupabaseSyncRemote(ref.watch(supabaseClientProvider)),
    attachments: ref.watch(attachmentStoreProvider),
  );
});

/// What an upload/download is doing right now, and how the last one went.
class SyncActivity {
  const SyncActivity({
    this.uploading = false,
    this.downloading = false,
    this.error,
    this.notice,
    this.downloadCount = 0,
  });

  final bool uploading;
  final bool downloading;
  final String? error;
  final String? notice;

  /// Bumped after every successful download, so an open note editor
  /// knows to reload instead of saving its stale copy over the new one.
  final int downloadCount;

  bool get busy => uploading || downloading;
}

class SyncController extends Notifier<SyncActivity> {
  @override
  SyncActivity build() => const SyncActivity();

  SyncService get _service => ref.read(syncServiceProvider);

  /// Returns whether the upload succeeded.
  Future<bool> upload() {
    return _run(uploading: true, () async {
      final result = await _service.upload();
      final skipped = result.skipped;
      if (skipped == 0) return null;
      return '$skipped ${skipped == 1 ? 'item was' : 'items were'} newer on '
          'the server and kept there. Download to get the newer version.';
    });
  }

  /// Returns whether the download succeeded.
  Future<bool> download({bool discardLocalChanges = false}) {
    return _run(downloading: true, downloaded: () => true, () async {
      await _service.download(discardLocalChanges: discardLocalChanges);
      return null;
    });
  }

  /// Automatic sync when the app opens (or comes back after a while):
  /// uploads anything waiting, then fetches the server's copy. Returns
  /// whether it all succeeded.
  Future<bool> syncOnOpen() async {
    final pending = await ref.read(appDatabaseProvider).syncDao.pendingCount();
    if (pending > 0 && !await upload()) return false;
    var downloaded = false;
    return _run(downloading: true, downloaded: () => downloaded, () async {
      try {
        await _service.download();
        downloaded = true;
      } on UnsyncedChangesException {
        // Edited since the upload above; that goes up with the next
        // automatic upload, and the next open fetches.
      }
      return null;
    });
  }

  /// Returns whether a different account signed in, whose notes were
  /// then downloaded (so there's no need for [syncOnOpen] right after).
  Future<bool> onSignedIn(String userId) async {
    final bool switched;
    try {
      switched = await _service.adoptAccount(userId);
    } catch (e, stack) {
      _fail(e, stack);
      return false;
    }
    if (!switched) return false;
    await _run(downloading: true, downloaded: () => true, () async {
      await _service.downloadForNewAccount();
      return null;
    });
    return true;
  }

  /// [action] returns a notice to show, or null. [downloaded] says, once
  /// it's done, whether local data was replaced (open editors reload).
  Future<bool> _run(
    Future<String?> Function() action, {
    bool uploading = false,
    bool downloading = false,
    bool Function()? downloaded,
  }) async {
    if (state.busy) return false;
    final count = state.downloadCount;
    state = SyncActivity(
      uploading: uploading,
      downloading: downloading,
      downloadCount: count,
    );
    try {
      await ref.read(pendingWritesProvider).flushAll();
      final notice = await action();
      state = SyncActivity(
        notice: notice,
        downloadCount: (downloaded?.call() ?? false) ? count + 1 : count,
      );
      return true;
    } catch (e, stack) {
      _fail(e, stack);
      return false;
    }
  }

  void _fail(Object error, StackTrace stack) {
    debugPrint('Sync failed: $error\n$stack');
    state = SyncActivity(
      error: _describe(error),
      downloadCount: state.downloadCount,
    );
  }

  static String _describe(Object error) => switch (error) {
    PostgrestException(:final message) => message,
    AuthException(:final message) => message,
    UnsyncedChangesException() ||
    SyncNotSignedInException() => error.toString(),
    _ => 'Couldn\'t reach the server ($error).',
  };
}

final syncControllerProvider = NotifierProvider<SyncController, SyncActivity>(
  SyncController.new,
);

final _pendingChangesProvider = StreamProvider<int>((ref) {
  return ref.watch(appDatabaseProvider).syncDao.watchPendingCount();
});

final _syncStateProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(appDatabaseProvider).syncDao.watchState();
});

final syncStatusProvider = Provider<AppSyncStatus>((ref) {
  final activity = ref.watch(syncControllerProvider);
  final stored = ref.watch(_syncStateProvider).value ?? const {};
  DateTime? time(String key) => DateTime.tryParse(stored[key] ?? '')?.toLocal();

  return AppSyncStatus(
    pendingChanges: ref.watch(_pendingChangesProvider).value ?? 0,
    uploading: activity.uploading,
    downloading: activity.downloading,
    lastUploadedAt: time(SyncDao.lastUploadedAtKey),
    lastDownloadedAt: time(SyncDao.lastDownloadedAtKey),
    error: activity.error,
    notice: activity.notice,
  );
});

/// How long after changes appear the automatic upload runs. Shortened by
/// tests.
@visibleForTesting
Duration autoUploadDelay = const Duration(seconds: 5);

/// Settings → "Sync automatically" (on unless turned off).
final autoSyncEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
        deviceSettingsProvider.select(
          (s) => s.value?[DeviceSettingKeys.autoSync],
        ),
      ) !=
      'off';
});

Future<void> setAutoSyncEnabled(WidgetRef ref, bool enabled) {
  return ref.read(writeDeviceSettingProvider)(
    DeviceSettingKeys.autoSync,
    enabled ? 'on' : 'off',
  );
}

/// Tells sync which account is signed in, so another account's local notes
/// are never uploaded into it (see `SyncService.adoptAccount`), and runs
/// automatic sync ([_AutoSync]). Watched once from `NooteApp.build()` to
/// keep it alive.
final syncCoordinatorProvider = Provider<void>((ref) {
  final auto = _AutoSync(ref);
  ref.onDispose(auto.dispose);

  ref.listen<User?>(currentUserProvider, (previous, user) {
    if (user?.id == previous?.id && previous != null) return;
    auto.signedOut();
    if (user == null) return;
    // Not during this provider's build: Riverpod doesn't allow changing
    // another provider's state there.
    Future.microtask(() async {
      final switched = await ref
          .read(syncControllerProvider.notifier)
          .onSignedIn(user.id);
      auto.accountReady(syncNow: !switched);
    });
  }, fireImmediately: true);

  ref.listen<int>(
    _pendingChangesProvider.select((count) => count.value ?? 0),
    (_, count) => auto.pendingChanged(count),
  );
  ref.listen<bool>(autoSyncEnabledProvider, (_, enabled) {
    if (enabled) auto.syncOpenSoon();
  });
});

/// Automatic sync, unless turned off in Settings:
/// - uploads [autoUploadDelay] after changes appear (retrying with back-off
///   if that fails, e.g. offline);
/// - uploads right away when the app goes to the background;
/// - when the app opens, and when it comes back after [_resyncAfter],
///   uploads anything waiting and then downloads the server's copy.
///
/// Nothing runs until the signed-in account has been adopted
/// ([accountReady]) — before that, local notes might be another account's.
class _AutoSync {
  _AutoSync(this._ref) {
    _lifecycle = AppLifecycleListener(
      onResume: _onResume,
      onHide: _onHide,
    );
  }

  static Duration get _uploadDelay => autoUploadDelay;
  static const _resyncAfter = Duration(minutes: 5);
  static const _maxBackoff = Duration(minutes: 5);

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;
  Timer? _uploadTimer;
  bool _ready = false;
  bool _cleanedUp = false;
  int _failures = 0;
  DateTime? _lastOpenSync;

  bool get _on => _ready && _ref.read(autoSyncEnabledProvider);

  SyncController get _controller => _ref.read(syncControllerProvider.notifier);

  void accountReady({required bool syncNow}) {
    _ready = true;
    if (!_cleanedUp) {
      // Once per app run: drop image files no note uses any more.
      _cleanedUp = true;
      unawaited(
        _ref
            .read(attachmentStoreProvider)
            .collectGarbage()
            .catchError((Object _) => 0),
      );
    }
    if (!_on) return;
    if (syncNow) {
      unawaited(_openSync());
    } else {
      _lastOpenSync = DateTime.now();
      _scheduleUpload(_uploadDelay);
    }
  }

  void signedOut() {
    _ready = false;
    _uploadTimer?.cancel();
    _failures = 0;
    _lastOpenSync = null;
  }

  /// Auto sync was just turned on.
  void syncOpenSoon() {
    if (_on) unawaited(_openSync());
  }

  void pendingChanged(int count) {
    // Only start the timer; resetting it on every change would put off
    // uploading for as long as someone keeps typing.
    if (count > 0 && _on && _uploadTimer?.isActive != true) {
      _scheduleUpload(_uploadDelay);
    }
  }

  void _scheduleUpload(Duration delay) {
    _uploadTimer?.cancel();
    _uploadTimer = Timer(delay, _upload);
  }

  Future<void> _upload() async {
    if (!_on) return;
    if (_ref.read(syncControllerProvider).busy) {
      _scheduleUpload(const Duration(seconds: 2));
      return;
    }
    final pending = await _pendingCount();
    if (pending == 0) return;
    if (await _controller.upload()) {
      _failures = 0;
      // Edits made during the upload.
      if (await _pendingCount() > 0) _scheduleUpload(_uploadDelay);
    } else {
      _failures++;
      final backoff = _uploadDelay * (1 << _failures.clamp(0, 6));
      _scheduleUpload(backoff > _maxBackoff ? _maxBackoff : backoff);
    }
  }

  Future<void> _openSync() async {
    if (_ref.read(syncControllerProvider).busy) return;
    _uploadTimer?.cancel();
    _lastOpenSync = DateTime.now();
    await _controller.syncOnOpen();
    if (_on && await _pendingCount() > 0) _scheduleUpload(_uploadDelay);
  }

  void _onResume() {
    final last = _lastOpenSync;
    if (_on && (last == null || DateTime.now().difference(last) > _resyncAfter)) {
      unawaited(_openSync());
    }
  }

  void _onHide() {
    if (_on && _uploadTimer?.isActive == true) {
      _uploadTimer!.cancel();
      unawaited(_upload());
    }
  }

  Future<int> _pendingCount() =>
      _ref.read(appDatabaseProvider).syncDao.pendingCount();

  void dispose() {
    _uploadTimer?.cancel();
    _lifecycle.dispose();
  }
}
