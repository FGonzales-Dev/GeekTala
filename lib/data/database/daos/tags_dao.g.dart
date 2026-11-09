// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tags_dao.dart';

// ignore_for_file: type=lint
mixin _$TagsDaoMixin on DatabaseAccessor<AppDatabase> {
  $TagsTableTable get tagsTable => attachedDatabase.tagsTable;
  $NotesTagsTableTable get notesTagsTable => attachedDatabase.notesTagsTable;
  TagsDaoManager get managers => TagsDaoManager(this);
}

class TagsDaoManager {
  final _$TagsDaoMixin _db;
  TagsDaoManager(this._db);
  $$TagsTableTableTableManager get tagsTable =>
      $$TagsTableTableTableManager(_db.attachedDatabase, _db.tagsTable);
  $$NotesTagsTableTableTableManager get notesTagsTable =>
      $$NotesTagsTableTableTableManager(
        _db.attachedDatabase,
        _db.notesTagsTable,
      );
}
