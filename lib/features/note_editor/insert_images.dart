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

typedef ImageInput = ({Uint8List bytes, String name});

bool isImageFileName(String name) => imageExtensions.contains(
  p.extension(name).replaceFirst('.', '').toLowerCase(),
);

/// Adds [images] as attachments and puts them in the note after the
/// cursor's line. Files that can't be added are reported via [messenger].
Future<void> insertImages(
  AttachmentStore store,
  EditorState editorState,
  List<ImageInput> images, {
  ScaffoldMessengerState? messenger,
}) async {
  final refs = <String>[];
  for (final image in images) {
    try {
      refs.add(await store.addImage(image.bytes, fileName: image.name));
    } on AttachmentTooLargeException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Couldn\'t add "${image.name}" as an image.')),
      );
    }
  }
  if (refs.isNotEmpty) await insertImageNodes(editorState, refs);
}

/// Image blocks for [refs] after the cursor's block — or in its place if
/// it's an empty line — followed by an empty line if they'd otherwise end
/// the note, with the cursor after them.
Future<void> insertImageNodes(EditorState editorState, List<String> refs) {
  final root = editorState.document.root;
  final selection = editorState.selection;
  final current =
      (selection == null
          ? null
          : editorState.getNodeAtPath(selection.end.path)) ??
      root.children.lastOrNull;
  final images = [for (final ref in refs) imageNode(url: ref)];
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

  final transaction = editorState.transaction..insertNodes(at, images);
  if (replace) transaction.deleteNode(current);
  final next = [...at.sublist(0, at.length - 1), at.last + images.length];
  if (after == null) transaction.insertNode(next, paragraphNode());
  transaction.afterSelection = Selection.collapsed(Position(path: next));
  return editorState.apply(transaction);
}

/// The toolbar's image button: pick image files and add them.
Future<void> pickAndInsertImages(
  BuildContext context,
  WidgetRef ref,
  EditorState editorState,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final store = ref.read(attachmentStoreProvider);
  final files = await openFiles(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Images',
        extensions: imageExtensions.toList(),
        uniformTypeIdentifiers: const ['public.image'],
      ),
    ],
  );
  if (files.isEmpty) return;
  final images = <ImageInput>[
    for (final file in files)
      (bytes: await file.readAsBytes(), name: file.name),
  ];
  await insertImages(store, editorState, images, messenger: messenger);
}
