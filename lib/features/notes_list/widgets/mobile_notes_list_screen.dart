import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/avatar_stack.dart';
import '../../../core/widgets/search_field.dart';
import '../../../data/models/folder.dart';
import '../../../data/models/note.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/search_provider.dart';
import '../../../data/providers/tags_providers.dart';
import '../../note_editor/markdown_io.dart';
import 'mobile_note_card.dart';

enum _NotesFilter { all, work, personal, shared }

/// `.m-topbar` + `.m-search` + `.m-folder-chips` + `.m-list` — the mobile
/// Notes tab content. The FAB and bottom tab bar live in `MobileShell`.
class MobileNotesListScreen extends ConsumerStatefulWidget {
  const MobileNotesListScreen({super.key});

  @override
  ConsumerState<MobileNotesListScreen> createState() =>
      _MobileNotesListScreenState();
}

class _MobileNotesListScreenState
    extends ConsumerState<MobileNotesListScreen> {
  var _filter = _NotesFilter.all;

  bool _matches(Note note, List<Folder> folders) {
    final folder = folders.where((f) => f.id == note.folderId).firstOrNull;
    return switch (_filter) {
      _NotesFilter.all => true,
      _NotesFilter.work =>
        note.folderId == 'work' || folder?.parentId == 'work',
      _NotesFilter.personal => note.folderId == 'personal',
      _NotesFilter.shared => note.collaboratorInitials.isNotEmpty,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = ref.watch(allFoldersProvider).value ?? const [];
    final allNotes = ref.watch(allNotesProvider).value ?? const [];
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final tagsById = {for (final t in tags) t.id: t};
    final query = ref.watch(searchQueryProvider);
    final notes = filterNotesByQuery(
      allNotes.where((n) => _matches(n, folders)).toList(),
      query,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 34, 18, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notes',
                style: AppTextStyles.mobileScreenTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Row(
                children: [
                  InkWell(
                    onTap: () => importMarkdownNote(context, ref),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.file_upload_outlined,
                        size: 18,
                        color: context.nooteColors.textFaint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const AvatarStack(initials: ['RS']),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
          child: const SearchField(hint: 'Search notes'),
        ),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              for (final filter in _NotesFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _FilterChip(
                    label: switch (filter) {
                      _NotesFilter.all => 'All',
                      _NotesFilter.work => 'Work',
                      _NotesFilter.personal => 'Personal',
                      _NotesFilter.shared => 'Shared',
                    },
                    selected: filter == _filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: notes.isEmpty && query.trim().isNotEmpty
              ? Center(
                  child: Text(
                    'No notes match "$query"',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: context.nooteColors.textFaint,
                    ),
                  ),
                )
              : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final note in notes)
                MobileNoteCard(
                  note: note,
                  tagsById: tagsById,
                  onTap: () => context.go('/notes/${note.id}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : colors.surfaceAlt,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.mobileChip.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
