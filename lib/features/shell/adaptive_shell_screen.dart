import 'package:flutter/material.dart';

import '../../core/utils/breakpoints.dart';
import 'widgets/desktop_shell.dart';

/// Picks [DesktopShell] (three panes, one window for every route) or the
/// route's own phone screen ([mobile]) based on width. [noteId] comes from
/// `/notes/:noteId`.
class AdaptiveShellScreen extends StatelessWidget {
  const AdaptiveShellScreen({super.key, required this.mobile, this.noteId});

  final Widget mobile;
  final String? noteId;

  @override
  Widget build(BuildContext context) {
    if (isDesktop(context)) return DesktopShell(noteId: noteId);
    return mobile;
  }
}
