import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/tag.dart';

const _uuid = Uuid();

class TagsRepository {
  TagsRepository(this._db);

  final AppDatabase _db;

  String get _ownerId => Supabase.instance.client.auth.currentUser?.id ?? '';

  Stream<List<Tag>> watchAllTags() {
    return _db.tagsDao.watchAllTags().map(
          (rows) => rows.map((r) => Tag(id: r.id, name: r.name)).toList(),
        );
  }

  Future<String> createTag(String name) async {
    final id = _uuid.v4();
    await _db.tagsDao.insertTag(
      TagsTableCompanion.insert(id: id, ownerId: Value(_ownerId), name: name),
    );
    return id;
  }
}
