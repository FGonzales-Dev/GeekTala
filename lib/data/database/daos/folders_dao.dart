import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/folders_table.dart';

part 'folders_dao.g.dart';

@DriftAccessor(tables: [FoldersTable])
class FoldersDao extends DatabaseAccessor<AppDatabase> with _$FoldersDaoMixin {
  FoldersDao(super.db);

  SimpleSelectStatement<$FoldersTableTable, FolderRow> _visible() {
    return select(foldersTable)
      ..where((f) => f.isDeleted.equals(false))
      ..orderBy([
        (f) => OrderingTerm.asc(f.sortOrder),
        (f) => OrderingTerm.asc(f.name),
      ]);
  }

  /// In display order: by [FoldersTable.sortOrder] within each parent.
  Stream<List<FolderRow>> watchAllFolders() => _visible().watch();

  /// One-shot (not a stream) — used to walk the parent/child tree when
  /// computing what a delete or move will affect.
  Future<List<FolderRow>> getAllFoldersOnce() => _visible().get();

  Future<void> insertFolder(FoldersTableCompanion entry) =>
      into(foldersTable).insert(entry);

  Future<void> renameFolder(String id, String name) {
    return (update(foldersTable)..where((f) => f.id.equals(id))).write(
      FoldersTableCompanion(
        name: Value(name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Puts [id] under [parentId] (null = top level) at [sortOrder].
  Future<void> placeFolder(
    String id, {
    required String? parentId,
    required double sortOrder,
  }) {
    return (update(foldersTable)..where((f) => f.id.equals(id))).write(
      FoldersTableCompanion(
        parentId: Value(parentId),
        sortOrder: Value(sortOrder),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setSortOrder(String id, double sortOrder) {
    return (update(foldersTable)..where((f) => f.id.equals(id))).write(
      FoldersTableCompanion(
        sortOrder: Value(sortOrder),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> softDeleteFolder(String id) {
    return (update(foldersTable)..where((f) => f.id.equals(id))).write(
      FoldersTableCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
