import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/attachments/attachment_refs.dart';
import '../../../data/providers/attachments_provider.dart';
import '../../../data/providers/device_settings_provider.dart';

/// Opens a file on this device in its usual app (Preview for a PDF,
/// QuickTime for a recording, …). A provider so tests can replace it.
final openFileProvider = Provider<Future<bool> Function(String path)>(
  (ref) =>
      (path) => launchUrl(Uri.file(path)),
);

/// Draws the first page of the PDF at a path on this device. A provider so
/// tests can replace it (PDFium isn't available under `flutter test`).
final pdfFirstPageProvider = Provider<Widget Function(String path)>(
  (ref) =>
      (path) => _PdfFirstPage(path: path),
);

/// A file in a note (see [FileBlockKeys]): its name, type and size, shown
/// straight from the note. A PDF also shows its first page, like Apple
/// Notes (which downloads it); other files are only downloaded when opened
/// or saved.
class AttachmentFileBlockComponentBuilder extends BlockComponentBuilder {
  AttachmentFileBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return AttachmentFileBlock(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta == null && node.children.isEmpty;
}

class AttachmentFileBlock extends BlockComponentStatefulWidget {
  const AttachmentFileBlock({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<AttachmentFileBlock> createState() => _AttachmentFileBlockState();
}

class _AttachmentFileBlockState extends State<AttachmentFileBlock>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final _cardKey = GlobalKey();
  bool _busy = false;

  String? _previewFor;
  Future<String?>? _previewPath;

  bool get _isPdf => _extension == 'pdf';

  /// A PDF switched with the block's own button keeps that; the others
  /// follow Settings → "PDFs in notes".
  bool get _showPreview {
    if (!_isPdf) return false;
    return switch (node.attributes[FileBlockKeys.view]) {
      FileBlockKeys.viewCard => false,
      FileBlockKeys.viewPreview => true,
      _ => _previewByDefault?.read() ?? true,
    };
  }

  ProviderSubscription<bool>? _previewByDefault;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _previewByDefault ??= ProviderScope.containerOf(context, listen: false)
        .listen<bool>(pdfPreviewByDefaultProvider, (_, _) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _previewByDefault?.close();
    super.dispose();
  }

  /// The file for the preview, downloaded once and kept across rebuilds;
  /// fetched again if the url changes or [retry] is used.
  Future<String?> _previewFile({bool retry = false}) {
    final url = node.attributes[FileBlockKeys.url] as String?;
    if (!retry && _previewFor == url && _previewPath != null) {
      return _previewPath!;
    }
    _previewFor = url;
    return _previewPath = _localPath();
  }

  void _setView(String view) {
    final transaction = editorState.transaction
      ..updateNode(node, {FileBlockKeys.view: view});
    editorState.apply(transaction);
  }

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = legacy.Provider.of<EditorState>(
    context,
    listen: false,
  );

  String get _name =>
      (node.attributes[FileBlockKeys.name] as String?)?.trim().isNotEmpty ==
          true
      ? node.attributes[FileBlockKeys.name] as String
      : 'File';

  String get _extension {
    final dot = _name.lastIndexOf('.');
    if (dot > 0) return _name.substring(dot + 1).toLowerCase();
    final id = attachmentIdOf(node.attributes[FileBlockKeys.url]) ?? '';
    final idDot = id.lastIndexOf('.');
    return idDot > 0 ? id.substring(idDot + 1) : '';
  }

  /// The file on this device, downloading it first if needed.
  Future<String?> _localPath() async {
    final id = attachmentIdOf(node.attributes[FileBlockKeys.url]);
    if (id == null) return null;
    final container = ProviderScope.containerOf(context, listen: false);
    return container.read(attachmentStoreProvider).ensureLocalPath(id);
  }

  Future<void> _withFile(
    Future<void> Function(String path) action,
    String failure,
  ) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final path = await _localPath();
      if (path == null) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              '"$_name" isn\'t available right now. Check your connection '
              'and try again.',
            ),
          ),
        );
        return;
      }
      await action(path);
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() {
    final open = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(openFileProvider);
    return _withFile((path) async {
      if (!await open(path)) throw StateError('not opened');
    }, 'Couldn\'t open "$_name" on this device.');
  }

  Future<void> _saveCopy() => _withFile((path) async {
    final location = await getSaveLocation(suggestedName: _name);
    if (location == null) return;
    await XFile(path).saveTo(location.path);
  }, 'Couldn\'t save a copy of "$_name".');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final size = (node.attributes[FileBlockKeys.size] as num?)?.toInt();
    final details = [
      if (_extension.isNotEmpty) _extension.toUpperCase(),
      if (size != null) formatFileSize(size),
    ].join(' · ');

    final bar = Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderSoft),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _iconFor(_extension),
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11.5,
                          color: colors.textFaint,
                        ),
                      ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                IconButton(
                  tooltip: 'Open',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: colors.textFaint,
                  icon: const Icon(Icons.open_in_new),
                  onPressed: _open,
                ),
                IconButton(
                  tooltip: 'Save a copy…',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: colors.textFaint,
                  icon: const Icon(Icons.download_outlined),
                  onPressed: _saveCopy,
                ),
                if (_isPdf && editorState.editable)
                  IconButton(
                    tooltip: _showPreview
                        ? 'Show as small card'
                        : 'Show preview',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    color: colors.textFaint,
                    icon: Icon(
                      _showPreview
                          ? Icons.photo_size_select_small
                          : Icons.photo_size_select_large,
                    ),
                    onPressed: () => _setView(
                      _showPreview
                          ? FileBlockKeys.viewCard
                          : FileBlockKeys.viewPreview,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    Widget child = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        key: _cardKey,
        constraints: BoxConstraints(maxWidth: _showPreview ? 560 : 440),
        child: _showPreview
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [_preview(colors), const SizedBox(height: 6), bar],
              )
            : bar,
      ),
    );

    child = Padding(padding: padding, child: child);

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return Padding(padding: margin, child: child);
  }

  Widget _preview(NooteColors colors) {
    return FutureBuilder<String?>(
      future: _previewFile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _PreviewMessage(
            colors: colors,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final path = snapshot.data;
        if (path == null) {
          return _PreviewMessage(
            colors: colors,
            text: 'Preview not available right now',
            onRetry: () => setState(() => _previewFile(retry: true)),
          );
        }
        final drawFirstPage = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(pdfFirstPageProvider);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _open,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(color: colors.borderSoft),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: drawFirstPage(path),
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _iconFor(String extension) => switch (extension) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'm4a' || 'mp3' || 'wav' || 'aac' => Icons.audio_file_outlined,
    'mp4' || 'mov' => Icons.video_file_outlined,
    'zip' => Icons.folder_zip_outlined,
    'txt' || 'md' || 'csv' || 'json' => Icons.description_outlined,
    _ when isImageExtension(extension) => Icons.image_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  // Selection and cursor, as for appflowy_editor's image block.

  @override
  Position start() => Position(path: widget.node.path);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _cardKey.currentContext?.findRenderObject();
    if (box is RenderBox) return Offset.zero & box.size;
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return null;
    final size = _renderBox!.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return [];
    final parentBox = context.findRenderObject();
    final cardBox = _cardKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && cardBox is RenderBox) {
      return [
        cardBox.localToGlobal(Offset.zero, ancestor: parentBox) & cardBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);
}

/// The first page of a PDF, sized to the page's shape.
class _PdfFirstPage extends StatelessWidget {
  const _PdfFirstPage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooteColors;
    return PdfDocumentViewBuilder.file(
      path,
      builder: (context, document) {
        if (document == null || document.pages.isEmpty) {
          return _PreviewMessage(
            colors: colors,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final page = document.pages.first;
        return AspectRatio(
          aspectRatio: page.width / page.height,
          child: PdfPageView(
            document: document,
            pageNumber: 1,
            backgroundColor: Colors.white,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _PreviewMessage(
        colors: colors,
        text: 'Couldn\'t show a preview of this PDF',
      ),
    );
  }
}

/// The preview area while loading, or when there's nothing to show.
class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.colors,
    this.text,
    this.child,
    this.onRetry,
  });

  final NooteColors colors;
  final String? text;
  final Widget? child;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border.all(color: colors.borderSoft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?child,
          if (text != null)
            Text(
              text!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: colors.textFaint,
              ),
            ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
