import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/attachments/attachment_refs.dart';
import '../../data/attachments/attachment_store.dart';
import '../../data/providers/attachments_provider.dart';

export '../../data/attachments/attachment_store.dart' show attachmentsSupported;

typedef FileInput = ({Uint8List bytes, String name});

bool isImageFileName(String name) =>
    isImageExtension(p.extension(name).replaceFirst('.', ''));

/// A file block (see [FileBlockKeys]).
Node fileNode({required String url, required String name, required int size}) {
  return Node(
    type: FileBlockKeys.type,
    attributes: {
      FileBlockKeys.url: url,
      FileBlockKeys.name: name,
      FileBlockKeys.size: size,
    },
  );
}

/// Adds [files] as attachments and puts them in the note after the cursor's
/// line: images as pictures, anything else as a file block. Files that
/// can't be added are reported via [messenger].
Future<void> insertFiles(
  AttachmentStore store,
  EditorState editorState,
  List<FileInput> files, {
  ScaffoldMessengerState? messenger,
}) async {
  final nodes = <Node>[];
  for (final file in files) {
    try {
      // A pasted picture has no file name; recognise it by its bytes.
      final isImage =
          isImageFileName(file.name) ||
          (p.extension(file.name).isEmpty &&
              imageExtensionOf(file.bytes) != null);
      if (isImage) {
        final ref = await store.addImage(file.bytes, fileName: file.name);
        nodes.add(imageNode(url: ref));
      } else {
        final ref = await store.addFile(file.bytes, fileName: file.name);
        nodes.add(fileNode(url: ref, name: file.name, size: file.bytes.length));
      }
    } on AttachmentTooLargeException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Couldn\'t add "${file.name}".')),
      );
    }
  }
  if (nodes.isNotEmpty) await insertBlocks(editorState, nodes);
}

/// Reads picked, dropped or pasted files — refusing any over the size limit
/// before loading it into memory.
Future<List<FileInput>> readFiles(
  Iterable<XFile> files, {
  ScaffoldMessengerState? messenger,
}) async {
  final result = <FileInput>[];
  for (final file in files) {
    try {
      if (await file.length() > maxAttachmentBytes) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(AttachmentTooLargeException(file.name).toString()),
          ),
        );
        continue;
      }
      result.add((bytes: await file.readAsBytes(), name: file.name));
    } catch (_) {
      // A folder, or a file that can't be read: skip it.
    }
  }
  return result;
}

/// [nodes] after the cursor's block — or in its place if it's an empty
/// line — followed by an empty line if they'd otherwise end the note, with
/// the cursor after them.
Future<void> insertBlocks(EditorState editorState, List<Node> nodes) {
  final root = editorState.document.root;
  final selection = editorState.selection;
  final current =
      (selection == null
          ? null
          : editorState.getNodeAtPath(selection.end.path)) ??
      root.children.lastOrNull;
  final replace =
      current != null &&
      current.type == ParagraphBlockKeys.type &&
      (current.delta?.isEmpty ?? false) &&
      current.children.isEmpty;
  final Path at = current == null
      ? const [0]
      : replace
      ? current.path
      : current.path.next;
  final after = current?.next;

  final transaction = editorState.transaction..insertNodes(at, nodes);
  if (replace) transaction.deleteNode(current);
  final next = [...at.sublist(0, at.length - 1), at.last + nodes.length];
  if (after == null) transaction.insertNode(next, paragraphNode());
  transaction.afterSelection = Selection.collapsed(Position(path: next));
  return editorState.apply(transaction);
}

/// The toolbar's attach button: pick any files and add them.
Future<void> pickAndInsertFiles(
  BuildContext context,
  WidgetRef ref,
  EditorState editorState,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final store = ref.read(attachmentStoreProvider);
  final picked = await openFiles();
  if (picked.isEmpty) return;
  final files = await readFiles(picked, messenger: messenger);
  await insertFiles(store, editorState, files, messenger: messenger);
}
