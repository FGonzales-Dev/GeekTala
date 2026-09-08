import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/title_style_run.dart';

/// JSON-encodes/decodes the raw appflowy_editor document tree
/// (`{"document": {"type": "page", "children": [...]}}`) into the
/// `bodyJson` text column. No typed model on this side — the document
/// shape belongs to appflowy_editor, not to us (see noote-plan.md §5).
class DocumentJsonConverter extends TypeConverter<Map<String, dynamic>, String> {
  const DocumentJsonConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) =>
      jsonDecode(fromDb) as Map<String, dynamic>;

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}

/// JSON-encodes/decodes the title's inline-formatting overlay (see
/// [TitleStyleRun]) into the `titleStyleJson` text column. The plain
/// `title` column stays untouched by this — it's a separate list of
/// `[start, end)` style runs, not the text itself.
class TitleStyleJsonConverter
    extends TypeConverter<List<TitleStyleRun>, String> {
  const TitleStyleJsonConverter();

  @override
  List<TitleStyleRun> fromSql(String fromDb) => (jsonDecode(fromDb) as List)
      .map((e) => TitleStyleRun.fromJson(e as Map<String, dynamic>))
      .toList();

  @override
  String toSql(List<TitleStyleRun> value) =>
      jsonEncode(value.map((r) => r.toJson()).toList());
}

/// See noote-plan.md §5. `body_json` stores appflowy_editor's own document
/// tree (Build Order step 3), not a custom block model.
@DataClassName('NoteRow')
class NotesTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().withDefault(const Constant(''))();
  TextColumn get folderId => text().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get titleStyleJson => text()
      .map(const TitleStyleJsonConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get bodyJson => text()
      .map(const DocumentJsonConverter())
      .withDefault(
        const Constant(
          '{"document":{"type":"page","children":'
          '[{"type":"paragraph","data":{"delta":[]}}]}}',
        ),
      )();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
