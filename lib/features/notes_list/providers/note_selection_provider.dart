import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notes picked with ⌘-click (Ctrl-click off Apple platforms) or
/// Shift-click in the desktop notes list, to drag, move or delete together.
///
/// A selection belongs to the note that was open when it was made
/// ([openNoteId]): opening another note in any way ends it, without
/// every navigation path having to clear it.
class NoteSelectionState {
  const NoteSelectionState({this.ids = const {}, this.anchor, this.openNoteId});

  final Set<String> ids;

  /// The last ⌘/plain-clicked note — where a Shift-click range starts.
  final String? anchor;
  final String? openNoteId;

  /// The selected notes while [currentOpenNoteId] is open (empty once
  /// another note has been opened).
  Set<String> idsFor(String? currentOpenNoteId) =>
      openNoteId == currentOpenNoteId ? ids : const {};
}

class NoteSelection extends Notifier<NoteSelectionState> {
  @override
  NoteSelectionState build() => const NoteSelectionState();

  void clear() => state = const NoteSelectionState();

  /// ⌘/Ctrl-click: adds or removes [id]. Starting a selection includes the
  /// open note, so ⌘-clicking a second note selects both.
  void toggle(String id, {required String? openNoteId}) {
    final ids = {...state.idsFor(openNoteId)};
    if (ids.isEmpty && openNoteId != null && openNoteId != id) {
      ids.add(openNoteId);
    }
    if (!ids.remove(id)) ids.add(id);
    state = NoteSelectionState(ids: ids, anchor: id, openNoteId: openNoteId);
  }

  /// Shift-click: every note from the anchor (or the open note) to [id],
  /// in the order of [visibleIds].
  void selectRange(
    List<String> visibleIds,
    String id, {
    required String? openNoteId,
  }) {
    final to = visibleIds.indexOf(id);
    if (to < 0) return;
    final anchor = state.openNoteId == openNoteId ? state.anchor : null;
    var from = visibleIds.indexOf(anchor ?? openNoteId ?? id);
    if (from < 0) from = to;
    final (start, end) = from <= to ? (from, to) : (to, from);
    state = NoteSelectionState(
      ids: visibleIds.sublist(start, end + 1).toSet(),
      anchor: visibleIds[from],
      openNoteId: openNoteId,
    );
  }
}

final noteSelectionProvider =
    NotifierProvider<NoteSelection, NoteSelectionState>(NoteSelection.new);

/// ⌘ on macOS/iOS, Ctrl elsewhere — the "add to selection" modifier.
bool isToggleSelectPressed() {
  final keys = HardwareKeyboard.instance;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => keys.isMetaPressed,
    _ => keys.isControlPressed,
  };
}
