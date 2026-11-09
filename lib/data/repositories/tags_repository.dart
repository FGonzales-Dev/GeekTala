import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/tag.dart';

const _uuid = Uuid();

/// Namespace for name-based tag ids (any fixed UUID works; never change it).
const _tagIdNamespace = '3f0c7c64-5b0e-4d33-9b4e-6c1f2a8d7e21';

class TagsRepository {
  TagsRepository(this._db, {String Function()? ownerId})
    : _ownerIdOf = ownerId ?? _signedInUserId;

  final AppDatabase _db;
  final String Function() _ownerIdOf;

  static String _signedInUserId() =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  String get _ownerId => _ownerIdOf();

  Stream<List<Tag>> watchAllTags() {
    return _db.tagsDao.watchAllTags().map(
          (rows) => rows.map((r) => Tag(id: r.id, name: r.name)).toList(),
        );
  }

  /// The id is derived from the name, so the same tag created on two
  /// devices before either uploads ends up as one tag, not two that break
  /// the server's one-name-per-account rule. An existing tag with that
  /// name is reused.
  Future<String> createTag(String name) async {
    final existing = await _db.tagsDao.tagByName(name);
    if (existing != null) return existing.id;
    var id = _uuid.v5(_tagIdNamespace, name);
    // A renamed tag keeps the id of its old name; don't collide with it.
    if (await _db.tagsDao.tagById(id) != null) id = _uuid.v4();
    await _db.tagsDao.insertTag(
      TagsTableCompanion.insert(id: id, ownerId: Value(_ownerId), name: name),
    );
    return id;
  }

  /// Throws [TagNameTakenException] if another tag already has [name].
  Future<void> renameTag(String id, String name) async {
    final other = await _db.tagsDao.tagByName(name);
    if (other != null) {
      if (other.id == id) return;
      throw TagNameTakenException(name);
    }
    await _db.tagsDao.renameTag(id, name);
  }

  /// Deletes the tag and removes it from its notes (which stay). Returns
  /// what [restoreTag] needs to undo it, or null if there was no such tag.
  Future<DeletedTag?> deleteTag(String id) {
    return _db.transaction(() async {
      final tag = await _db.tagsDao.tagById(id);
      if (tag == null) return null;
      final noteIds = await _db.tagsDao.noteIdsWithTag(id);
      await _db.tagsDao.deleteTag(id);
      return DeletedTag._(tag, noteIds);
    });
  }

  /// Undo for [deleteTag]. False if another tag has taken the name since.
  Future<bool> restoreTag(DeletedTag deleted) {
    final tag = deleted._row;
    return _db.transaction(() async {
      if (await _db.tagsDao.tagByName(tag.name) != null) return false;
      await _db.tagsDao.insertTag(tag.toCompanion(false));
      for (final noteId in deleted.noteIds) {
        await _db.notesDao.addTagToNote(noteId, tag.id, tag.ownerId);
      }
      return true;
    });
  }
}

class DeletedTag {
  DeletedTag._(this._row, this.noteIds);

  final TagRow _row;

  /// The notes it was removed from.
  final List<String> noteIds;
}

class TagNameTakenException implements Exception {
  const TagNameTakenException(this.name);

  final String name;

  @override
  String toString() => 'A tag named "$name" already exists.';
}
