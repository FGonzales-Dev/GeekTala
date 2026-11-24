import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/search_field.dart';
import '../../core/widgets/sync_status_indicator.dart';
import '../../data/models/note.dart';
import '../../data/models/note_search.dart';
import '../../data/providers/folders_providers.dart';
import '../../data/providers/notes_providers.dart';
import '../../data/providers/search_provider.dart';
import '../../data/providers/tags_providers.dart';
import '../notes_list/widgets/mobile_note_card.dart';
import '../shell/widgets/mobile_nav_bar.dart';
import '../tags/tag_actions.dart';
import 'folder_actions.dart';
import 'widgets/folder_disclosure.dart';
import 'widgets/folder_tree_node.dart';

/// Phones' home screen, like Apple Notes: All Notes, the folder tree (the
/// arrow shows or hides subfolders, the row opens the folder), tags and
/// Recently Deleted. The gear opens Settings; New folder and New note sit
/// in the bottom bar. Typing in the search box searches every note.
class MobileFoldersHome extends ConsumerWidget {
  const MobileFoldersHome({super.key});

  static final _search = screenSearchQueryProvider('home');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_search);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileNavBar(
              actions: [
                MobileBarButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
            const MobileLargeTitle('Folders'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SearchField(
                hint: 'Search all notes',
                query: _search,
                large: true,
              ),
            ),
            Expanded(
              child: query.trim().isEmpty
                  ? const _FolderList()
                  : _SearchResults(query: query),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MobileBottomBar(
        leading: MobileBarButton(
          icon: Icons.create_new_folder_outlined,
          tooltip: 'New folder',
          onPressed: () => createFolderFlow(context, ref),
        ),
        center: const SyncStatusIndicator(),
        trailing: MobileBarButton(
          icon: Icons.edit_square,
          tooltip: 'New note',
          onPressed: () => createNoteFlow(
            context,
            ref,
            folderId: 'personal',
            from: 'Folders',
          ),
        ),
      ),
    );
  }
}

/// Creates a note in [folderId] (with [tagId] on it, if given) and opens
/// it; its Back button says [from].
Future<void> createNoteFlow(
  BuildContext context,
  WidgetRef ref, {
  required String folderId,
  String? tagId,
  required String from,
}) async {
  final notes = ref.read(notesRepositoryProvider);
  final id = await notes.createNote(folderId: folderId);
  if (tagId != null) await notes.addTag(id, tagId);
  if (context.mounted) openNote(context, id, from: from);
}

class _FolderList extends ConsumerWidget {
  const _FolderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.nooteColors;
    final tree = ref.watch(folderTreeProvider);
    final noteCounts = ref.watch(noteCountsByFolderProvider).value ?? const {};
    final total = ref.watch(allNotesProvider).value?.length;
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final deleted = ref.watch(deletedNotesProvider).value?.length ?? 0;
    final roots = [
      for (final folder in tree.roots)
        if (!tree.isHiddenShared(
          folder.id,
          noteCount: noteCounts[folder.id] ?? 0,
        ))
          folder,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      children: [
        MobileGroup(
          children: [
            MobileRow(
              icon: Icons.notes,
              label: 'All Notes',
              count: total,
              onTap: () => openFolder(context, 'all', from: 'Folders'),
            ),
          ],
        ),
        const MobileGroupLabel('Folders'),
        MobileGroup(
          dividers: false,
          children: [
            for (final folder in roots)
              FolderTreeNode(
                key: ValueKey(folder.id),
                folder: folder,
                tree: tree,
                depth: 0,
                noteCounts: noteCounts,
                selectedFolderId: null,
                onSelect: (id) => openFolder(context, id, from: 'Folders'),
                rowBuilder:
                    (
                      context, {
                      required folder,
                      required depth,
                      required selected,
                      required noteCount,
                      required onTap,
                      expanded,
                      onToggle,
                    }) => MobileRow(
                      topDivider: folder.id != roots.first.id,
                      // The row's whole left strip toggles, not just the
                      // small arrow (see MobileRow.onLeadingTap).
                      leading: FolderDisclosure(
                        expanded: expanded,
                        onToggle: null,
                        size: 18,
                        color: colors.textFaint,
                      ),
                      onLeadingTap: onToggle,
                      icon: Icons.folder_outlined,
                      label: folder.name,
                      count: noteCount,
                      depth: depth,
                      onTap: onTap,
                    ),
              ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const MobileGroupLabel('Tags'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final tag in tags)
                  // Long-press: Rename, Delete.
                  GestureDetector(
                    onLongPressStart: (details) => showTagActionsMenu(
                      context,
                      ref,
                      tag,
                      details.globalPosition,
                    ),
                    child: ActionChip(
                      label: Text('#${tag.name}'),
                      onPressed: () =>
                          openTag(context, tag.id, from: 'Folders'),
                      labelStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: theme.colorScheme.outline),
                      shape: const StadiumBorder(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        MobileGroup(
          children: [
            MobileRow(
              icon: Icons.delete_outline,
              label: 'Recently Deleted',
              count: deleted,
              onTap: () => context.push('/trash'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Every note matching the home screen's search box.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(allTagsProvider).value ?? const [];
    final tagsById = {for (final t in tags) t.id: t};
    final all = [...?ref.watch(allNotesProvider).value]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final results = searchNotes(all, query, tagsById: tagsById);
    return MobileNoteList(
      notes: results,
      grouped: false,
      searchTerms: highlightTerms(query),
      emptyText: 'No notes match “${query.trim()}”',
      backLabel: 'Folders',
      header: '${results.length} ${results.length == 1 ? 'note' : 'notes'}',
    );
  }
}

/// Notes in rounded groups — by date ("Today", "Previous 7 Days", …) when
/// [grouped] — each opening its note. [before] goes above them, e.g. a
/// folder's subfolders.
class MobileNoteList extends StatelessWidget {
  const MobileNoteList({
    super.key,
    required this.notes,
    this.grouped = true,
    this.searchTerms = const [],
    this.before = const [],
    this.emptyText = 'No notes',
    this.header,
    this.backLabel,
  });

  final List<Note> notes;
  final bool grouped;
  final List<String> searchTerms;
  final List<Widget> before;
  final String emptyText;

  /// A label above an ungrouped list, e.g. "12 notes".
  final String? header;

  /// What the note screen's Back says (the screen this list is on).
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooteColors;
    final now = DateTime.now();
    final groups = <String, List<Note>>{};
    for (final note in notes) {
      final label = grouped ? noteDateGroup(note.updatedAt, now) : '';
      (groups[label] ??= []).add(note);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      children: [
        ...before,
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                emptyText,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: colors.textFaint,
                ),
              ),
            ),
          ),
        for (final MapEntry(key: label, value: list) in groups.entries) ...[
          if (label.isNotEmpty)
            MobileGroupLabel(label)
          else if (header != null)
            MobileGroupLabel(header!)
          else
            const SizedBox(height: 4),
          MobileGroup(
            children: [
              for (final note in list)
                MobileNoteCard(
                  key: ValueKey(note.id),
                  note: note,
                  searchTerms: searchTerms,
                  onTap: () => openNote(context, note.id, from: backLabel),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
