import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The currently selected tag id, driving which tag's notes are shown in
/// the notes-list pane. Mutually exclusive with folder selection and
/// search — see `notes_list_pane.dart`'s precedence (search > tag >
/// folder).
class SelectedTagId extends Notifier<String?> {
  @override
  String? build() => null;

  /// Selecting the already-selected tag clears it (tap to toggle off).
  void toggle(String tagId) => state = state == tagId ? null : tagId;

  void clear() => state = null;
}

final selectedTagIdProvider = NotifierProvider<SelectedTagId, String?>(
  SelectedTagId.new,
);
