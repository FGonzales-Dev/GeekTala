import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/tags_providers.dart';

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
      onTap: () => showDialog<void>(
        context: context,
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

class _TagPickerDialogState extends ConsumerState<_TagPickerDialog> {
  final _newTagController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _createAndAttach() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    final tagId = await ref.read(tagsRepositoryProvider).createTag(name);
    await ref.read(notesRepositoryProvider).addTag(widget.noteId, tagId);
    _newTagController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(noteByIdProvider(widget.noteId)).value;
    final allTags = ref.watch(allTagsProvider).value ?? const [];
    final selected = note?.tagIds.toSet() ?? const <String>{};

    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (allTags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No tags yet — create one below.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in allTags)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(tag.name),
                        value: selected.contains(tag.id),
                        onChanged: (checked) {
                          final repo = ref.read(notesRepositoryProvider);
                          if (checked ?? false) {
                            repo.addTag(widget.noteId, tag.id);
                          } else {
                            repo.removeTag(widget.noteId, tag.id);
                          }
                        },
                      ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'New tag name',
                    ),
                    onSubmitted: (_) => _createAndAttach(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _createAndAttach, child: const Text('Add')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
