import '../../../data/attachments/attachment_store.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/folders_repository.dart';
import '../../../data/repositories/notes_repository.dart';
import 'folder_import_result.dart';

/// Web: there's no file system to walk.
const canImportFolders = false;

Future<FolderImportResult> importMarkdownDirectory(
  String path, {
  required AppDatabase db,
  required FoldersRepository folders,
  required NotesRepository notes,
  AttachmentStore? attachments,
}) {
  throw UnsupportedError('Importing a folder needs a file system.');
}
