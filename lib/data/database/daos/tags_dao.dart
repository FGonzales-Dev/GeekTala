import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tags_table.dart';

part 'tags_dao.g.dart';

@DriftAccessor(tables: [TagsTable])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  Stream<List<TagRow>> watchAllTags() => select(tagsTable).watch();

  Future<void> insertTag(TagsTableCompanion entry) =>
      into(tagsTable).insert(entry);
}
