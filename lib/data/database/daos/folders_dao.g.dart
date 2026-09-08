// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folders_dao.dart';

// ignore_for_file: type=lint
mixin _$FoldersDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTableTable get foldersTable => attachedDatabase.foldersTable;
  FoldersDaoManager get managers => FoldersDaoManager(this);
}

class FoldersDaoManager {
  final _$FoldersDaoMixin _db;
  FoldersDaoManager(this._db);
  $$FoldersTableTableTableManager get foldersTable =>
      $$FoldersTableTableTableManager(_db.attachedDatabase, _db.foldersTable);
}
