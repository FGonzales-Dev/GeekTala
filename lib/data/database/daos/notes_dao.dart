import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/notes_table.dart';
import '../tables/notes_tags_table.dart';

part 'notes_dao.g.dart';

/// A note row plus the ids of every tag attached to it via `notes_tags`.
class NoteWithTags {
  const NoteWithTags(this.note, this.tagIds);

  final NoteRow note;
  final List<String> tagIds;
}

@DriftAccessor(tables: [NotesTable, NotesTagsTable])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  Stream<List<NoteWithTags>> watchAllNotes() {
    final query = select(notesTable).join([
      leftOuterJoin(
        notesTagsTable,
        notesTagsTable.noteId.equalsExp(notesTable.id),
      ),
    ])..where(notesTable.isDeleted.equals(false));
    return query.watch().map(_groupByNote);
  }

  Stream<List<NoteWithTags>> watchNotesInFolder(String? folderId) {
    final query = select(notesTable).join([
      leftOuterJoin(
        notesTagsTable,
        notesTagsTable.noteId.equalsExp(notesTable.id),
      ),
    ])..where(notesTable.isDeleted.equals(false));
    if (folderId == null) {
      query.where(notesTable.folderId.isNull());
    } else {
      query.where(notesTable.folderId.equals(folderId));
    }
    return query.watch().map(_groupByNote);
  }

  Stream<List<NoteWithTags>> watchDeletedNotes() {
    final query = select(notesTable).join([
      leftOuterJoin(
        notesTagsTable,
        notesTagsTable.noteId.equalsExp(notesTable.id),
      ),
    ])
      ..where(notesTable.isDeleted.equals(true))
      ..orderBy([OrderingTerm.desc(notesTable.deletedAt)]);
    return query.watch().map(_groupByNote);
  }

  Stream<NoteWithTags?> watchNoteById(String id) {
    final query = select(notesTable).join([
      leftOuterJoin(
        notesTagsTable,
        notesTagsTable.noteId.equalsExp(notesTable.id),
      ),
    ])..where(notesTable.id.equals(id));
    return query.watch().map((rows) {
      final grouped = _groupByNote(rows);
      return grouped.isEmpty ? null : grouped.first;
    });
  }

  List<NoteWithTags> _groupByNote(List<TypedResult> rows) {
    final notesById = <String, NoteRow>{};
    final tagsById = <String, List<String>>{};
    for (final row in rows) {
      final note = row.readTable(notesTable);
      notesById[note.id] = note;
      final tagId = row.readTableOrNull(notesTagsTable)?.tagId;
      final tags = tagsById.putIfAbsent(note.id, () => []);
      if (tagId != null) tags.add(tagId);
    }
    return notesById.values
        .map((note) => NoteWithTags(note, tagsById[note.id] ?? const []))
        .toList();
  }

  Future<void> insertNote(NotesTableCompanion entry) => into(notesTable).insert(entry);

  Future<List<NoteRow>> getNotesByIds(Iterable<String> ids) {
    return (select(
      notesTable,
    )..where((n) => n.id.isIn(ids.toList()))).get();
  }

  Future<void> updateNote(String id, NotesTableCompanion entry) {
    return (update(notesTable)..where((n) => n.id.equals(id))).write(entry);
  }

  Future<void> softDeleteNote(String id) {
    final now = DateTime.now();
    return (update(notesTable)..where((n) => n.id.equals(id))).write(
      NotesTableCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> restoreNote(String id) {
    return (update(notesTable)..where((n) => n.id.equals(id))).write(
      NotesTableCompanion(
        isDeleted: const Value(false),
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Hard delete — irreversible. Cleans up `notes_tags` first since there's
  /// no `ON DELETE CASCADE` on that join table.
  Future<void> permanentlyDeleteNote(String id) {
    return transaction(() async {
      await (delete(
        notesTagsTable,
      )..where((t) => t.noteId.equals(id))).go();
      await (delete(notesTable)..where((n) => n.id.equals(id))).go();
    });
  }

  /// Attaches [tagId] to [noteId] — a no-op if already attached.
  Future<void> addTagToNote(String noteId, String tagId, String ownerId) {
    return into(notesTagsTable).insertOnConflictUpdate(
      NotesTagsTableCompanion.insert(
        id: '$noteId::$tagId',
        noteId: noteId,
        tagId: tagId,
        ownerId: Value(ownerId),
      ),
    );
  }

  Future<void> removeTagFromNote(String noteId, String tagId) {
    return (delete(
      notesTagsTable,
    )..where((t) => t.noteId.equals(noteId) & t.tagId.equals(tagId))).go();
  }

  /// Total notes currently in any of [folderIds] — used by the delete-folder
  /// warning dialog to show a concrete count before the user commits.
  Future<int> countInFolders(List<String> folderIds) async {
    final countExpr = notesTable.id.count();
    final query = selectOnly(notesTable)
      ..addColumns([countExpr])
      ..where(
        notesTable.isDeleted.equals(false) &
            notesTable.folderId.isIn(folderIds),
      );
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  /// Bulk-reassigns every note in [folderIds] to [targetFolderId] — used
  /// when a folder is deleted and its notes are moved out rather than
  /// deleted with it.
  Future<void> reassignFolder(List<String> folderIds, String targetFolderId) {
    return (update(
      notesTable,
    )..where((n) => n.folderId.isIn(folderIds))).write(
      NotesTableCompanion(
        folderId: Value(targetFolderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Bulk soft-delete for every note in [folderIds] — used when a folder is
  /// deleted along with its notes.
  Future<void> softDeleteInFolders(List<String> folderIds) {
    final now = DateTime.now();
    return (update(
      notesTable,
    )..where((n) => n.folderId.isIn(folderIds))).write(
      NotesTableCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Note count per folder — a cross-entity aggregate, not stored on
  /// [FolderRow]/`Folder` itself.
  Stream<Map<String, int>> watchNoteCountsByFolder() {
    final countExpr = notesTable.id.count();
    final query = selectOnly(notesTable)
      ..addColumns([notesTable.folderId, countExpr])
      ..where(notesTable.isDeleted.equals(false))
      ..groupBy([notesTable.folderId]);

    return query.watch().map((rows) {
      final counts = <String, int>{};
      for (final row in rows) {
        final folderId = row.read(notesTable.folderId);
        if (folderId != null) {
          counts[folderId] = row.read(countExpr) ?? 0;
        }
      }
      return counts;
    });
  }
}
