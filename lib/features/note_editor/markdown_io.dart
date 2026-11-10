import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/note.dart';
import '../../data/attachments/attachment_store.dart';
import '../../data/providers/attachments_provider.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/folders_providers.dart';
import '../../data/providers/notes_providers.dart';
import '../shell/providers/is_viewing_trash_provider.dart';
import '../shell/providers/selected_folder_provider.dart';
import '../shell/providers/selected_tag_provider.dart';
import 'folder_import/folder_import.dart';
import 'markdown_convert.dart';

export 'folder_import/folder_import.dart' show canImportFolders;

const _markdownTypeGroup = XTypeGroup(
  label: 'Markdown',
  extensions: ['md', 'markdown', 'txt'],
);

/// Opens a native file picker for a `.md`/`.markdown`/`.txt` file, parses it
/// with [noteMarkdownToDocument], and creates a new note from the result.
/// Shared by the desktop notes-list pane and the mobile
/// notes tab.
Future<void> importMarkdownNote(
  BuildContext context,
  WidgetRef ref, {
  String? folderId,
}) async {
  final file = await openFile(acceptedTypeGroups: [_markdownTypeGroup]);
  if (file == null) return;

  Document document;
  try {
    final content = await file.readAsString();
    document = noteMarkdownToDocument(content);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t read "${file.name}" as Markdown')),
      );
    }
    return;
  }

  final title = file.name.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
  final id = await ref.read(notesRepositoryProvider).createNote(
        folderId: folderId,
        title: title,
        body: document.toJson(),
      );
  if (context.mounted) context.go('/notes/$id');
}

/// Picks a folder and imports every Markdown file in it, keeping its
/// subfolders (see [importMarkdownDirectory]) — e.g. an export from Apple
/// Notes or Obsidian. Opens the new folder when done.
Future<void> importMarkdownFolder(BuildContext context, WidgetRef ref) async {
  final path = await getDirectoryPath(confirmButtonText: 'Import');
  if (path == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Text('Importing notes…'),
        ],
      ),
    ),
  );

  FolderImportResult? result;
  Object? error;
  try {
    result = await importMarkdownDirectory(
      path,
      db: ref.read(appDatabaseProvider),
      folders: ref.read(foldersRepositoryProvider),
      notes: ref.read(notesRepositoryProvider),
      attachments: attachmentsSupported
          ? ref.read(attachmentStoreProvider)
          : null,
    );
  } catch (e) {
    error = e;
  }
  navigator.pop();

  if (result == null) {
    messenger.showSnackBar(
      SnackBar(content: Text('Couldn\'t import that folder ($error).')),
    );
    return;
  }
  ref.read(selectedFolderIdProvider.notifier).select(result.rootFolderId);
  ref.read(selectedTagIdProvider.notifier).clear();
  ref.read(isViewingTrashProvider.notifier).exit();
  final n = result.notes;
  final failed = result.failedFiles.length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Imported $n ${n == 1 ? 'note' : 'notes'} into "${result.folderName}"'
        '${failed == 0 ? '' : '; $failed ${failed == 1 ? 'file' : 'files'} couldn\'t be read'}.',
      ),
    ),
  );
}

/// Converts the note's already-persisted body to markdown (via
/// appflowy_editor's `documentToMarkdown`) and offers a native save dialog.
Future<void> exportNoteAsMarkdown(BuildContext context, Note note) async {
  final markdown = documentToMarkdown(Document.fromJson(note.body));
  final suggestedName = note.title.trim().isEmpty ? 'Untitled' : note.title;

  final location = await getSaveLocation(
    acceptedTypeGroups: [_markdownTypeGroup],
    suggestedName: '$suggestedName.md',
  );
  if (location == null) return;

  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode(markdown)),
    mimeType: 'text/markdown',
    name: '$suggestedName.md',
  );
  await file.saveTo(location.path);
}
