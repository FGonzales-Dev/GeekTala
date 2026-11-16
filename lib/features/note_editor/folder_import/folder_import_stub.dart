import '../../../data/attachments/attachment_store.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/folders_repository.dart';
import '../../../data/repositories/notes_repository.dart';
import 'folder_import_result.dart';

/// Web: there's no file system to walk.
const canImportFolders = false;

Future<FolderImportPreview> previewMarkdownDirectory(
  String path, {
  required AppDatabase db,
}) {
  throw UnsupportedError('Importing a folder needs a file system.');
}

Future<FolderImportResult> importMarkdownDirectory(
  String path, {
  required AppDatabase db,
  required FoldersRepository folders,
  required NotesRepository notes,
  AttachmentStore? attachments,
  bool addMissingOnly = false,
}) {
  throw UnsupportedError('Importing a folder needs a file system.');
}
