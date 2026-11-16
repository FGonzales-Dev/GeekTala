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

/// What importing [path] would do, worked out before asking: how many
/// notes it holds ([FolderImportPreview.total]), and how many of them are
/// already there — same folder path from the top-level folder named after
/// it, same title — which "add only what's missing" would skip.
Future<FolderImportPreview> previewMarkdownDirectory(
  String path, {
  required AppDatabase db,
}) async {
  final root = Directory(path);
  final name = p.basename(p.normalize(path));
  final existingFolders = await db.foldersDao.getAllFoldersOnce();
  String? existingFolder(String? parentId, String name) {
    for (final f in existingFolders) {
      if (f.parentId == parentId && f.name == name) return f.id;
    }
    return null;
  }

  final titlesByFolder = <String?, Set<String>>{};
  final rows = await (db.select(
    db.notesTable,
  )..where((n) => n.isDeleted.equals(false))).get();
  for (final row in rows) {
    (titlesByFolder[row.folderId] ??= {}).add(row.title);
  }

  var total = 0;
  var existing = 0;
  // [folderId] null: a folder that doesn't exist yet, so nothing in it is
  // there already (but titles still repeat within it).
  Future<void> walk(Directory dir, String? folderId, Set<String> seen) async {
    for (final entry in await dir.list(followLinks: false).toList()) {
      final base = p.basename(entry.path);
      if (base.startsWith('.')) continue;
      if (entry is Directory) {
        if (!await _worthImporting(entry)) continue;
        final id = folderId == null ? null : existingFolder(folderId, base);
        await walk(entry, id, id == null ? {} : (titlesByFolder[id] ?? {}).toSet());
      } else if (entry is File &&
          _extensions.contains(p.extension(base).toLowerCase())) {
        total++;
        if (!seen.add(p.basenameWithoutExtension(base))) existing++;
      }
    }
  }

  final rootId = existingFolder(null, name);
  await walk(
    root,
    rootId,
    rootId == null ? {} : (titlesByFolder[rootId] ?? {}).toSet(),
  );
  return FolderImportPreview(total: total, existing: existing);
}

/// Imports a folder of Markdown files: a new Noote folder named after it,
/// subfolders as subfolders, each `.md`/`.markdown`/`.txt` file as a note
/// (title = file name, date = the file's modification time). All in one
/// transaction.
///
/// With [attachments], images a note links to by relative path
/// (`![](images/photo.jpg)`) are added as attachments, and so is any other
/// file linked on a line of its own (`[Kit.pdf](files/Kit.pdf)`), which
/// becomes a file block. Hidden files and
/// folders are skipped, and so are folders holding only other files (like
/// those images) — but empty folders are kept.
///
/// With [addMissingOnly], it adds to what's already there instead: a
/// top-level folder with the same name, and same-named folders inside it,
/// are reused, and a note is skipped if its folder already has an active
/// note with the same title — e.g. to bring in what's new in a fresh export
/// without duplicating (or overwriting) notes imported earlier.
Future<FolderImportResult> importMarkdownDirectory(
  String path, {
  required AppDatabase db,
  required FoldersRepository folders,
  required NotesRepository notes,
  AttachmentStore? attachments,
  bool addMissingOnly = false,
}) async {
  final root = Directory(path);
  final name = p.basename(p.normalize(path));
  var noteCount = 0;
  var folderCount = 0;
  var skipped = 0;
  final failed = <String>[];

  // What's already there, for addMissingOnly.
  final existingFolders = addMissingOnly
      ? await db.foldersDao.getAllFoldersOnce()
      : const <FolderRow>[];
  String? existingFolder(String? parentId, String name) {
    for (final f in existingFolders) {
      if (f.parentId == parentId && f.name == name) return f.id;
    }
    return null;
  }

  final titlesByFolder = <String?, Set<String>>{};
  if (addMissingOnly) {
    final rows = await (db.select(
      db.notesTable,
    )..where((n) => n.isDeleted.equals(false))).get();
    for (final row in rows) {
      (titlesByFolder[row.folderId] ??= {}).add(row.title);
    }
  }

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
          var id = existingFolder(folderId, base);
          if (id == null) {
            id = await folders.createFolder(name: base, parentId: folderId);
            folderCount++;
          }
          await walk(entry, id);
        } else if (entry is File &&
            _extensions.contains(p.extension(base).toLowerCase())) {
          final title = p.basenameWithoutExtension(base);
          final titles = titlesByFolder[folderId] ??= {};
          if (addMissingOnly && titles.contains(title)) {
            skipped++;
            continue;
          }
          try {
            var markdown = await entry.readAsString();
            var files = const <String, ({String name, int size})>{};
            if (attachments != null) {
              markdown = await _importLinkedImages(
                markdown,
                from: entry.parent.path,
                attachments: attachments,
              );
              (markdown, files) = await _importLinkedFiles(
                markdown,
                from: entry.parent.path,
                attachments: attachments,
              );
            }
            Map<String, dynamic> body = noteMarkdownToDocument(markdown)
                .toJson();
            if (files.isNotEmpty) body = _toFileBlocks(body, files);
            await notes.createNote(
              folderId: folderId,
              title: title,
              body: body,
              modifiedAt: await entry.lastModified(),
            );
            titles.add(title);
            noteCount++;
          } catch (_) {
            failed.add(p.relative(entry.path, from: root.path));
          }
        }
      }
    }

    final existingRoot = existingFolder(null, name);
    if (existingRoot != null) {
      rootId = existingRoot;
    } else {
      rootId = await folders.createFolder(name: name);
      folderCount++;
    }
    await walk(root, rootId);
  });

  return FolderImportResult(
    rootFolderId: rootId,
    folderName: name,
    notes: noteCount,
    folders: folderCount,
    skippedNotes: skipped,
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

/// A line that's nothing but a link: `[Kit.pdf](files/Kit.pdf)`.
final _fileLinkLine = RegExp(
  r'^[ \t]*\[([^\]\n]+)\]\(<?([^)>\n]+?)>?\)[ \t]*$',
  multiLine: true,
);

/// Adds files linked on a line of their own as attachments. Each such line
/// becomes an image-style link to the attachment, which [_toFileBlocks]
/// then turns into a file block (images stay pictures). Links to the web,
/// to other notes, and to missing files stay as they are.
Future<(String, Map<String, ({String name, int size})>)> _importLinkedFiles(
  String markdown, {
  required String from,
  required AttachmentStore attachments,
}) async {
  final files = <String, ({String name, int size})>{};
  final lines = <String, String>{}; // matched line -> replacement
  for (final match in _fileLinkLine.allMatches(markdown)) {
    final line = match.group(0)!;
    final name = match.group(1)!.trim();
    final target = match.group(2)!.trim();
    if (lines.containsKey(line) ||
        target.contains(':') ||
        target.startsWith('#')) {
      continue;
    }
    String decoded;
    try {
      decoded = Uri.decodeComponent(target);
    } catch (_) {
      decoded = target;
    }
    final file = File(p.normalize(p.join(from, decoded)));
    final extension = p
        .extension(file.path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (_extensions.contains('.$extension') || !await file.exists()) continue;
    if (isImageExtension(extension)) {
      lines[line] = '![](${await attachments.addImageFile(file.path)})';
    } else {
      final ref = await attachments.addFileFromPath(file.path);
      files[ref] = (name: name, size: await file.length());
      lines[line] = '![]($ref)';
    }
  }
  if (lines.isEmpty) return (markdown, files);
  final rewritten = markdown.replaceAllMapped(
    _fileLinkLine,
    (m) => lines[m.group(0)!] ?? m.group(0)!,
  );
  return (rewritten, files);
}

/// The image blocks pointing at [files] become file blocks (with the name
/// and size to show before the file is downloaded).
Map<String, dynamic> _toFileBlocks(
  Map<String, dynamic> body,
  Map<String, ({String name, int size})> files,
) {
  Object? convert(Object? node) {
    if (node is! Map) return node;
    final data = node['data'];
    final url = data is Map ? data['url'] : null;
    final file = url is String ? files[url] : null;
    if (node['type'] == 'image' && file != null) {
      return {
        'type': FileBlockKeys.type,
        'data': {
          FileBlockKeys.url: url,
          FileBlockKeys.name: file.name,
          FileBlockKeys.size: file.size,
        },
      };
    }
    final children = node['children'];
    return {
      ...node,
      if (children is List) 'children': [for (final c in children) convert(c)],
    };
  }

  return {...body, 'document': convert(body['document'])};
}
