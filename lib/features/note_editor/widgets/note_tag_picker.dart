import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/noote_dialog.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/models/tag.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/tags_providers.dart';
import '../../tags/tag_actions.dart';

/// The open note's tags (removable) plus a button to attach more — sits
/// under the title in `NoteEditorBody`.
class NoteTagPicker extends ConsumerWidget {
  const NoteTagPicker({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteByIdProvider(noteId)).value;
    final allTags = ref.watch(allTagsProvider).value ?? const [];
    if (note == null) return const SizedBox.shrink();

    final tagsById = {for (final t in allTags) t.id: t};
    final noteTags = [
      for (final id in note.tagIds)
        if (tagsById[id] != null) tagsById[id]!,
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in noteTags)
          TagChip(
            label: tag.name,
            onRemove: () =>
                ref.read(notesRepositoryProvider).removeTag(noteId, tag.id),
          ),
        _AddTagButton(noteId: noteId),
      ],
    );
  }
}

class _AddTagButton extends StatelessWidget {
  const _AddTagButton({required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooteColors;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showNooteDialog<void>(
        context,
        builder: (_) => _TagPickerDialog(noteId: noteId),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderSoft),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 11, color: colors.textFaint),
            const SizedBox(width: 3),
            Text(
              'Tag',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: colors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPickerDialog extends ConsumerStatefulWidget {
  const _TagPickerDialog({required this.noteId});

  final String noteId;

  @override
  ConsumerState<_TagPickerDialog> createState() => _TagPickerDialogState();
}

/// One field to search the tags or create a new one; tick a tag to put it
/// on the note. Enter creates the typed tag (or ticks the one with that
/// name); with nothing typed it closes.
class _TagPickerDialogState extends ConsumerState<_TagPickerDialog> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The typed name, without a leading `#`.
  String get _typed {
    final text = _query.text.trim();
    return (text.startsWith('#') ? text.substring(1) : text).trim();
  }

  void _toggle(Tag tag, bool on) {
    final repo = ref.read(notesRepositoryProvider);
    if (on) {
      repo.addTag(widget.noteId, tag.id);
    } else {
      repo.removeTag(widget.noteId, tag.id);
    }
  }

  Future<void> _createAndAttach(String name) async {
    final tagId = await ref.read(tagsRepositoryProvider).createTag(name);
    await ref.read(notesRepositoryProvider).addTag(widget.noteId, tagId);
    _query.clear();
  }

  void _submit(List<Tag> allTags, Set<String> selected) {
    final name = _typed;
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final exact = allTags.where(
      (t) => t.name.toLowerCase() == name.toLowerCase(),
    );
    if (exact.isEmpty) {
      _createAndAttach(name);
    } else {
      if (!selected.contains(exact.first.id)) _toggle(exact.first, true);
      _query.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(noteByIdProvider(widget.noteId)).value;
    final allTags = ref.watch(allTagsProvider).value ?? const <Tag>[];
    final selected = note?.tagIds.toSet() ?? const <String>{};
    final name = _typed;
    final q = name.toLowerCase();
    final shown = [
      for (final tag in allTags)
        if (q.isEmpty || tag.name.toLowerCase().contains(q)) tag,
    ];
    final canCreate =
        name.isNotEmpty && !allTags.any((t) => t.name.toLowerCase() == q);
    final title = note?.title.trim() ?? '';

    return NooteDialog(
      icon: Icons.sell_outlined,
      title: 'Tags',
      subtitle: title.isEmpty ? null : 'For “$title”',
      width: 380,
      autofocus: false,
      onSubmit: () => _submit(allTags, selected),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NooteField(
            controller: _query,
            hint: allTags.isEmpty ? 'Name a new tag' : 'Search or create a tag',
            keepFocusOnSubmit: true,
            onSubmitted: (_) => _submit(allTags, selected),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final tag in shown)
                  // Right-click / long-press: Rename, Delete — the
                  // only place to manage tags on mobile.
                  GestureDetector(
                    onSecondaryTapDown: (details) => showTagActionsMenu(
                      context,
                      ref,
                      tag,
                      details.globalPosition,
                    ),
                    onLongPressStart: (details) => showTagActionsMenu(
                      context,
                      ref,
                      tag,
                      details.globalPosition,
                    ),
                    child: _TagRow(
                      name: tag.name,
                      checked: selected.contains(tag.id),
                      onTap: () => _toggle(tag, !selected.contains(tag.id)),
                    ),
                  ),
                if (canCreate)
                  _TagRow(
                    name: 'Create “$name”',
                    create: true,
                    onTap: () => _createAndAttach(name),
                  ),
                if (shown.isEmpty && !canCreate)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No tags yet. Type a name to create one.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        color: context.nooteColors.textFaint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      hint: const KeyHint(['Type to search or create']),
      actions: [
        NooteButton.primary(
          'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.name,
    this.checked = false,
    this.create = false,
    required this.onTap,
  });

  final String name;
  final bool checked;

  /// The "Create “name”" row: a plus instead of a checkbox.
  final bool create;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final textStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      color: create
          ? theme.colorScheme.onSurfaceVariant
          : theme.colorScheme.onSurface,
    );
    return Semantics(
      checked: create ? null : checked,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              if (create)
                Icon(Icons.add, size: 16, color: colors.textFaint)
              else
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: checked ? theme.colorScheme.onSurface : null,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: checked
                          ? theme.colorScheme.onSurface
                          : colors.textFaint,
                      width: 1.5,
                    ),
                  ),
                  child: checked
                      ? Icon(
                          Icons.check,
                          size: 12,
                          color: theme.scaffoldBackgroundColor,
                        )
                      : null,
                ),
              const SizedBox(width: 9),
              if (!create)
                Text('#', style: textStyle.copyWith(color: colors.textFaint)),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
