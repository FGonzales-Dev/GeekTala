import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/noote_dialog.dart';
import '../../../data/models/folder_tree.dart';

/// Single-field name dialog for renaming a folder or a tag — returns the
/// entered name, or `null` if cancelled or blank.
Future<String?> showFolderNameDialog(
  BuildContext context, {
  required String title,
  String? initialName,
  String confirmLabel = 'Save',
  String hintText = 'Name',
  IconData icon = Icons.edit_outlined,
}) {
  return showNooteDialog<String>(
    context,
    builder: (context) => _NameDialog(
      title: title,
      initialName: initialName,
      confirmLabel: confirmLabel,
      hintText: hintText,
      icon: icon,
    ),
  );
}

/// "New folder": a name, and the folder it goes inside ([parentId] to
/// start with; null = the top level). Returns both, or null if cancelled.
Future<({String name, String? parentId})?> showNewFolderDialog(
  BuildContext context, {
  required FolderTree tree,
  String? parentId,
}) {
  return showNooteDialog<({String name, String? parentId})>(
    context,
    builder: (context) => _NameDialog(
      title: parentId == null ? 'New folder' : 'New subfolder',
      confirmLabel: 'Create',
      hintText: 'Folder name',
      icon: Icons.create_new_folder_outlined,
      tree: tree,
      parentId: parentId,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    this.initialName,
    required this.confirmLabel,
    required this.hintText,
    required this.icon,
    this.tree,
    this.parentId,
  });

  final String title;
  final String? initialName;
  final String confirmLabel;
  final String hintText;
  final IconData icon;

  /// Set for "New folder": shows the "Inside" selector.
  final FolderTree? tree;
  final String? parentId;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialName)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName?.length ?? 0,
    );
  late String? _parentId = widget.parentId;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  void _submit() {
    if (_name.isEmpty) return;
    if (widget.tree == null) {
      Navigator.of(context).pop(_name);
    } else {
      Navigator.of(context).pop((name: _name, parentId: _parentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final verb = widget.confirmLabel == 'Create' ? 'create' : 'save';
    return NooteDialog(
      icon: widget.icon,
      title: widget.title,
      width: 380,
      autofocus: false,
      onSubmit: _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NooteField(
            controller: _controller,
            hint: widget.hintText,
            onSubmitted: (_) => _submit(),
          ),
          if (widget.tree case final tree?)
            _InsideSelector(
              tree: tree,
              parentId: _parentId,
              onChanged: (id) => setState(() => _parentId = id),
            ),
        ],
      ),
      hint: KeyHint([const Kbd('↵'), ' to $verb']),
      actions: [
        NooteButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        NooteButton.primary(
          widget.confirmLabel,
          onPressed: _name.isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

/// "Inside [Apple Notes / Pivotly ▾]": where a new folder goes.
class _InsideSelector extends StatelessWidget {
  const _InsideSelector({
    required this.tree,
    required this.parentId,
    required this.onChanged,
  });

  final FolderTree tree;
  final String? parentId;
  final ValueChanged<String?> onChanged;

  static const _topLevel = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final label = parentId == null ? 'Top level' : tree.pathOf(parentId!);
    final textStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12.5,
      color: theme.colorScheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(
            'Inside',
            style: textStyle.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: 'Where the folder goes',
              initialValue: parentId ?? _topLevel,
              onSelected: (id) => onChanged(id == _topLevel ? null : id),
              constraints: const BoxConstraints(minWidth: 220, maxHeight: 360),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _topLevel,
                  height: 36,
                  child: Text('Top level', style: textStyle),
                ),
                for (final (:folder, :depth) in tree.flatten())
                  if (!tree.isHiddenShared(folder.id))
                    PopupMenuItem(
                      value: folder.id,
                      height: 36,
                      child: Padding(
                        padding: EdgeInsets.only(left: depth * 14.0),
                        child: Text(
                          folder.name,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                      ),
                    ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more, size: 15, color: colors.textFaint),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
