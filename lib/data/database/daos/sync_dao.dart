import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/folders_table.dart';
import '../tables/notes_table.dart';
import '../tables/notes_tags_table.dart';
import '../tables/tags_table.dart';

part 'sync_dao.g.dart';

/// Outbox and sync-state access for `SyncService` — see `../sync.drift`.
@DriftAccessor(
  include: {'../sync.drift'},
  tables: [FoldersTable, TagsTable, NotesTable, NotesTagsTable],
)
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  static const userIdKey = 'user_id';
  static const lastUploadedAtKey = 'last_uploaded_at';
  static const lastDownloadedAtKey = 'last_downloaded_at';

  Selectable<int> _pendingCountQuery() {
    final count = syncOutbox.seq.count();
    return (selectOnly(
      syncOutbox,
    )..addColumns([count])).map((row) => row.read(count) ?? 0);
  }

  Stream<int> watchPendingCount() => _pendingCountQuery().watchSingle();

  Future<int> pendingCount() => _pendingCountQuery().getSingle();

  Future<List<SyncOutboxEntry>> outboxEntries() {
    return (select(
      syncOutbox,
    )..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();
  }

  /// Removes exactly these entries. An entry replaced by a newer change
  /// since it was read has a different seq, so it survives.
  Future<void> deleteOutboxEntries(Iterable<int> seqs) {
    final list = seqs.toList();
    if (list.isEmpty) return Future.value();
    return (delete(syncOutbox)..where((o) => o.seq.isIn(list))).go();
  }

  Future<void> clearOutbox() => delete(syncOutbox).go();

  Stream<Map<String, String>> watchState() {
    return select(syncState)
        .watch()
        .map((rows) => {for (final row in rows) row.name: row.value});
  }

  Future<String?> readState(String name) async {
    final row = await (select(
      syncState,
    )..where((s) => s.name.equals(name))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeState(String name, String value) {
    return into(syncState).insertOnConflictUpdate(
      SyncStateCompanion.insert(name: name, value: value),
    );
  }

  Future<void> deleteState(String name) {
    return (delete(syncState)..where((s) => s.name.equals(name))).go();
  }

  /// Empties the four synced tables. Their delete triggers queue a delete
  /// for every row, so callers that don't want those uploaded clear the
  /// outbox afterwards, in the same transaction.
  Future<void> deleteAllData() async {
    await delete(notesTagsTable).go();
    await delete(notesTable).go();
    await delete(tagsTable).go();
    await delete(foldersTable).go();
  }
}
