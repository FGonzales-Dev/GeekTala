import 'package:drift/drift.dart';

@DataClassName('FolderRow')
class FoldersTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Position among the folders with the same parent, ascending. A
  /// fraction, so a folder dropped between two others gets the midpoint
  /// without renumbering its siblings (see `FoldersRepository.moveFolder`).
  RealColumn get sortOrder => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}
