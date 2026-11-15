/// What [importMarkdownDirectory] did.
class FolderImportResult {
  const FolderImportResult({
    required this.rootFolderId,
    required this.folderName,
    required this.notes,
    required this.folders,
    required this.failedFiles,
    this.skippedNotes = 0,
  });

  /// The Noote folder the import created (named after the chosen folder),
  /// or the existing one it added to.
  final String rootFolderId;
  final String folderName;

  /// Notes added.
  final int notes;

  /// Folders created, including the root folder unless it already existed.
  final int folders;

  /// Notes already there (same title, same folder), when only adding
  /// what's missing.
  final int skippedNotes;

  /// Paths (relative to the chosen folder) that couldn't be read.
  final List<String> failedFiles;
}
