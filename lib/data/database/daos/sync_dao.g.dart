// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncDaoMixin on DatabaseAccessor<AppDatabase> {
  SyncOutbox get syncOutbox => attachedDatabase.syncOutbox;
  SyncState get syncState => attachedDatabase.syncState;
  $FoldersTableTable get foldersTable => attachedDatabase.foldersTable;
  $TagsTableTable get tagsTable => attachedDatabase.tagsTable;
  $NotesTableTable get notesTable => attachedDatabase.notesTable;
  $NotesTagsTableTable get notesTagsTable => attachedDatabase.notesTagsTable;
  SyncDaoManager get managers => SyncDaoManager(this);
}

class SyncDaoManager {
  final _$SyncDaoMixin _db;
  SyncDaoManager(this._db);
  $SyncOutboxTableManager get syncOutbox =>
      $SyncOutboxTableManager(_db.attachedDatabase, _db.syncOutbox);
  $SyncStateTableManager get syncState =>
      $SyncStateTableManager(_db.attachedDatabase, _db.syncState);
  $$FoldersTableTableTableManager get foldersTable =>
      $$FoldersTableTableTableManager(_db.attachedDatabase, _db.foldersTable);
  $$TagsTableTableTableManager get tagsTable =>
      $$TagsTableTableTableManager(_db.attachedDatabase, _db.tagsTable);
  $$NotesTableTableTableManager get notesTable =>
      $$NotesTableTableTableManager(_db.attachedDatabase, _db.notesTable);
  $$NotesTagsTableTableTableManager get notesTagsTable =>
      $$NotesTagsTableTableTableManager(
        _db.attachedDatabase,
        _db.notesTagsTable,
      );
}
