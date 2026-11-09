import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _fileName = 'noote_local.sqlite';

/// A plain SQLite file owned by drift. Sync with Supabase is done by app
/// code (lib/data/sync/sync_service.dart), not by the database layer.
///
/// Kept in the app's private data folder (Application Support on macOS,
/// AppData\Roaming on Windows), not Documents: on Windows, Documents is
/// visible to the user and often synced by OneDrive, which can lock or
/// corrupt a live database. A file left in Documents by an earlier version
/// is moved over the first time ([moveFromDocumentsIfNeeded]).
///
/// `noote.powersync.sqlite` (PowerSync era) and `noote.sqlite` (before
/// that) have different layouts and are left behind untouched.
DatabaseConnection connect() {
  return DatabaseConnection(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, _fileName));
      await moveFromDocumentsIfNeeded(
        from: (await getApplicationDocumentsDirectory()).path,
        to: dir.path,
      );
      return NativeDatabase.createInBackground(file);
    }),
  );
}

/// Moves `noote_local.sqlite` (and SQLite's `-wal`/`-shm` side files, which
/// hold recent writes) from [from] to [to], unless [to] already has one.
@visibleForTesting
Future<void> moveFromDocumentsIfNeeded({
  required String from,
  required String to,
}) async {
  if (p.equals(from, to)) return;
  final old = File(p.join(from, _fileName));
  if (!await old.exists() || await File(p.join(to, _fileName)).exists()) {
    return;
  }
  for (final suffix in const ['', '-wal', '-shm']) {
    final source = File(p.join(from, '$_fileName$suffix'));
    if (!await source.exists()) continue;
    final target = p.join(to, '$_fileName$suffix');
    try {
      await source.rename(target);
    } on FileSystemException {
      // Different drive: copy, then remove the original.
      await source.copy(target);
      await source.delete();
    }
  }
}
