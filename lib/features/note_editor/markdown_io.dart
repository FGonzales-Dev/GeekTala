import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/note.dart';
import '../../data/providers/notes_providers.dart';
import 'markdown_convert.dart';

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
