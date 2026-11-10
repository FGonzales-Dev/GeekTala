import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/attachments_table.dart';
import '../tables/notes_table.dart';

part 'attachments_dao.g.dart';

@DriftAccessor(tables: [AttachmentsTable, NotesTable])
class AttachmentsDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentsDaoMixin {
  AttachmentsDao(super.db);

  Future<void> upsert(AttachmentsTableCompanion entry) =>
      into(attachmentsTable).insertOnConflictUpdate(entry);

  Future<AttachmentRow?> byId(String id) {
    return (select(
      attachmentsTable,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  Future<List<AttachmentRow>> all() => select(attachmentsTable).get();

  Future<List<AttachmentRow>> notUploaded() {
    return (select(attachmentsTable)
          ..where((a) => a.uploaded.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .get();
  }

  Future<void> markUploaded(String id) {
    return (update(attachmentsTable)..where((a) => a.id.equals(id))).write(
      const AttachmentsTableCompanion(uploaded: Value(true)),
    );
  }

  Future<void> deleteIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return (delete(attachmentsTable)..where((a) => a.id.isIn(list))).go();
  }

  Future<void> deleteAll() => delete(attachmentsTable).go();

  /// Every note body, trashed ones included (they can be restored).
  Future<List<Map<String, dynamic>>> allNoteBodies() async {
    final query = selectOnly(notesTable)..addColumns([notesTable.bodyJson]);
    final rows = await query.get();
    return [
      for (final row in rows) ?row.readWithConverter(notesTable.bodyJson),
    ];
  }
}
