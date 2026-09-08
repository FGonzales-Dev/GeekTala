import 'package:drift/drift.dart';

/// Join table between notes and tags. `id` (not a composite
/// `(noteId, tagId)` key) because PowerSync's Table schema requires a
/// single-column primary key on every synced table — see
/// `../../sync/powersync_schema.dart`. It's deterministic
/// (`'$noteId::$tagId'`, computed in `NotesDao.addTagToNote`), so it still
/// can't collide or duplicate the way an arbitrary generated id could.
class NotesTagsTable extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get tagId => text()();
  TextColumn get ownerId => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}
