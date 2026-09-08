import 'package:drift/drift.dart';

@DataClassName('FolderRow')
class FoldersTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
