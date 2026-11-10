/// What [importMarkdownDirectory] did.
class FolderImportResult {
  const FolderImportResult({
    required this.rootFolderId,
    required this.folderName,
    required this.notes,
    required this.folders,
    required this.failedFiles,
  });

  /// The Noote folder the import created (named after the chosen folder).
  final String rootFolderId;
  final String folderName;
  final int notes;

  /// Including the root folder.
  final int folders;

  /// Paths (relative to the chosen folder) that couldn't be read.
  final List<String> failedFiles;
}
