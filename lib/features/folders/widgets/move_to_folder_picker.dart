import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/noote_dialog.dart';
import '../../../data/models/folder_tree.dart';

/// Where to move notes or a folder: a dialog on desktop, a bottom sheet on
/// phones. Type to find a folder, <kbd>↑</kbd>/<kbd>↓</kbd> to pick,
/// <kbd>↵</kbd> to move. Returns the chosen folder — `(folderId: null)`
/// for the top level — or null if cancelled.
///
/// Folders [isAllowed] rejects are shown greyed out; [current] (where the
/// notes or folder are now) is marked "Current".
Future<({String? folderId})?> showMoveToFolderPicker(
  BuildContext context, {
  required String title,
  required FolderTree tree,
  required bool Function(String? folderId) isAllowed,
  bool offerTopLevel = false,
  ({String? folderId})? current,
}) {
  return showNooteDialog<({String? folderId})>(
    context,
    builder: (context) => _MovePicker(
      title: title,
      tree: tree,
      isAllowed: isAllowed,
      offerTopLevel: offerTopLevel,
      current: current,
    ),
  );
}

/// One row in the picker: [folderId] null is "Top level".
typedef _Row = ({String? folderId, String label, int depth, bool enabled});

class _MovePicker extends StatefulWidget {
  const _MovePicker({
    required this.title,
    required this.tree,
    required this.isAllowed,
    required this.offerTopLevel,
    required this.current,
  });

  final String title;
  final FolderTree tree;
  final bool Function(String? folderId) isAllowed;
  final bool offerTopLevel;
  final ({String? folderId})? current;

  @override
  State<_MovePicker> createState() => _MovePickerState();
}

class _MovePickerState extends State<_MovePicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  /// Index into [_rows] of the picked folder, or null.
  int? _picked;
  late List<_Row> _rows = _buildRows('');

  static const _rowHeight = 34.0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Row> _buildRows(String query) {
    final tree = widget.tree;
    final q = query.trim().toLowerCase();
    return [
      if (widget.offerTopLevel && q.isEmpty)
        (
          folderId: null,
          label: 'Top level',
          depth: 0,
          enabled: widget.isAllowed(null),
        ),
      for (final (:folder, :depth) in tree.flatten())
        if (!tree.isHiddenShared(folder.id) &&
            (q.isEmpty || folder.name.toLowerCase().contains(q)))
          (
            folderId: folder.id,
            // While searching the list is flat, so show where each one is.
            label: q.isEmpty ? folder.name : tree.pathOf(folder.id),
            depth: q.isEmpty ? depth : 0,
            enabled: widget.isAllowed(folder.id),
          ),
    ];
  }

  void _onSearch(String query) {
    setState(() {
      _rows = _buildRows(query);
      // Typing picks the first match, so Enter moves straight there.
      final first = _rows.indexWhere((r) => r.enabled);
      _picked = query.trim().isEmpty || first < 0 ? null : first;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _step(int delta) {
    if (_rows.isEmpty) return;
    var i = _picked ?? (delta > 0 ? -1 : _rows.length);
    for (var n = 0; n < _rows.length; n++) {
      i += delta;
      if (i < 0 || i >= _rows.length) return;
      if (_rows[i].enabled) break;
    }
    if (!_rows[i].enabled) return;
    setState(() => _picked = i);
    _reveal(i);
  }

  void _reveal(int i) {
    if (!_scroll.hasClients) return;
    final top = i * _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowHeight - view);
    }
  }

  void _move() {
    final picked = _picked;
    if (picked == null) return;
    Navigator.of(context).pop((folderId: _rows[picked].folderId));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _step(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final picked = _picked == null ? null : _rows[_picked!];
    final pickedName = picked == null
        ? null
        : picked.folderId == null
        ? 'the top level'
        : widget.tree[picked.folderId!]?.name;
    final from = current?.folderId;

    return NooteDialog(
      icon: Icons.drive_file_move_outlined,
      title: widget.title,
      subtitle: from == null ? null : 'From ${widget.tree.pathOf(from)}',
      autofocus: false,
      onSubmit: _move,
      body: Focus(
        onKeyEvent: _onKey,
        skipTraversal: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NooteField(
              controller: _search,
              hint: 'Find a folder',
              search: true,
              onChanged: _onSearch,
              onSubmitted: (_) => _move(),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: context.nooteColors.borderSoft),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 6.5 * _rowHeight),
                child: _rows.isEmpty
                    ? const _NoMatch()
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: _rows.length,
                        itemBuilder: (context, i) {
                          final row = _rows[i];
                          return _PickerRow(
                            row: row,
                            isCurrent:
                                current != null &&
                                current.folderId == row.folderId,
                            picked: i == _picked,
                            onTap: () => setState(() => _picked = i),
                            onDoubleTap: () {
                              setState(() => _picked = i);
                              _move();
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      hint: KeyHint([
        const Kbd('↑'),
        const Kbd('↓'),
        ' pick · ',
        const Kbd('↵'),
        ' move',
      ]),
      actions: [
        NooteButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        NooteButton.primary(
          pickedName == null ? 'Move' : 'Move to $pickedName',
          onPressed: picked == null ? null : _move,
        ),
      ],
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No folder by that name.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.5,
          color: context.nooteColors.textFaint,
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.row,
    required this.isCurrent,
    required this.picked,
    required this.onTap,
    required this.onDoubleTap,
  });

  final _Row row;
  final bool isCurrent;
  final bool picked;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final enabled = row.enabled;
    final fg = enabled ? theme.colorScheme.onSurface : colors.textFaint;
    return Material(
      color: picked ? colors.activeBg : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: enabled ? onTap : null,
        onDoubleTap: enabled ? onDoubleTap : null,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: EdgeInsets.only(left: 9 + row.depth * 18.0, right: 9),
          child: Row(
            children: [
              if (row.folderId == null)
                Icon(
                  Icons.vertical_align_top,
                  size: 15,
                  color: colors.textFaint,
                )
              else
                AppIcon(AppIconName.folder, size: 15, color: colors.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: picked ? FontWeight.w500 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ),
              if (isCurrent)
                Text(
                  'Current',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    color: colors.textFaint,
                  ),
                )
              else if (picked)
                Icon(Icons.check, size: 15, color: theme.colorScheme.onSurface),
            ],
          ),
        ),
      ),
    );
  }
}
