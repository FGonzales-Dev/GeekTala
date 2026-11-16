import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../utils/breakpoints.dart';

// Phones drill down — Folders → a folder → a note — by pushing each screen
// over the last, so Back (and Android's back gesture) walks back up.
// [from] is what that Back button says: the screen it returns to.

/// Opens note [id]. On desktop it replaces the open note in the window; on
/// phones it slides in over the current screen.
void openNote(BuildContext context, String id, {String? from}) {
  if (isDesktop(context)) {
    context.go('/notes/$id');
  } else {
    context.push('/notes/$id', extra: from);
  }
}

/// Phones: opens a folder's notes (`'all'` for All Notes).
void openFolder(BuildContext context, String folderId, {String? from}) =>
    context.push('/folders/$folderId', extra: from);

/// Phones: opens a tag's notes.
void openTag(BuildContext context, String tagId, {String? from}) =>
    context.push('/tags/$tagId', extra: from);

/// Goes back a screen, or to Folders when there's nothing to go back to
/// (e.g. the app was opened straight onto a note).
void goBack(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/');
  }
}
