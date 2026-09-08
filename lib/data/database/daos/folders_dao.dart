import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/folders_table.dart';

part 'folders_dao.g.dart';

@DriftAccessor(tables: [FoldersTable])
class FoldersDao extends DatabaseAccessor<AppDatabase> with _$FoldersDaoMixin {
  FoldersDao(super.db);

  Stream<List<FolderRow>> watchAllFolders() {
    return (select(
      foldersTable,
    )..where((f) => f.isDeleted.equals(false))).watch();
  }

  /// One-shot (not a stream) — used to walk the parent/child tree when
  /// computing what a delete will affect.
  Future<List<FolderRow>> getAllFoldersOnce() {
    return (select(
      foldersTable,
    )..where((f) => f.isDeleted.equals(false))).get();
  }

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

  Future<void> softDeleteFolder(String id) {
    return (update(foldersTable)..where((f) => f.id.equals(id))).write(
      FoldersTableCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
