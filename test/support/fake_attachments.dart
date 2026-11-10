import 'dart:io';
import 'dart:typed_data';

import 'package:noote/data/attachments/attachment_remote.dart';
import 'package:noote/data/attachments/attachment_store.dart';
import 'package:noote/data/database/app_database.dart';

/// Supabase Storage stand-in: keeps uploads in memory.
class FakeAttachmentRemote implements AttachmentRemote {
  final files = <String, Uint8List>{};
  Object? failWith;
  var uploads = 0;

  @override
  Future<void> upload(String id, Uint8List bytes, String mimeType) async {
    if (failWith case final error?) throw error;
    uploads++;
    files[id] = bytes;
  }

  @override
  Future<Uint8List> download(String id) async {
    if (failWith case final error?) throw error;
    final bytes = files[id];
    if (bytes == null) throw StateError('No such file: $id');
    return bytes;
  }
}

/// An [AttachmentStore] writing to a fresh temp folder.
Future<(AttachmentStore, FakeAttachmentRemote, Directory)> testAttachmentStore(
  AppDatabase db,
) async {
  final dir = await Directory.systemTemp.createTemp('noote_attachments');
  final remote = FakeAttachmentRemote();
  return (AttachmentStore(db, remote, directory: () async => dir), remote, dir);
}
