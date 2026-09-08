import 'package:flutter/material.dart';

import '../../core/utils/breakpoints.dart';
import '../note_editor/widgets/mobile_note_editor_screen.dart';
import 'widgets/desktop_shell.dart';
import 'widgets/mobile_shell.dart';

/// Picks [DesktopShell] (three-pane) or [MobileShell] (bottom-nav) based on
/// width. [noteId] comes from `/notes/:noteId`; [currentPath] is the
/// mobile tab route (`/`, `/folders`, `/shared`, `/settings`) — irrelevant
/// on desktop, where the sidebar/list/editor are always all visible at once.
class AdaptiveShellScreen extends StatelessWidget {
  const AdaptiveShellScreen({
    super.key,
    required this.currentPath,
    this.noteId,
  });

  final String currentPath;
  final String? noteId;

  @override
  Widget build(BuildContext context) {
    if (isDesktop(context)) {
      return DesktopShell(noteId: noteId);
    }
    if (noteId != null) {
      return MobileNoteEditorScreen(noteId: noteId!);
    }
    return MobileShell(currentPath: currentPath);
  }
}
