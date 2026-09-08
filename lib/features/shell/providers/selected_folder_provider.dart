import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The currently selected folder id, driving which folder's notes are
/// shown in the notes-list pane / mobile filter chip.
class SelectedFolderId extends Notifier<String?> {
  @override
  String? build() => 'engineering';

  void select(String? folderId) => state = folderId;
}

final selectedFolderIdProvider = NotifierProvider<SelectedFolderId, String?>(
  SelectedFolderId.new,
);
