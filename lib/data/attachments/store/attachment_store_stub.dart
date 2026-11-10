import 'dart:typed_data';

import '../../database/app_database.dart';
import '../attachment_remote.dart';

/// Web: no file system yet, so no attachments (noote-plan.md: Phase 3).
const attachmentsSupported = false;

class AttachmentStore {
  /// Same signature as the native store; [directory] is unused here.
  AttachmentStore(
    this._db,
    this._remote, {
    Future<Object> Function()? directory,
  });

  // Kept so the constructor matches the native one.
  // ignore: unused_field
  final AppDatabase _db;
  // ignore: unused_field
  final AttachmentRemote _remote;

  Future<String> addImage(Uint8List bytes, {required String fileName}) =>
      throw UnsupportedError('Attachments need a file system.');

  Future<String> addImageFile(String path) =>
      throw UnsupportedError('Attachments need a file system.');

  /// A dart:io `File` on other platforms; never anything here.
  Future<Object?> ensureLocal(String id) async => null;

  Future<String?> ensureLocalPath(String id) async => null;

  Future<int> uploadPending() async => 0;

  Future<int> collectGarbage({Duration grace = Duration.zero}) async => 0;

  Future<void> clearAll() async {}
}
