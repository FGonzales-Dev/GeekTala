import 'package:drift/drift.dart';

@DataClassName('TagRow')
class TagsTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().withDefault(const Constant(''))();
  TextColumn get name => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
}
