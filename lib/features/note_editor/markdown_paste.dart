import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/device_settings_provider.dart';
import 'markdown_convert.dart';

// ---------------------------------------------------------------------------
// Preference
// ---------------------------------------------------------------------------

/// Settings → "When pasting Markdown": true = format it (the default),
/// false = keep the Markdown text. Remembered on this device.
final pasteMarkdownFormattedProvider = Provider<bool>((ref) {
  return ref.watch(
        deviceSettingsProvider.select(
          (s) => s.value?[DeviceSettingKeys.pasteMarkdown],
        ),
      ) !=
      'markdown';
});

Future<void> setPasteMarkdownFormatted(WidgetRef ref, bool formatted) {
  return ref.read(writeDeviceSettingProvider)(
    DeviceSettingKeys.pasteMarkdown,
    formatted ? 'formatted' : 'markdown',
  );
}

// ---------------------------------------------------------------------------
// Paste
// ---------------------------------------------------------------------------

/// Pastes Markdown into one note's editor — formatted, or as the raw
/// Markdown text — and lets the user swap the paste for the other version
/// (see [MarkdownPasteBar]) until they carry on editing.
///
/// Text that doesn't look like Markdown ([looksLikeMarkdown]) goes through
/// the editor's normal paste, unchanged.
class MarkdownPaste extends ChangeNotifier {
  MarkdownPaste(
    this._editorState, {
    required this.formattedByDefault,
    this.pasteImages,
  }) {
    _transactions = _editorState.transactionStream.listen((_) {
      // Any edit that isn't part of a paste or swap ends the offer.
      if (!_busy) dismiss();
    });
  }

  final EditorState _editorState;

  /// The Settings preference, read at paste time.
  final bool Function() formattedByDefault;

  /// Tried first on ⌘V: pastes images on the clipboard, if any. Returns
  /// whether it did.
  final Future<bool> Function()? pasteImages;

  /// The editor this pastes into (also used by the mobile editor's image
  /// button, via [MarkdownPasteTargets]).
  EditorState get editorState => _editorState;
  late final StreamSubscription<EditorTransactionValue> _transactions;
  _LastPaste? _last;
  bool _busy = false;
  Timer? _hideTimer;

  /// How long the swap offer stays up if the user does nothing.
  static const offerDuration = Duration(seconds: 12);

  /// Whether the last paste went in formatted; null when there's no paste
  /// to swap.
  bool? get lastPasteFormatted => _last?.formatted;

  /// The editor's standard shortcuts, with ⌘V/Ctrl+V replaced by this.
  /// ⌘⇧V (paste as plain text) is left as it is.
  late final List<CommandShortcutEvent> commandShortcutEvents = [
    for (final event in standardCommandShortcutEvents)
      if (event.key != pasteCommand.key) event,
    CommandShortcutEvent(
      key: pasteCommand.key,
      getDescription: () => pasteCommand.description ?? 'Paste',
      command: 'ctrl+v',
      macOSCommand: 'cmd+v',
      handler: (editorState) {
        if (editorState.selection == null) return KeyEventResult.ignored;
        unawaited(_pasteFromShortcut());
        return KeyEventResult.handled;
      },
    ),
  ];

  Future<void> _pasteFromShortcut() async {
    if (await pasteImages?.call() ?? false) return;
    final text = (await AppFlowyClipboard.getData()).text;
    if (text == null || text.isEmpty) return;
    if (!looksLikeMarkdown(text)) {
      // The editor's own paste (it also turns a pasted URL into a link).
      pasteCommand.handler(_editorState);
      return;
    }
    await paste(text, formatted: formattedByDefault());
  }

  /// The mobile editor's "Paste Markdown" menu item: always formatted,
  /// since the user asked for it. Returns false if the clipboard is empty.
  Future<bool> pasteClipboardFormatted() async {
    final text = (await AppFlowyClipboard.getData()).text;
    if (text == null || text.trim().isEmpty) return false;
    if (_editorState.selection == null) {
      // Opening the menu can take the cursor away; paste at the end.
      final last = _editorState.document.root.children.lastOrNull;
      if (last == null) return false;
      _editorState.selection = Selection.collapsed(
        Position(path: last.path, offset: last.delta?.length ?? 0),
      );
    }
    await paste(text, formatted: true);
    return true;
  }

  /// Pastes [text] at the selection as formatted blocks or as plain lines
  /// of Markdown, and offers the other version.
  Future<void> paste(String text, {required bool formatted}) async {
    if (_editorState.selection == null) return;
    await _run(() async {
      final before = _Snapshot.of(_editorState);
      await _insert(text, formatted: formatted);
      _offer(_LastPaste(text: text, formatted: formatted, before: before));
    });
  }

  /// Replaces the last paste with the other version.
  Future<void> swap() async {
    final last = _last;
    if (last == null) return;
    await _run(() async {
      await last.before.restore(_editorState);
      await _insert(last.text, formatted: !last.formatted);
      _offer(last.swapped());
    });
  }

  void dismiss() {
    _hideTimer?.cancel();
    if (_last == null) return;
    _last = null;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }

  void _offer(_LastPaste paste) {
    _last = paste;
    _hideTimer?.cancel();
    _hideTimer = Timer(offerDuration, dismiss);
    notifyListeners();
  }

  Future<void> _insert(String text, {required bool formatted}) async {
    final formattedNodes = _formattedNodes(text);
    final nodes = formatted ? formattedNodes : _plainNodes(text);
    if (nodes.isEmpty) return;

    // Markdown that starts with a heading, list, table… pasted at the start
    // or end of a line goes on its own line(s), rather than being merged
    // into that line (the editor's default). Decided from the formatted
    // version so both versions land in the same place.
    final selection = await _editorState.deleteSelectionIfNeeded();
    if (selection == null) return;
    final node = _editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    final startsWithBlock =
        formattedNodes.firstOrNull?.type != ParagraphBlockKeys.type;
    if (node != null &&
        delta != null &&
        delta.isNotEmpty &&
        startsWithBlock &&
        (selection.startIndex == 0 || selection.startIndex == delta.length)) {
      final atEnd = selection.startIndex == delta.length;
      final at = atEnd ? node.path.next : node.path;
      Path shifted(int by) => [...at.sublist(0, at.length - 1), at.last + by];
      final last = nodes.last;
      final transaction = _editorState.transaction
        ..insertNodes(at, nodes)
        ..afterSelection = atEnd
            ? Selection.collapsed(
                Position(
                  path: shifted(nodes.length - 1),
                  offset: last.delta?.length ?? 0,
                ),
              )
            : Selection.collapsed(Position(path: shifted(nodes.length)));
      await _editorState.apply(transaction);
      return;
    }

    if (nodes.length == 1) {
      await _editorState.pasteSingleLineNode(nodes.single);
    } else {
      await _editorState.pasteMultiLineNodes(nodes);
    }
  }

  static List<Node> _formattedNodes(String text) {
    final nodes = noteMarkdownToDocument(text).root.children.toList();
    bool blank(Node n) => n.delta?.isEmpty == true && n.children.isEmpty;
    while (nodes.isNotEmpty && blank(nodes.first)) {
      nodes.removeAt(0);
    }
    while (nodes.isNotEmpty && blank(nodes.last)) {
      nodes.removeLast();
    }
    return nodes;
  }

  /// One paragraph per line, exactly as typed.
  static List<Node> _plainNodes(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
    return [for (final line in lines) paragraphNode(text: line)];
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_transactions.cancel());
    super.dispose();
  }
}

class _LastPaste {
  const _LastPaste({
    required this.text,
    required this.formatted,
    required this.before,
  });

  final String text;
  final bool formatted;

  /// The note as it was just before the paste.
  final _Snapshot before;

  _LastPaste swapped() =>
      _LastPaste(text: text, formatted: !formatted, before: before);
}

/// The whole note body and selection. Swapping restores this and pastes
/// again: simpler and more reliable than working out which blocks a paste
/// created (the editor merges pasted text into the blocks around it).
class _Snapshot {
  _Snapshot._(this._nodes, this._selection);

  factory _Snapshot.of(EditorState editorState) => _Snapshot._([
    for (final node in editorState.document.root.children) node.deepCopy(),
  ], editorState.selection);

  final List<Node> _nodes;
  final Selection? _selection;

  Future<void> restore(EditorState editorState) {
    final transaction = editorState.transaction
      ..deleteNodes(editorState.document.root.children.toList())
      ..insertNodes([0], [for (final node in _nodes) node.deepCopy()])
      ..afterSelection = _selection;
    return editorState.apply(transaction);
  }
}

// ---------------------------------------------------------------------------
// The swap bar
// ---------------------------------------------------------------------------

/// "Pasted as formatted text · Show as Markdown ×", shown over the editor
/// right after a Markdown paste.
class MarkdownPasteBar extends StatelessWidget {
  const MarkdownPasteBar({super.key, required this.controller});

  final MarkdownPaste controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final formatted = controller.lastPasteFormatted;
        if (formatted == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final colors = context.nooteColors;
        // Clicking the bar mustn't take focus (and the cursor) away from
        // the editor.
        return ExcludeFocus(
          child: Material(
            elevation: 4,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.only(left: 14, right: 4),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatted
                        ? 'Pasted as formatted text'
                        : 'Pasted as Markdown text',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      color: colors.textFaint,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: controller.swap,
                    child: Text(
                      formatted ? 'Show as Markdown' : 'Show formatted',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.dismiss,
                    icon: Icon(Icons.close, color: colors.textFaint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The open editors' [MarkdownPaste]s by note id — for the mobile editor
/// screen's "Paste Markdown" menu item; `NoteEditorBody` owns them.
class MarkdownPasteTargets {
  final _byNoteId = <String, MarkdownPaste>{};

  MarkdownPaste? operator [](String noteId) => _byNoteId[noteId];

  void register(String noteId, MarkdownPaste paste) =>
      _byNoteId[noteId] = paste;

  void unregister(String noteId, MarkdownPaste paste) {
    if (_byNoteId[noteId] == paste) _byNoteId.remove(noteId);
  }
}

final markdownPasteTargetsProvider = Provider<MarkdownPasteTargets>(
  (ref) => MarkdownPasteTargets(),
);
