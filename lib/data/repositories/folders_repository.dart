import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/folder.dart';
import '../models/folder_tree.dart';

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

/// How folders were placed before a move — everything [FoldersRepository.
/// moveFolder] changed — so the move can be undone exactly.
class FolderMoveUndo {
  const FolderMoveUndo(this._before);

  final List<({String id, String? parentId, double sortOrder})> _before;
}

class FoldersRepository {
  FoldersRepository(this._db);

  final AppDatabase _db;

  String get _ownerId => Supabase.instance.client.auth.currentUser?.id ?? '';

  bool isProtected(String id) => FolderTree.isProtected(id);

  static Folder _toFolder(FolderRow r) => Folder(
        id: r.id,
        name: r.name,
        parentId: r.parentId,
        sortOrder: r.sortOrder,
      );

  Stream<List<Folder>> watchAllFolders() {
    return _db.foldersDao.watchAllFolders().map(
          (rows) => rows.map(_toFolder).toList(),
        );
  }

  Future<FolderTree> _tree() async =>
      FolderTree((await _db.foldersDao.getAllFoldersOnce()).map(_toFolder).toList());

  /// New folders go at the end of their parent's list.
  Future<String> createFolder({required String name, String? parentId}) async {
    final id = _uuid.v4();
    final siblings = (await _tree()).childrenOf(parentId);
    await _db.foldersDao.insertFolder(
      FoldersTableCompanion.insert(
        id: id,
        ownerId: Value(_ownerId),
        name: name,
        parentId: Value(parentId),
        updatedAt: DateTime.now(),
        sortOrder: Value(siblings.isEmpty ? 0 : siblings.last.sortOrder + 1),
      ),
    );
    return id;
  }

  /// Moves folder [id] into [parentId] (null = top level), at [index]
  /// among that parent's other folders (null = at the end).
  ///
  /// Returns what's needed to undo it, or null if the folder was already
  /// there. Throws [ArgumentError] for a move [FolderTree.canMove] forbids.
  Future<FolderMoveUndo?> moveFolder(
    String id, {
    required String? parentId,
    int? index,
  }) async {
    final tree = await _tree();
    if (!tree.canMove(id, into: parentId)) {
      throw ArgumentError('Folder "$id" can\'t be moved into "$parentId".');
    }
    final folder = tree[id]!;
    final siblings = [
      for (final f in tree.childrenOf(parentId))
        if (f.id != id) f,
    ];
    final at = (index ?? siblings.length).clamp(0, siblings.length);
    if (folder.parentId == parentId &&
        tree.childrenOf(parentId).indexWhere((f) => f.id == id) == at) {
      return null;
    }

    final before = at > 0 ? siblings[at - 1].sortOrder : null;
    final after = at < siblings.length ? siblings[at].sortOrder : null;
    final changed = [
      (id: id, parentId: folder.parentId, sortOrder: folder.sortOrder),
    ];

    await _db.transaction(() async {
      final double order;
      if (before == null) {
        order = after == null ? 0 : after - 1;
      } else if (after == null) {
        order = before + 1;
      } else if (after - before > 1e-9) {
        order = (before + after) / 2;
      } else {
        // No room between the two neighbours (or they're tied): renumber
        // the whole list instead.
        final ordered = [...siblings]..insert(at, folder);
        for (var i = 0; i < ordered.length; i++) {
          final f = ordered[i];
          if (f.id == id) continue;
          changed.add((id: f.id, parentId: f.parentId, sortOrder: f.sortOrder));
          await _db.foldersDao.setSortOrder(f.id, i.toDouble());
        }
        order = at.toDouble();
      }
      await _db.foldersDao.placeFolder(id, parentId: parentId, sortOrder: order);
    });
    return FolderMoveUndo(changed);
  }

  Future<void> undoMove(FolderMoveUndo undo) {
    return _db.transaction(() async {
      for (final f in undo._before) {
        await _db.foldersDao.placeFolder(
          f.id,
          parentId: f.parentId,
          sortOrder: f.sortOrder,
        );
      }
    });
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
