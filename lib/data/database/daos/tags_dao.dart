import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/notes_tags_table.dart';
import '../tables/tags_table.dart';

part 'tags_dao.g.dart';

@DriftAccessor(tables: [TagsTable, NotesTagsTable])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  /// Alphabetical.
  Stream<List<TagRow>> watchAllTags() {
    return (select(
      tagsTable,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  Future<void> insertTag(TagsTableCompanion entry) =>
      into(tagsTable).insert(entry);

  Future<TagRow?> tagById(String id) {
    return (select(
      tagsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<TagRow?> tagByName(String name) {
    return (select(
      tagsTable,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
  }

  Future<void> renameTag(String id, String name) {
    return (update(tagsTable)..where((t) => t.id.equals(id))).write(
      TagsTableCompanion(name: Value(name)),
    );
  }

  Future<List<String>> noteIdsWithTag(String tagId) async {
    final rows = await (select(
      notesTagsTable,
    )..where((t) => t.tagId.equals(tagId))).get();
    return [for (final row in rows) row.noteId];
  }

  /// The tag and its links to notes (the notes themselves stay).
  Future<void> deleteTag(String id) async {
    await (delete(notesTagsTable)..where((t) => t.tagId.equals(id))).go();
    await (delete(tagsTable)..where((t) => t.id.equals(id))).go();
  }
}
