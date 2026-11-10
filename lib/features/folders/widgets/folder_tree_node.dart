import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/drag_auto_scroll.dart';
import '../../../data/models/folder.dart';
import '../../../data/models/folder_tree.dart';
import '../../../data/providers/folders_providers.dart';
import '../collapsed_folders_provider.dart';
import '../drag_data.dart';
import '../folder_actions.dart';
import 'delete_folder_dialog.dart';
import 'folder_name_dialog.dart';
import 'move_to_folder_picker.dart';

/// Renders [folder] via [rowBuilder], then recurses into its children
/// (unless it's collapsed — see [collapsedFoldersProvider]) —
/// arbitrary depth, not hardcoded to one level. Shared by the desktop
/// sidebar and the mobile Folders screen; each supplies its own row visual
/// via [rowBuilder] so this widget only owns the tree structure, the
/// long-press/right-click "New subfolder / Rename / Move to… / Delete"
/// menu, and (with [dragAndDrop]) dragging folders and dropping folders
/// and notes onto them.
class FolderTreeNode extends ConsumerWidget {
  const FolderTreeNode({
    super.key,
    required this.folder,
    required this.tree,
    required this.depth,
    required this.noteCounts,
    required this.selectedFolderId,
    required this.onSelect,
    required this.rowBuilder,
    this.dragAndDrop = false,
  });

  final Folder folder;
  final FolderTree tree;
  final int depth;
  final Map<String, int> noteCounts;
  final String? selectedFolderId;
  final ValueChanged<String> onSelect;
  final Widget Function(
    BuildContext context, {
    required Folder folder,
    required int depth,
    required bool selected,
    required int noteCount,
    required VoidCallback onTap,

    /// Whether the subfolders are showing; null when there are none.
    bool? expanded,

    /// Shows/hides the subfolders (the row's disclosure arrow).
    VoidCallback? onToggle,
  })
  rowBuilder;

  /// Desktop sidebar only. On the mobile Folders screen a long press opens
  /// the menu instead (which has "Move to…").
  final bool dragAndDrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = tree.childrenOf(folder.id);
    final collapsed = ref.watch(
      collapsedFoldersProvider.select((ids) => ids.contains(folder.id)),
    );
    final expanded = children.isEmpty ? null : !collapsed;

    Widget row = GestureDetector(
      onSecondaryTapDown: (details) =>
          _showActionsMenu(context, ref, details.globalPosition),
      onLongPressStart: (details) =>
          _showActionsMenu(context, ref, details.globalPosition),
      child: rowBuilder(
        context,
        folder: folder,
        depth: depth,
        selected: folder.id == selectedFolderId,
        noteCount: noteCounts[folder.id] ?? 0,
        onTap: () => onSelect(folder.id),
        expanded: expanded,
        onToggle: expanded == null
            ? null
            : () => ref.read(collapsedFoldersProvider.notifier).toggle(folder.id),
      ),
    );
    if (dragAndDrop) {
      row = _FolderDragAndDrop(
        key: ValueKey(folder.id),
        folder: folder,
        tree: tree,
        depth: depth,
        child: row,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        if (expanded ?? false)
          for (final child in children)
            FolderTreeNode(
              key: ValueKey(child.id),
              folder: child,
              tree: tree,
              depth: depth + 1,
              noteCounts: noteCounts,
              selectedFolderId: selectedFolderId,
              onSelect: onSelect,
              rowBuilder: rowBuilder,
              dragAndDrop: dragAndDrop,
            ),
      ],
    );
  }

  Future<void> _showActionsMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final repository = ref.read(foldersRepositoryProvider);
    // Personal and Shared can't be deleted, and only move within the top
    // level (by dragging), so "Move to…" would have nowhere to offer.
    final protected = repository.isProtected(folder.id);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'new_subfolder', child: Text('New subfolder')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (!protected) const PopupMenuItem(value: 'move', child: Text('Move to…')),
        if (!protected) const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'new_subfolder':
        final name = await showFolderNameDialog(
          context,
          title: 'New subfolder',
          confirmLabel: 'Create',
        );
        if (name != null) {
          await repository.createFolder(name: name, parentId: folder.id);
        }
      case 'rename':
        final name = await showFolderNameDialog(
          context,
          title: 'Rename folder',
          initialName: folder.name,
          confirmLabel: 'Rename',
        );
        if (name != null) await repository.renameFolder(folder.id, name);
      case 'move':
        final tree = ref.read(folderTreeProvider);
        final target = await showMoveToFolderPicker(
          context,
          title: 'Move "${folder.name}"',
          tree: tree,
          offerTopLevel: true,
          // Not where it already is.
          isAllowed: (id) =>
              tree.canMove(folder.id, into: id) &&
              tree.parentOf(folder.id) != id,
        );
        if (target != null && context.mounted) {
          await moveFolderTo(context, ref, folder.id, parentId: target.folderId);
        }
      case 'delete':
        await showDeleteFolderDialog(
          context,
          ref,
          folderId: folder.id,
          folderName: folder.name,
        );
    }
  }
}

/// Where on a folder row something is dropped. A folder can go above or
/// below the row (top/bottom quarter) or inside it (the middle); notes
/// always go inside.
enum _DropZone { before, into, after }

/// Makes a sidebar folder row draggable, and a drop target for notes and
/// other folders.
class _FolderDragAndDrop extends ConsumerStatefulWidget {
  const _FolderDragAndDrop({
    super.key,
    required this.folder,
    required this.tree,
    required this.depth,
    required this.child,
  });

  final Folder folder;
  final FolderTree tree;
  final int depth;
  final Widget child;

  @override
  ConsumerState<_FolderDragAndDrop> createState() => _FolderDragAndDropState();
}

class _FolderDragAndDropState extends ConsumerState<_FolderDragAndDrop> {
  /// Matches the sidebar row's indentation (`_NavItem` in app_sidebar.dart),
  /// so an insertion line starts where the folder name's row does.
  static const _indentBase = 8.0;
  static const _indentPerLevel = 16.0;

  _DropZone? _zone;

  /// Opens a collapsed folder when something is held over it while
  /// dragging, so it can be dropped deeper in.
  Timer? _openTimer;
  static const _openAfter = Duration(milliseconds: 700);

  Folder get _folder => widget.folder;
  FolderTree get _tree => widget.tree;

  bool get _collapsed =>
      ref.read(collapsedFoldersProvider).contains(_folder.id);

  /// The bottom edge of a folder with subfolders listed under it means
  /// "first inside it", not "after it" (which is below all of those).
  /// When it's collapsed they aren't listed, so it means "after it".
  bool _bottomMeansFirstChild(String draggedId) =>
      !_collapsed && _tree.childrenOf(_folder.id).any((f) => f.id != draggedId);

  @override
  void dispose() {
    _openTimer?.cancel();
    super.dispose();
  }

  /// Where dropping [draggedId] in [zone] puts it, or null if it can't go
  /// there or is already there.
  ({String? parentId, int index})? _placement(String draggedId, _DropZone zone) {
    if (draggedId == _folder.id) return null;
    final String? parentId;
    final int index;
    if (zone == _DropZone.into ||
        (zone == _DropZone.after && _bottomMeansFirstChild(draggedId))) {
      parentId = _folder.id;
      index = zone == _DropZone.after
          ? 0
          : _tree.childrenOf(parentId).where((f) => f.id != draggedId).length;
    } else {
      parentId = _tree.parentOf(_folder.id);
      final siblings = [
        for (final f in _tree.childrenOf(parentId))
          if (f.id != draggedId) f.id,
      ];
      final at = siblings.indexOf(_folder.id);
      index = zone == _DropZone.before ? at : at + 1;
    }
    if (!_tree.canMove(draggedId, into: parentId)) return null;
    final dragged = _tree[draggedId]!;
    final alreadyThere = dragged.parentId == parentId &&
        _tree.childrenOf(parentId).indexWhere((f) => f.id == draggedId) == index;
    return alreadyThere ? null : (parentId: parentId, index: index);
  }

  bool _accepts(NooteDragData data) => switch (data) {
    NotesDragData(:final folderIds) => folderIds.any((id) => id != _folder.id),
    FolderDragData(:final folderId) => _DropZone.values.any(
      (zone) => _placement(folderId, zone) != null,
    ),
  };

  _DropZone? _zoneAt(NooteDragData data, Offset globalPosition) {
    switch (data) {
      case NotesDragData():
        return _accepts(data) ? _DropZone.into : null;
      case FolderDragData(:final folderId):
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return null;
        final y = box.globalToLocal(globalPosition).dy / box.size.height;
        final zone = y < 0.25
            ? _DropZone.before
            : y > 0.75
            ? _DropZone.after
            : _DropZone.into;
        return _placement(folderId, zone) == null ? null : zone;
    }
  }

  void _setZone(_DropZone? zone) {
    if (zone != _zone) setState(() => _zone = zone);
    final hoveringInside = zone == _DropZone.into && _collapsed;
    if (!hoveringInside) {
      _openTimer?.cancel();
      _openTimer = null;
    } else {
      _openTimer ??= Timer(_openAfter, () {
        _openTimer = null;
        if (mounted) {
          ref.read(collapsedFoldersProvider.notifier).expand(_folder.id);
        }
      });
    }
  }

  Future<void> _drop(NooteDragData data, _DropZone zone) async {
    switch (data) {
      case NotesDragData(:final noteIds):
        await moveNotesTo(context, ref, noteIds, _folder.id);
      case FolderDragData(:final folderId):
        final placement = _placement(folderId, zone);
        if (placement == null) return;
        await moveFolderTo(
          context,
          ref,
          folderId,
          parentId: placement.parentId,
          index: placement.index,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoScroll = ref.read(dragAutoScrollProvider);
    final draggable = Draggable<NooteDragData>(
      data: FolderDragData(_folder.id),
      // Hit-test drop targets at the pointer itself, so the top/bottom
      // quarter of a row means what it looks like.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: DragFeedbackChip(label: _folder.name, icon: AppIconName.folder),
      childWhenDragging: Opacity(opacity: 0.4, child: widget.child),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      child: widget.child,
    );

    return DragTarget<NooteDragData>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (details) => _setZone(_zoneAt(details.data, details.offset)),
      onLeave: (_) => _setZone(null),
      onAcceptWithDetails: (details) {
        final zone = _zoneAt(details.data, details.offset);
        _setZone(null);
        if (zone != null) _drop(details.data, zone);
      },
      builder: (context, candidates, _) => _withIndicator(
        draggable,
        candidates.isEmpty ? null : _zone,
        candidates.firstOrNull,
      ),
    );
  }

  Widget _withIndicator(Widget row, _DropZone? zone, NooteDragData? data) {
    if (zone == null) return row;
    final color = Theme.of(context).colorScheme.primary;
    if (zone == _DropZone.into) {
      return Container(
        foregroundDecoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: row,
      );
    }
    // A line under a folder with subfolders marks "first inside it", so it
    // starts one level in.
    final intoFirst = zone == _DropZone.after &&
        data is FolderDragData &&
        _bottomMeansFirstChild(data.folderId);
    final level = widget.depth + (intoFirst ? 1 : 0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        row,
        Positioned(
          left: _indentBase + level * _indentPerLevel,
          right: 0,
          top: zone == _DropZone.before ? -1 : null,
          bottom: zone == _DropZone.after ? -1 : null,
          child: IgnorePointer(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
