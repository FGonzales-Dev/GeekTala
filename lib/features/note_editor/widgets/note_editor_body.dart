import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/sync_provider.dart';
import '../../../data/sync/pending_writes.dart';
import '../markdown_paste.dart';
import 'note_tag_picker.dart';
import 'styled_title_controller.dart';

/// Title field + real `AppFlowyEditor` body, shared by the desktop
/// [EditorPane] and [MobileNoteEditorScreen].
///
/// Owns an [EditorState] (and title [TextEditingController]) per open
/// note, seeded **once** from Drift via a one-time `ref.read(...future)` —
/// not a reactive `ref.watch`, which would recreate the [EditorState] (and
/// reset cursor/selection) on every stream emission, including the ones
/// caused by this widget's own saves. Changes flow one-way out to Drift
/// on a debounce; they don't flow back in while the note is open — except
/// after a sync download, which reloads the note from Drift.
///
/// Pending debounced saves are registered with [PendingWrites] so upload
/// and download can write them out first, and are written (not dropped)
/// when switching to another note.
///
/// Pasting Markdown goes through [MarkdownPaste]: formatted or as Markdown
/// text (Settings), with a bar to swap to the other right after.
class NoteEditorBody extends ConsumerStatefulWidget {
  const NoteEditorBody({super.key, required this.noteId, this.desktop = true});

  final String noteId;
  final bool desktop;

  @override
  ConsumerState<NoteEditorBody> createState() => _NoteEditorBodyState();
}

/// Standard block builders, but the paragraph placeholder shows whenever
/// the line is empty — not only while it's focused, which is
/// [ParagraphBlockComponentBuilder]'s default. Mirrors the title field's
/// `hintText`, which is likewise always visible until you type, regardless
/// of focus.
Map<String, BlockComponentBuilder> _blockComponentBuilders(bool desktop) => {
  ...standardBlockComponentBuilderMap,
  ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
    configuration: standardBlockComponentConfiguration.copyWith(
      placeholderText: (_) =>
          desktop ? AppFlowyEditorL10n.current.slashPlaceHolder : ' ',
    ),
    showPlaceholder: (editorState, node) => node.delta?.isEmpty ?? true,
  ),
};

/// Which field the pinned toolbar currently formats. Sticky rather than a
/// live `hasFocus` read: tapping a toolbar button steals focus from
/// whichever field had it *before* the tap's `onPressed` fires, so a live
/// read would flip the toolbar out from under the user mid-tap.
enum _ToolbarTarget { title, body }

const _titleColorSwatches = [
  '#EF4444',
  '#F59E0B',
  '#22C55E',
  '#3B82F6',
  '#A855F7',
];

class _NoteEditorBodyState extends ConsumerState<NoteEditorBody> {
  static const _saveDebounce = Duration(milliseconds: 500);

  EditorState? _editorState;
  EditorScrollController? _editorScrollController;
  StyledTitleController? _titleController;
  FocusNode? _titleFocusNode;
  Timer? _bodyDebounceTimer;
  Timer? _titleDebounceTimer;
  Future<void> Function()? _pendingBodySave;
  Future<void> Function()? _pendingTitleSave;
  late final PendingWrites _pendingWrites;
  late final MarkdownPasteTargets _pasteTargets;
  MarkdownPaste? _markdownPaste;
  String? _loadedNoteId;
  _ToolbarTarget _toolbarTarget = _ToolbarTarget.body;

  @override
  void initState() {
    super.initState();
    _pendingWrites = ref.read(pendingWritesProvider)..register(_flushSaves);
    _pasteTargets = ref.read(markdownPasteTargetsProvider);
    _load();
  }

  @override
  void didUpdateWidget(covariant NoteEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _teardown();
      _load();
    }
  }

  @override
  void dispose() {
    _pendingWrites.unregister(_flushSaves);
    _teardown();
    super.dispose();
  }

  void _teardown() {
    unawaited(_flushSaves());
    _disposeMarkdownPaste(_loadedNoteId, _markdownPaste);
    _markdownPaste = null;
    _titleFocusNode?.dispose();
    _titleController?.dispose();
    _editorScrollController?.dispose();
    _editorState?.dispose();
    _editorState = null;
    _editorScrollController = null;
    _titleController = null;
    _titleFocusNode = null;
    _loadedNoteId = null;
    _toolbarTarget = _ToolbarTarget.body;
  }

  void _disposeMarkdownPaste(String? noteId, MarkdownPaste? paste) {
    if (paste == null) return;
    if (noteId != null) _pasteTargets.unregister(noteId, paste);
    paste.dispose();
  }

  /// Writes any debounced save now instead of waiting for its timer.
  Future<void> _flushSaves() async {
    _bodyDebounceTimer?.cancel();
    _titleDebounceTimer?.cancel();
    final saves = [?_pendingBodySave, ?_pendingTitleSave];
    _pendingBodySave = null;
    _pendingTitleSave = null;
    await Future.wait([for (final save in saves) save()]);
  }

  /// After a download the database holds the server's copy of this note;
  /// reload it rather than keep editing (and later saving) the old one.
  void _reloadAfterDownload() {
    if (!mounted || _loadedNoteId == null) return;
    // The download flushed saves before it started; anything typed during
    // it loses to the server copy the user chose to download.
    _bodyDebounceTimer?.cancel();
    _titleDebounceTimer?.cancel();
    _pendingBodySave = null;
    _pendingTitleSave = null;
    final old = (
      _titleFocusNode,
      _titleController,
      _editorScrollController,
      _editorState,
    );
    _disposeMarkdownPaste(_loadedNoteId, _markdownPaste);
    setState(() {
      _markdownPaste = null;
      _editorState = null;
      _editorScrollController = null;
      _titleController = null;
      _titleFocusNode = null;
      _loadedNoteId = null;
      _toolbarTarget = _ToolbarTarget.body;
    });
    // Disposed once the old editor widgets are gone from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.$1?.dispose();
      old.$2?.dispose();
      old.$3?.dispose();
      old.$4?.dispose();
    });
    _load(fresh: true);
  }

  /// [fresh] reads straight from Drift: right after a download the cached
  /// `noteByIdProvider` value may not have caught up yet.
  Future<void> _load({bool fresh = false}) async {
    final noteId = widget.noteId;
    final note = fresh
        ? await ref.read(notesRepositoryProvider).watchNoteById(noteId).first
        : await ref.read(noteByIdProvider(noteId).future);
    if (!mounted || note == null || widget.noteId != noteId) return;

    final editorState = EditorState(document: Document.fromJson(note.body));
    editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) {
        _scheduleBodySave(noteId, editorState);
      }
    });
    // Pre-seeds a valid (but invisible until clicked) cursor position so the
    // pinned toolbar's items — which hide themselves when there's no
    // selection at all — show up immediately instead of only after the
    // first click into the body.
    editorState.selection = Selection.collapsed(Position(path: const [0]));
    final markdownPaste = MarkdownPaste(
      editorState,
      formattedByDefault: () =>
          ref.read(pasteMarkdownFormattedProvider),
    );
    _pasteTargets.register(noteId, markdownPaste);
    editorState.selectionNotifier.addListener(() {
      if (mounted &&
          _titleFocusNode?.hasFocus != true &&
          _toolbarTarget != _ToolbarTarget.body) {
        setState(() => _toolbarTarget = _ToolbarTarget.body);
      }
    });

    final titleController = StyledTitleController(
      text: note.title,
      runs: note.titleStyle,
    );
    titleController.addListener(() {
      _scheduleTitleSave(noteId, titleController);
    });

    final titleFocusNode = FocusNode();
    titleFocusNode.addListener(() {
      if (mounted &&
          titleFocusNode.hasFocus &&
          _toolbarTarget != _ToolbarTarget.title) {
        setState(() => _toolbarTarget = _ToolbarTarget.title);
      }
    });

    setState(() {
      _loadedNoteId = noteId;
      _editorState = editorState;
      _markdownPaste = markdownPaste;
      _editorScrollController = EditorScrollController(
        editorState: editorState,
      );
      _titleController = titleController;
      _titleFocusNode = titleFocusNode;
      _toolbarTarget = _ToolbarTarget.body;
    });
  }

  // The save closures capture the repository up front so they can still
  // run from `_teardown` (during dispose, where `ref` is off-limits).
  void _scheduleBodySave(String noteId, EditorState editorState) {
    final repository = ref.read(notesRepositoryProvider);
    _pendingBodySave = () =>
        repository.updateBody(noteId, editorState.document.toJson());
    _bodyDebounceTimer?.cancel();
    _bodyDebounceTimer = Timer(_saveDebounce, () {
      final save = _pendingBodySave;
      _pendingBodySave = null;
      save?.call();
    });
  }

  void _scheduleTitleSave(String noteId, StyledTitleController controller) {
    final repository = ref.read(notesRepositoryProvider);
    _pendingTitleSave = () => repository.updateTitle(
          noteId,
          controller.text,
          style: controller.runs,
        );
    _titleDebounceTimer?.cancel();
    _titleDebounceTimer = Timer(_saveDebounce, () {
      final save = _pendingTitleSave;
      _pendingTitleSave = null;
      save?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      syncControllerProvider.select((s) => s.downloadCount),
      (_, _) => _reloadAfterDownload(),
    );
    // Keeps the paste preference loaded for `MarkdownPaste`.
    ref.watch(pasteMarkdownFormattedProvider);
    final editorState = _editorState;
    final markdownPaste = _markdownPaste;
    final editorScrollController = _editorScrollController;
    final titleController = _titleController;
    final titleFocusNode = _titleFocusNode;
    if (editorState == null ||
        markdownPaste == null ||
        editorScrollController == null ||
        titleController == null ||
        titleFocusNode == null ||
        _loadedNoteId != widget.noteId) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final titlePadding = widget.desktop
        ? const EdgeInsets.fromLTRB(20, 16, 20, 0)
        : const EdgeInsets.fromLTRB(18, 6, 18, 0);

    final editorOnly = AppFlowyEditor(
      key: ValueKey(widget.noteId),
      editorState: editorState,
      editorScrollController: editorScrollController,
      commandShortcutEvents: markdownPaste.commandShortcutEvents,
      blockComponentBuilders: _blockComponentBuilders(widget.desktop),
      editorStyle: widget.desktop
          ? _desktopStyle(theme, colors)
          : _mobileStyle(theme, colors),
      header: Padding(
        padding: titlePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              focusNode: titleFocusNode,
              maxLines: null,
              style: AppTextStyles.editorTitle.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Untitled',
                hintStyle: AppTextStyles.editorTitle.copyWith(
                  color: colors.textFaint,
                ),
              ),
            ),
            const SizedBox(height: 10),
            NoteTagPicker(noteId: widget.noteId),
          ],
        ),
      ),
      // Bottom breathing room, matching the mockup's editor-scroll padding.
      // This goes in `footer`, not `editorStyle.padding` — that padding is
      // applied to *every block* by appflowy_editor (confirmed by reading
      // page_block_component.dart), not once around the page; putting
      // vertical values there is what caused the huge per-line gaps.
      footer: const SizedBox(height: 40),
    );
    // The bar to swap a Markdown paste, floating over the editor's bottom.
    final editor = Stack(
      fit: StackFit.expand,
      children: [
        editorOnly,
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Center(child: MarkdownPasteBar(controller: markdownPaste)),
        ),
      ],
    );

    if (!widget.desktop) {
      // This toolbar lives under appflowy_editor's toolbar/desktop/ —
      // mobile gets its own selection handles/menu from the platform text
      // input, not this widget.
      return editor;
    }

    return Column(
      children: [
        // Pinned above the editor — not the selection-triggered
        // FloatingToolbar (that pops up/disappears with the selection);
        // this stays visible the whole time you're editing, and formats
        // whichever of the title/body currently has focus.
        Material(
          color: theme.colorScheme.surface,
          child: Container(
            height: 40,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _toolbarTarget == _ToolbarTarget.title
                ? _TitleToolbar(controller: titleController, theme: theme)
                : FloatingToolbarWidget(
                    items: [
                      paragraphItem,
                      ...headingItems,
                      ...markdownFormatItems,
                      quoteItem,
                      bulletedListItem,
                      numberedListItem,
                      linkItem,
                      buildTextColorItem(),
                      buildHighlightColorItem(),
                    ],
                    editorState: editorState,
                    textDirection: TextDirection.ltr,
                    floatingToolbarHeight: 32,
                    backgroundColor: Colors.transparent,
                    toolbarActiveColor: theme.colorScheme.primary,
                    toolbarIconColor: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
        Expanded(child: editor),
      ],
    );
  }

  EditorStyle _desktopStyle(ThemeData theme, NooteColors colors) {
    return EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      cursorColor: theme.colorScheme.primary,
      selectionColor: colors.selectionBg,
      textStyleConfiguration: _textStyleConfiguration(theme, colors),
    );
  }

  EditorStyle _mobileStyle(ThemeData theme, NooteColors colors) {
    return EditorStyle.mobile(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      cursorColor: theme.colorScheme.primary,
      selectionColor: colors.selectionBg,
      textStyleConfiguration: _textStyleConfiguration(theme, colors),
    );
  }

  TextStyleConfiguration _textStyleConfiguration(
    ThemeData theme,
    NooteColors colors,
  ) {
    final base = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13.5,
      height: 1.65,
      color: theme.colorScheme.onSurface,
    );
    return TextStyleConfiguration(
      // This is the field that actually controls rendered line height —
      // appflowy_editor overrides each TextStyle's `.height` with this
      // value at render time (see appflowy_rich_text.dart), so setting
      // `height:` on the styles below does nothing; this is the real knob.
      lineHeight: 1.4,
      text: base,
      bold: base.copyWith(fontWeight: FontWeight.w700),
      italic: base.copyWith(fontStyle: FontStyle.italic),
      underline: base.copyWith(decoration: TextDecoration.underline),
      strikethrough: base.copyWith(decoration: TextDecoration.lineThrough),
      href: base.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      // Temporary stand-in for the real code block (Build Order step 4) —
      // see the seed data's `_codeParagraph` for why inline `code` styling
      // is used instead of a block for now.
      code: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 12,
        height: 1.6,
        color: theme.colorScheme.onSurface,
        backgroundColor: colors.codeBg,
      ),
    );
  }
}

/// Bold/italic/underline/color for the title field — [StyledTitleController]
/// only supports inline styling (no headings/lists/quotes; a single-line
/// title has no use for block structure), so this is a reduced set next to
/// the body's full [FloatingToolbarWidget].
class _TitleToolbar extends StatefulWidget {
  const _TitleToolbar({required this.controller, required this.theme});

  final StyledTitleController controller;
  final ThemeData theme;

  @override
  State<_TitleToolbar> createState() => _TitleToolbarState();
}

class _TitleToolbarState extends State<_TitleToolbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _TitleToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final active = theme.colorScheme.primary;
    final inactive = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.format_bold, size: 18),
          color: widget.controller.selectionIsBold ? active : inactive,
          tooltip: 'Bold',
          visualDensity: VisualDensity.compact,
          onPressed: widget.controller.toggleBold,
        ),
        IconButton(
          icon: const Icon(Icons.format_italic, size: 18),
          color: widget.controller.selectionIsItalic ? active : inactive,
          tooltip: 'Italic',
          visualDensity: VisualDensity.compact,
          onPressed: widget.controller.toggleItalic,
        ),
        IconButton(
          icon: const Icon(Icons.format_underlined, size: 18),
          color: widget.controller.selectionIsUnderline ? active : inactive,
          tooltip: 'Underline',
          visualDensity: VisualDensity.compact,
          onPressed: widget.controller.toggleUnderline,
        ),
        PopupMenuButton<String?>(
          tooltip: 'Text color',
          icon: Icon(Icons.format_color_text, size: 18, color: inactive),
          onSelected: widget.controller.applyColor,
          itemBuilder: (context) => [
            const PopupMenuItem(value: null, child: Text('Default')),
            for (final hex in _titleColorSwatches)
              PopupMenuItem(
                value: hex,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Color(
                          int.parse(hex.substring(1), radix: 16) | 0xFF000000,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(hex),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
