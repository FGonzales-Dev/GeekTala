import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/router/navigation.dart';
import '../../core/utils/breakpoints.dart';
import '../../core/widgets/noote_dialog.dart';

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
  if (context.mounted) openNote(context, id);
}

/// Picks a folder and imports every Markdown file in it, keeping its
/// subfolders (see [importMarkdownDirectory]) — e.g. an export from Apple
/// Notes or Obsidian. Opens the new folder when done.
///
/// If a top-level folder with the same name already exists (e.g. an earlier
/// import of the same export), asks whether to add only the notes that
/// aren't there yet or import everything as a separate folder.
Future<void> importMarkdownFolder(BuildContext context, WidgetRef ref) async {
  final path = await getDirectoryPath(confirmButtonText: 'Import');
  if (path == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  final name = p.basename(p.normalize(path));
  final db = ref.read(appDatabaseProvider);
  var addMissingOnly = false;
  if (ref.read(folderTreeProvider).roots.any((f) => f.name == name)) {
    final FolderImportPreview preview;
    try {
      preview = await previewMarkdownDirectory(path, db: db);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t read that folder ($e).')),
      );
      return;
    }
    if (!context.mounted) return;
    final choice = await showNooteDialog<bool>(
      context,
      builder: (context) => _ImportIntoExistingDialog(
        name: name,
        preview: preview,
      ),
    );
    if (choice == null || !context.mounted) return;
    addMissingOnly = choice;
  }

  showNooteDialog<void>(
    context,
    dismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: NooteDialog(
        icon: Icons.download_outlined,
        title: 'Importing “$name”…',
        subtitle: 'Notes, subfolders and attached files.',
        autofocus: false,
        body: const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: LinearProgressIndicator(minHeight: 3),
        ),
      ),
    ),
  );

  FolderImportResult? result;
  Object? error;
  try {
    result = await importMarkdownDirectory(
      path,
      db: db,
      folders: ref.read(foldersRepositoryProvider),
      notes: ref.read(notesRepositoryProvider),
      attachments: attachmentsSupported
          ? ref.read(attachmentStoreProvider)
          : null,
      addMissingOnly: addMissingOnly,
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
  if (context.mounted && !isDesktop(context)) {
    openFolder(context, result.rootFolderId);
  }
  final n = result.notes;
  final failed = result.failedFiles.length;
  final notes = '$n ${n == 1 ? 'note' : 'notes'}';
  final skipped = result.skippedNotes;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        (addMissingOnly
            ? 'Added $notes to "${result.folderName}"; $skipped '
                  '${skipped == 1 ? 'was' : 'were'} already there'
            : 'Imported $notes into "${result.folderName}"') +
            (failed == 0
                ? '.'
                : '; $failed ${failed == 1 ? 'file' : 'files'} couldn\'t be read.'),
      ),
    ),
  );
}

/// "Import “Apple Notes”": a folder with that name is already there. Pops
/// `true` to add only the missing notes (preselected), `false` to import
/// everything as a separate folder.
class _ImportIntoExistingDialog extends StatefulWidget {
  const _ImportIntoExistingDialog({required this.name, required this.preview});

  final String name;
  final FolderImportPreview preview;

  @override
  State<_ImportIntoExistingDialog> createState() =>
      _ImportIntoExistingDialogState();
}

class _ImportIntoExistingDialogState extends State<_ImportIntoExistingDialog> {
  var _addMissing = true;

  static String _notes(int n) => '$n ${n == 1 ? 'note' : 'notes'}';

  void _import() => Navigator.of(context).pop(_addMissing);

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final missing = preview.missing;
    final there = preview.existing;
    return NooteDialog(
      icon: Icons.download_outlined,
      title: 'Import “${widget.name}”',
      subtitle: 'You already have a folder with this name.',
      onSubmit: _addMissing && missing == 0 ? null : _import,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NooteOptionCard(
            selected: _addMissing,
            recommended: true,
            title: 'Add the missing notes',
            description: missing == 0
                ? 'Nothing to add: all ${_notes(there)} are already there.'
                : '$missing new · $there already there and left as they are.',
            onTap: () => setState(() => _addMissing = true),
          ),
          NooteOptionCard(
            selected: !_addMissing,
            title: 'Import everything as a new folder',
            description:
                'All ${_notes(preview.total)}, alongside the existing folder.',
            onTap: () => setState(() => _addMissing = false),
          ),
        ],
      ),
      hint: KeyHint([const Kbd('↵'), ' to import']),
      actions: [
        NooteButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        NooteButton.primary(
          _addMissing
              ? (missing == 0 ? 'Nothing to add' : 'Add ${_notes(missing)}')
              : 'Import ${_notes(preview.total)}',
          onPressed: _addMissing && missing == 0 ? null : _import,
        ),
      ],
    );
  }
}

/// Converts the note's already-persisted body to markdown (via
/// appflowy_editor's `documentToMarkdown`) and offers a native save dialog.
Future<void> exportNoteAsMarkdown(BuildContext context, Note note) async {
  final markdown = noteDocumentToMarkdown(Document.fromJson(note.body));
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
