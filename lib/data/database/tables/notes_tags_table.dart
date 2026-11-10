import 'package:drift/drift.dart';

/// Join table between notes and tags. Keyed by a single deterministic `id`
/// (`'$noteId::$tagId'`, computed in `NotesDao.addTagToNote`) so the sync
/// outbox can track each link as one record (see `../sync.drift`); upload
/// splits it back into note_id/tag_id. It can't collide or duplicate the
/// way an arbitrary generated id could.
class NotesTagsTable extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get tagId => text()();
  TextColumn get ownerId => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}
