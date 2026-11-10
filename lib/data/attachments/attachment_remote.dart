import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sync_remote.dart';

/// Where attachments are stored on the server: the private `attachments`
/// bucket in Supabase Storage, under `<user id>/<attachment id>` (see
/// supabase/migrations/…_attachments.sql for who may read/write what).
abstract interface class AttachmentRemote {
  Future<void> upload(String id, Uint8List bytes, String mimeType);

  Future<Uint8List> download(String id);
}

class SupabaseAttachmentRemote implements AttachmentRemote {
  SupabaseAttachmentRemote(this._client);

  final SupabaseClient _client;

  static const bucket = 'attachments';

  String _path(String id) {
    final user = _client.auth.currentUser;
    if (user == null) throw const SyncNotSignedInException();
    return '${user.id}/$id';
  }

  @override
  Future<void> upload(String id, Uint8List bytes, String mimeType) {
    return _client.storage
        .from(bucket)
        .uploadBinary(
          _path(id),
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
  }

  @override
  Future<Uint8List> download(String id) =>
      _client.storage.from(bucket).download(_path(id));
}
