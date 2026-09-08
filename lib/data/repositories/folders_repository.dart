import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/folder.dart';

const _uuid = Uuid();

/// What deleting a folder will actually affect — computed before the user
/// commits, so the confirmation dialog can show real numbers instead of a
/// generic warning.
class FolderDeletePreview {
  const FolderDeletePreview({
    required this.affectedFolderIds,
    required this.subfolderCount,
    required this.noteCount,
  });

  /// The folder being deleted plus every descendant subfolder.
  final List<String> affectedFolderIds;

  /// [affectedFolderIds] minus the folder itself.
  final int subfolderCount;

  /// Notes currently in any of [affectedFolderIds].
  final int noteCount;
}

class FoldersRepository {
  FoldersRepository(this._db);

  final AppDatabase _db;

  String get _ownerId => Supabase.instance.client.auth.currentUser?.id ?? '';

  /// Personal and Shared always exist and can't be deleted.
  static const protectedFolderIds = {'personal', 'shared'};

  bool isProtected(String id) => protectedFolderIds.contains(id);

  Stream<List<Folder>> watchAllFolders() {
    return _db.foldersDao.watchAllFolders().map(
          (rows) => rows
              .map((r) => Folder(id: r.id, name: r.name, parentId: r.parentId))
              .toList(),
        );
  }

  Future<String> createFolder({required String name, String? parentId}) async {
    final id = _uuid.v4();
    await _db.foldersDao.insertFolder(
      FoldersTableCompanion.insert(
        id: id,
        ownerId: Value(_ownerId),
        name: name,
        parentId: Value(parentId),
        updatedAt: DateTime.now(),
      ),
    );
    return id;
  }

  Future<void> renameFolder(String id, String name) =>
      _db.foldersDao.renameFolder(id, name);

  /// Collects [id] plus every descendant folder (BFS over `parentId`).
  Future<List<String>> _collectWithDescendants(String id) async {
    final all = await _db.foldersDao.getAllFoldersOnce();
    final result = <String>[id];
    final queue = [id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final folder in all) {
        if (folder.parentId == current) {
          result.add(folder.id);
          queue.add(folder.id);
        }
      }
    }
    return result;
  }

  Future<FolderDeletePreview> previewDelete(String id) async {
    final affected = await _collectWithDescendants(id);
    final noteCount = await _db.notesDao.countInFolders(affected);
    return FolderDeletePreview(
      affectedFolderIds: affected,
      subfolderCount: affected.length - 1,
      noteCount: noteCount,
    );
  }

  Future<void> deleteFolder(String id, {required bool moveNotesToPersonal}) async {
    if (isProtected(id)) {
      throw ArgumentError('Folder "$id" is protected and cannot be deleted.');
    }

    final affected = await _collectWithDescendants(id);

    await _db.transaction(() async {
      if (moveNotesToPersonal) {
        await _db.notesDao.reassignFolder(affected, 'personal');
      } else {
        await _db.notesDao.softDeleteInFolders(affected);
      }
      for (final folderId in affected) {
        await _db.foldersDao.softDeleteFolder(folderId);
      }
    });
  }
}
