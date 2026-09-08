import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/notes_providers.dart';
import 'editor_top_bar.dart';
import 'note_editor_body.dart';

/// `.editor-pane` — desktop/web, inline in the three-pane shell.
/// [noteId] comes from the current route (`/notes/:noteId`).
class EditorPane extends ConsumerWidget {
  const EditorPane({super.key, this.noteId});

  final String? noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = noteId == null
        ? null
        : ref.watch(noteByIdProvider(noteId!)).value;

    if (note == null) {
      return Center(
        child: Text(
          'Select a note',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: context.nooteColors.textFaint,
          ),
        ),
      );
    }

    return Column(
      children: [
        EditorTopBar(note: note),
        Expanded(child: NoteEditorBody(noteId: noteId!)),
      ],
    );
  }
}
