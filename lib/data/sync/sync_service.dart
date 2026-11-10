import 'dart:convert';

import 'package:drift/drift.dart';

import '../attachments/attachment_store.dart';
import '../database/app_database.dart';
import '../database/daos/sync_dao.dart';
import '../models/title_style_run.dart';
import 'sync_remote.dart';

/// Manual sync between the local database and Supabase — no sync server.
///
/// - [upload] sends what changed locally (the outbox filled by the
///   triggers in lib/data/database/sync.drift) to the `push_changes` RPC.
/// - [download] replaces all local data with the server's copy.
/// - [adoptAccount] keeps one account's notes from being uploaded into
///   another account that signs in on the same device.
class SyncService {
  SyncService(this._db, this._remote, {this.attachments});

  final AppDatabase _db;
  final SyncRemote _remote;

  /// Files notes show (images); uploaded before the notes that use them.
  final AttachmentStore? attachments;

  SyncDao get _dao => _db.syncDao;

  /// Per `push_changes` request. Each request is one server transaction.
  static const maxBatchChanges = 100;
  static const maxBatchBytes = 512 * 1024;

  /// Folders the app assumes always exist (`protectedFolderIds` in
  /// models/folder.dart, and "move notes to Personal" on folder delete).
  static const _protectedFolders = {'personal': 'Personal', 'shared': 'Shared'};

  // ---------------------------------------------------------------------
  // Upload
  // ---------------------------------------------------------------------

  Future<UploadResult> upload() async {
    // Files first: a note must never reach the server (and from there
    // another device) pointing at a file the server doesn't have. If one
    // fails, this throws and nothing else is sent.
    await attachments?.uploadPending();

    final entries = await _inUploadOrder(await _dao.outboxEntries());

    var uploaded = 0;
    var skipped = 0;
    final batch = <Map<String, Object?>>[];
    final batchSeqs = <int>[];
    var batchBytes = 0;

    Future<void> send() async {
      if (batch.isNotEmpty) {
        skipped += await _remote.pushChanges(List.of(batch));
        uploaded += batch.length;
      }
      // Only after the server accepted the batch: a failed request leaves
      // these entries queued for the next attempt.
      await _dao.deleteOutboxEntries(batchSeqs);
      batch.clear();
      batchSeqs.clear();
      batchBytes = 0;
    }

    for (final entry in entries) {
      final change = await _changeFor(entry);
      if (change == null) {
        // The record vanished after it was queued; its delete (if any) is
        // a newer outbox entry. Drop this one with the current batch.
        batchSeqs.add(entry.seq);
        continue;
      }
      final size = jsonEncode(change).length;
      if (batch.isNotEmpty &&
          (batch.length >= maxBatchChanges ||
              batchBytes + size > maxBatchBytes)) {
        await send();
      }
      batch.add(change);
      batchSeqs.add(entry.seq);
      batchBytes += size;
    }
    await send();

    await _dao.writeState(SyncDao.lastUploadedAtKey, _nowIso());
    return UploadResult(uploaded: uploaded, skipped: skipped);
  }

  /// Requests are separate transactions on the server, so a row must never
  /// arrive in an earlier request than a row it points at: folders
  /// (parents first), then tags, notes, note–tag links. Deletes go last,
  /// in reverse.
  Future<List<SyncOutboxEntry>> _inUploadOrder(
    List<SyncOutboxEntry> entries,
  ) async {
    const tableRank = {'folders': 0, 'tags': 1, 'notes': 2, 'notes_tags': 3};
    int rank(SyncOutboxEntry e) {
      final table = tableRank[e.entity] ?? 4;
      return e.op == 'delete' ? 10 + (4 - table) : table;
    }

    final folders = await _db.select(_db.foldersTable).get();
    final parentOf = {for (final f in folders) f.id: f.parentId};
    int depth(String id) {
      var depth = 0;
      final seen = {id};
      for (var p = parentOf[id]; p != null && seen.add(p); p = parentOf[p]) {
        depth++;
      }
      return depth;
    }

    return [...entries]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      if (a.entity == 'folders' && a.op == 'upsert') {
        final byDepth = depth(a.recordId).compareTo(depth(b.recordId));
        if (byDepth != 0) return byDepth;
      }
      return a.seq.compareTo(b.seq);
    });
  }

  /// One `push_changes` item, built from the record's *current* local
  /// state (not what it was when queued). Null when there's nothing to send.
  Future<Map<String, Object?>?> _changeFor(SyncOutboxEntry entry) async {
    final id = entry.recordId;
    final table = entry.entity;

    if (entry.op == 'delete') {
      if (table == 'notes_tags') {
        final key = _noteTagKey(id);
        if (key == null) return null;
        return {'table': table, 'op': 'delete', 'id': id, 'row': key};
      }
      return {'table': table, 'op': 'delete', 'id': id};
    }

    Map<String, Object?>? row;
    switch (table) {
      case 'folders':
        final f = await (_db.select(
          _db.foldersTable,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (f != null) {
          row = {
            'name': f.name,
            'parent_id': f.parentId,
            'sort_order': f.sortOrder,
            'updated_at': _iso(f.updatedAt),
            'is_deleted': f.isDeleted,
          };
        }
      case 'tags':
        final t = await (_db.select(
          _db.tagsTable,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (t != null) row = {'name': t.name};
      case 'notes':
        final n = await (_db.select(
          _db.notesTable,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (n != null) {
          row = {
            'folder_id': n.folderId,
            'title': n.title,
            'title_style_json': [for (final r in n.titleStyleJson) r.toJson()],
            'body_json': n.bodyJson,
            'created_at': _iso(n.createdAt),
            'updated_at': _iso(n.updatedAt),
            'is_deleted': n.isDeleted,
            'deleted_at': n.deletedAt == null ? null : _iso(n.deletedAt!),
          };
        }
      case 'notes_tags':
        final nt = await (_db.select(
          _db.notesTagsTable,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (nt != null) row = {'note_id': nt.noteId, 'tag_id': nt.tagId};
    }
    if (row == null) return null;
    return {'table': table, 'op': 'upsert', 'id': id, 'row': row};
  }

  /// notes_tags ids are `'$noteId::$tagId'` (see `NotesDao.addTagToNote`).
  Map<String, String>? _noteTagKey(String id) {
    final split = id.indexOf('::');
    if (split <= 0) return null;
    return {
      'note_id': id.substring(0, split),
      'tag_id': id.substring(split + 2),
    };
  }

  // ---------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------

  /// Replaces every local folder, tag and note with the server's copy.
  ///
  /// Throws [UnsyncedChangesException] if anything is waiting to upload,
  /// unless [discardLocalChanges] — those changes would be lost.
  Future<DownloadResult> download({bool discardLocalChanges = false}) async {
    Future<void> checkNothingPending() async {
      if (discardLocalChanges) return;
      final pending = await _dao.pendingCount();
      if (pending > 0) throw UnsyncedChangesException(pending);
    }

    await checkNothingPending();

    // Fetch everything before touching local data, so a network failure
    // halfway leaves the device as it was.
    final folders = await _remote.fetchAll('folders');
    final tags = await _remote.fetchAll('tags');
    final notes = await _remote.fetchAll('notes');
    final notesTags = await _remote.fetchAll('notes_tags');

    await _db.transaction(() async {
      // Again inside the transaction: something may have been edited
      // while the fetch was running.
      await checkNothingPending();
      await _dao.deleteAllData();
      await _db.batch((b) {
        b.insertAll(_db.foldersTable, folders.map(_folderFromServer));
        b.insertAll(_db.tagsTable, tags.map(_tagFromServer));
        b.insertAll(_db.notesTable, notes.map(_noteFromServer));
        b.insertAll(_db.notesTagsTable, notesTags.map(_noteTagFromServer));
      });
      // The deletes/inserts above went through the outbox triggers; none
      // of it is a local change.
      await _dao.clearOutbox();
      // After clearing, so that if the server lacked them they're queued
      // for upload (notes in them need them to exist on the server).
      await _ensureProtectedFolders();
      await _dao.writeState(SyncDao.lastDownloadedAtKey, _nowIso());
    });

    return DownloadResult(
      rowCount: folders.length + tags.length + notes.length + notesTags.length,
    );
  }

  FoldersTableCompanion _folderFromServer(Map<String, dynamic> r) {
    return FoldersTableCompanion.insert(
      id: r['id'] as String,
      ownerId: Value(r['owner_id'] as String),
      name: r['name'] as String,
      parentId: Value(r['parent_id'] as String?),
      updatedAt: _parse(r['updated_at'])!,
      isDeleted: Value(r['is_deleted'] as bool),
      sortOrder: Value((r['sort_order'] as num?)?.toDouble() ?? 0),
    );
  }

  TagsTableCompanion _tagFromServer(Map<String, dynamic> r) {
    return TagsTableCompanion.insert(
      id: r['id'] as String,
      ownerId: Value(r['owner_id'] as String),
      name: r['name'] as String,
    );
  }

  NotesTableCompanion _noteFromServer(Map<String, dynamic> r) {
    return NotesTableCompanion.insert(
      id: r['id'] as String,
      ownerId: Value(r['owner_id'] as String),
      folderId: Value(r['folder_id'] as String?),
      title: Value(r['title'] as String),
      titleStyleJson: Value([
        for (final run in r['title_style_json'] as List)
          TitleStyleRun.fromJson(run as Map<String, dynamic>),
      ]),
      bodyJson: Value(r['body_json'] as Map<String, dynamic>),
      createdAt: _parse(r['created_at'])!,
      updatedAt: _parse(r['updated_at'])!,
      isDeleted: Value(r['is_deleted'] as bool),
      deletedAt: Value(_parse(r['deleted_at'])),
    );
  }

  NotesTagsTableCompanion _noteTagFromServer(Map<String, dynamic> r) {
    final noteId = r['note_id'] as String;
    final tagId = r['tag_id'] as String;
    return NotesTagsTableCompanion.insert(
      id: '$noteId::$tagId',
      noteId: noteId,
      tagId: tagId,
      ownerId: Value(r['owner_id'] as String),
    );
  }

  /// Missing ones go at the end of the top level.
  Future<void> _ensureProtectedFolders() async {
    final now = DateTime.now();
    final existing = await _db.select(_db.foldersTable).get();
    final ids = {for (final f in existing) f.id};
    var next = existing
            .where((f) => f.parentId == null)
            .fold<double>(-1, (m, f) => f.sortOrder > m ? f.sortOrder : m) +
        1;
    await _db.batch((b) {
      b.insertAll(_db.foldersTable, [
        for (final MapEntry(key: id, value: name) in _protectedFolders.entries)
          if (!ids.contains(id))
            FoldersTableCompanion.insert(
              id: id,
              name: name,
              updatedAt: now,
              sortOrder: Value(next++),
            ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  // ---------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------

  /// Records which account the local data belongs to. The first account to
  /// sign in on a device takes over what's there (the demo content). If a
  /// *different* account signs in later, local data is cleared, including
  /// anything not uploaded, and this returns true — the caller should then
  /// run [downloadForNewAccount].
  Future<bool> adoptAccount(String userId) async {
    final stored = await _dao.readState(SyncDao.userIdKey);
    if (stored == userId) return false;
    if (stored == null) {
      await _dao.writeState(SyncDao.userIdKey, userId);
      return false;
    }
    await _db.transaction(() async {
      await _dao.deleteAllData();
      await _dao.clearOutbox();
      await _dao.deleteState(SyncDao.lastUploadedAtKey);
      await _dao.deleteState(SyncDao.lastDownloadedAtKey);
      await _dao.writeState(SyncDao.userIdKey, userId);
      // So the app still works if the download that follows fails.
      await _ensureProtectedFolders();
    });
    await attachments?.clearAll();
    return true;
  }

  /// After an account switch: the account's notes from the server, or the
  /// demo content if it has none yet.
  Future<void> downloadForNewAccount() async {
    final result = await download(discardLocalChanges: true);
    if (result.rowCount == 0) await _db.seedDemoContent();
  }

  // ---------------------------------------------------------------------

  static String _iso(DateTime value) => value.toUtc().toIso8601String();

  static String _nowIso() => _iso(DateTime.now());

  static DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}

class UploadResult {
  const UploadResult({required this.uploaded, required this.skipped});

  final int uploaded;

  /// Notes/folders the server kept because its copy was newer.
  final int skipped;
}

class DownloadResult {
  const DownloadResult({required this.rowCount});

  final int rowCount;
}

class UnsyncedChangesException implements Exception {
  const UnsyncedChangesException(this.count);

  final int count;

  @override
  String toString() =>
      '$count ${count == 1 ? 'change hasn\'t' : 'changes haven\'t'} been '
      'uploaded yet. Upload them first, or choose to discard them.';
}
