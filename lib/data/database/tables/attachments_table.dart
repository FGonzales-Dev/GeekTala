import 'package:drift/drift.dart';

/// Files (images for now) that notes show. The bytes live in the app's
/// private data folder and in Supabase Storage; a note's body refers to one
/// as `attachment://<id>` (see lib/data/attachments/attachment_refs.dart).
///
/// Local bookkeeping only — not synced through the outbox. Another device
/// learns about a file from the note that shows it and downloads it then.
@DataClassName('AttachmentRow')
class AttachmentsTable extends Table {
  /// `<uuid>.<ext>` — also the file name, locally and in Storage.
  TextColumn get id => text()();

  /// The name it had when added (e.g. `IMG_0412.jpeg`).
  TextColumn get originalName => text().withDefault(const Constant(''))();
  TextColumn get mimeType => text()();
  IntColumn get byteSize => integer()();

  /// In Supabase Storage. False for files added here and not uploaded yet.
  BoolColumn get uploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
