import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;

import '../../../core/theme/app_colors.dart';
import '../../../data/attachments/attachment_refs.dart';
import '../../../data/providers/attachments_provider.dart';

/// appflowy_editor's image block, but able to show `attachment://` images:
/// it finds the file on this device, or downloads it first (see
/// `AttachmentStore.ensureLocal`). Web addresses and file paths work as
/// before.
///
/// The selection/cursor behaviour is copied from appflowy_editor's
/// `ImageBlockComponentWidget`, which can't be reused here because it
/// reads its image source straight from the node.
class AttachmentImageBlockComponentBuilder extends BlockComponentBuilder {
  AttachmentImageBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return AttachmentImageBlock(
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

class AttachmentImageBlock extends BlockComponentStatefulWidget {
  const AttachmentImageBlock({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<AttachmentImageBlock> createState() => _AttachmentImageBlockState();
}

class _AttachmentImageBlockState extends State<AttachmentImageBlock>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final imageKey = GlobalKey();

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = legacy.Provider.of<EditorState>(
    context,
    listen: false,
  );

  String? _resolvingFor;
  Future<String?>? _localPath;

  /// The device path for an `attachment://` url (downloading if needed);
  /// kept across rebuilds, redone if the url changes or [retry] is used.
  Future<String?> _resolve(String url, {bool retry = false}) {
    if (!retry && _resolvingFor == url && _localPath != null) {
      return _localPath!;
    }
    _resolvingFor = url;
    final id = attachmentIdOf(url);
    final store = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(attachmentStoreProvider);
    return _localPath = id == null
        ? Future.value(null)
        : store.ensureLocalPath(id);
  }

  @override
  Widget build(BuildContext context) {
    final attributes = node.attributes;
    final url = attributes[ImageBlockKeys.url] as String? ?? '';
    final alignment = _alignment(attributes[ImageBlockKeys.align] as String?);
    final width =
        (attributes[ImageBlockKeys.width] as num?)?.toDouble() ??
        MediaQuery.of(context).size.width;
    final height = (attributes[ImageBlockKeys.height] as num?)?.toDouble();

    Widget image(String src) => ResizableImage(
      src: src,
      width: width,
      height: height,
      editable: editorState.editable,
      alignment: alignment,
      onResize: (width) {
        final transaction = editorState.transaction
          ..updateNode(node, {ImageBlockKeys.width: width});
        editorState.apply(transaction);
      },
    );

    Widget child = isAttachmentRef(url)
        ? FutureBuilder<String?>(
            future: _resolve(url),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _Placeholder(loading: true);
              }
              final path = snapshot.data;
              if (path == null) {
                return _Placeholder(
                  loading: false,
                  onRetry: () => setState(() => _resolve(url, retry: true)),
                );
              }
              return image(path);
            },
          )
        : image(url);

    child = Padding(key: imageKey, padding: padding, child: child);

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

  static Alignment _alignment(String? name) => switch (name) {
    'left' => Alignment.centerLeft,
    'right' => Alignment.centerRight,
    _ => Alignment.center,
  };

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
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) return Offset.zero & imageBox.size;
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
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && imageBox is RenderBox) {
      return [
        imageBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            imageBox.size,
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

/// Shown while an image downloads, or when it can't be had right now.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.loading, this.onRetry});

  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooteColors;
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border.all(color: colors.borderSoft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('Loading image…', style: _style(colors)),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 16,
                  color: colors.textFaint,
                ),
                const SizedBox(width: 8),
                Text('Image not available right now', style: _style(colors)),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
              ],
            ),
    );
  }

  static TextStyle _style(NooteColors colors) =>
      TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: colors.textFaint);
}
