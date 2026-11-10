import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../data/attachments/attachment_refs.dart';
import '../../../data/attachments/attachment_store.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/folders_repository.dart';
import '../../../data/repositories/notes_repository.dart';
import '../markdown_convert.dart';
import 'folder_import_result.dart';

const canImportFolders = true;

const _extensions = {'.md', '.markdown', '.txt'};

/// Imports a folder of Markdown files: a new Noote folder named after it,
/// subfolders as subfolders, each `.md`/`.markdown`/`.txt` file as a note
/// (title = file name, date = the file's modification time). All in one
/// transaction.
///
/// With [attachments], images a note links to by relative path
/// (`![](images/photo.jpg)`) are added as attachments. Hidden files and
/// folders are skipped, and so are folders holding only other files (like
/// those images) — but empty folders are kept.
Future<FolderImportResult> importMarkdownDirectory(
  String path, {
  required AppDatabase db,
  required FoldersRepository folders,
  required NotesRepository notes,
  AttachmentStore? attachments,
}) async {
  final root = Directory(path);
  final name = p.basename(p.normalize(path));
  var noteCount = 0;
  var folderCount = 0;
  final failed = <String>[];

  late String rootId;
  await db.transaction(() async {
    Future<void> walk(Directory dir, String folderId) async {
      final entries = await dir.list(followLinks: false).toList()
        ..sort(
          (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );
      for (final entry in entries) {
        final base = p.basename(entry.path);
        if (base.startsWith('.')) continue;
        if (entry is Directory) {
          if (!await _worthImporting(entry)) continue;
          final id = await folders.createFolder(name: base, parentId: folderId);
          folderCount++;
          await walk(entry, id);
        } else if (entry is File &&
            _extensions.contains(p.extension(base).toLowerCase())) {
          try {
            var markdown = await entry.readAsString();
            if (attachments != null) {
              markdown = await _importLinkedImages(
                markdown,
                from: entry.parent.path,
                attachments: attachments,
              );
            }
            await notes.createNote(
              folderId: folderId,
              title: p.basenameWithoutExtension(base),
              body: noteMarkdownToDocument(markdown).toJson(),
              modifiedAt: await entry.lastModified(),
            );
            noteCount++;
          } catch (_) {
            failed.add(p.relative(entry.path, from: root.path));
          }
        }
      }
    }

    rootId = await folders.createFolder(name: name);
    folderCount++;
    await walk(root, rootId);
  });

  return FolderImportResult(
    rootFolderId: rootId,
    folderName: name,
    notes: noteCount,
    folders: folderCount,
    failedFiles: failed,
  );
}

/// A folder with notes somewhere inside, or an empty one (kept, as in the
/// source); not one holding only other files, like an images folder.
Future<bool> _worthImporting(Directory dir) async {
  var empty = true;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    final base = p.basename(entity.path);
    if (base.startsWith('.')) continue;
    if (entity is File) {
      empty = false;
      if (_extensions.contains(p.extension(base).toLowerCase())) return true;
    }
  }
  return empty;
}

final _imageLink = RegExp(r'!\[([^\]]*)\]\(<?([^)>\s]+)>?(?:\s+"[^"]*")?\)');

/// Rewrites `![…](relative/image.png)` to point at a new attachment holding
/// that image. Links to the web, missing files and non-images stay as they
/// are.
Future<String> _importLinkedImages(
  String markdown, {
  required String from,
  required AttachmentStore attachments,
}) async {
  final replacements = <String, String>{};
  for (final match in _imageLink.allMatches(markdown)) {
    final target = match.group(2)!;
    if (replacements.containsKey(target) || target.contains(':')) continue;
    String decoded;
    try {
      decoded = Uri.decodeComponent(target);
    } catch (_) {
      decoded = target;
    }
    final file = File(p.normalize(p.join(from, decoded)));
    if (!imageExtensions.contains(
          p.extension(file.path).replaceFirst('.', '').toLowerCase(),
        ) ||
        !await file.exists()) {
      continue;
    }
    replacements[target] = await attachments.addImageFile(file.path);
  }
  if (replacements.isEmpty) return markdown;
  return markdown.replaceAllMapped(_imageLink, (m) {
    final ref = replacements[m.group(2)];
    return ref == null ? m.group(0)! : '![${m.group(1)}]($ref)';
  });
}
