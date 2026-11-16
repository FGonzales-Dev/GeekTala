import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/navigation.dart';
import '../../../core/widgets/search_field.dart';
import '../../../data/models/folder.dart';
import '../../../data/models/note.dart';
import '../../../data/models/note_search.dart';
import '../../../data/models/tag.dart';
import '../../../data/providers/folders_providers.dart';
import '../../../data/providers/notes_providers.dart';
import '../../../data/providers/search_provider.dart';
import '../../../data/providers/tags_providers.dart';
import '../../folders/mobile_folders_home.dart';
import '../../folders/widgets/folder_tree_node.dart';
import '../../note_editor/markdown_io.dart';
import '../../shell/widgets/mobile_nav_bar.dart';
import '../../tags/tag_actions.dart';

/// What a [MobileFolderScreen] lists.
sealed class NotesScope {
  const NotesScope();
}

/// Every note.
class AllNotesScope extends NotesScope {
  const AllNotesScope();
}

class FolderScope extends NotesScope {
  const FolderScope(this.folderId);

  final String folderId;
}

class TagScope extends NotesScope {
  const TagScope(this.tagId);

  final String tagId;
}

/// A phone screen of notes — a folder's, a tag's, or All Notes: Back,
/// a large title and count, a search box for just these notes, the
/// folder's subfolders, then the notes grouped by date. ••• has the
/// folder's actions; New note (bottom right) goes into this folder.
class MobileFolderScreen extends ConsumerWidget {
  const MobileFolderScreen({super.key, required this.scope, this.backLabel});

  final NotesScope scope;

  /// What Back says; "Folders" by default.
  final String? backLabel;

  String get _searchKey => switch (scope) {
    AllNotesScope() => 'all',
    FolderScope(:final folderId) => 'folder:$folderId',
    TagScope(:final tagId) => 'tag:$tagId',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = screenSearchQueryProvider(_searchKey);
    final query = ref.watch(search);
    final tree = ref.watch(folderTreeProvider);
    final noteCounts = ref.watch(noteCountsByFolderProvider).value ?? const {};
    final tags = ref.watch(allTagsProvider).value ?? const <Tag>[];
    final tagsById = {for (final t in tags) t.id: t};

    final Folder? folder;
    final Tag? tag;
    final List<Note>? loaded;
    switch (scope) {
      case AllNotesScope():
        folder = null;
        tag = null;
        loaded = ref.watch(allNotesProvider).value;
      case FolderScope(:final folderId):
        folder = tree[folderId];
        tag = null;
        loaded = ref.watch(notesInFolderProvider(folderId)).value;
      case TagScope(:final tagId):
        folder = null;
        tag = tagsById[tagId];
        loaded = ref
            .watch(allNotesProvider)
            .value
            ?.where((n) => n.tagIds.contains(tagId))
            .toList();
    }

    // Deleted while open (here or on another device).
    final gone =
        (scope is FolderScope && folder == null && tree.roots.isNotEmpty) ||
        (scope is TagScope && tag == null && tags.isNotEmpty);
    final title = switch (scope) {
      AllNotesScope() => 'All Notes',
      FolderScope() => folder?.name ?? '',
      TagScope() => tag == null ? '' : '#${tag.name}',
    };
    final notes = [...?loaded]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final shown = searchNotes(notes, query, tagsById: tagsById);
    final searching = query.trim().isNotEmpty;
    final count = '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}';
    final subfolders = [
      if (folder != null && !searching)
        for (final child in tree.childrenOf(folder.id))
          if (!tree.isHiddenShared(
            child.id,
            noteCount: noteCounts[child.id] ?? 0,
          ))
            child,
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileNavBar(
              backLabel: backLabel ?? 'Folders',
              actions: [
                if (!gone)
                  Builder(
                    builder: (context) => MobileBarButton(
                      icon: Icons.more_horiz,
                      tooltip: 'More',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onPressed: () =>
                          _showMoreMenu(context, ref, folder: folder, tag: tag),
                    ),
                  ),
              ],
            ),
            MobileLargeTitle(
              gone ? 'Not found' : title,
              subtitle: gone || loaded == null ? null : count,
            ),
            if (gone)
              const Expanded(child: Center(child: Text('This was deleted.')))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchField(
                  hint: 'Search ${title.isEmpty ? 'notes' : title}',
                  query: search,
                  large: true,
                ),
              ),
              Expanded(
                child: MobileNoteList(
                  notes: shown,
                  grouped: !searching,
                  searchTerms: highlightTerms(query),
                  backLabel: title,
                  header: searching
                      ? '${shown.length} '
                            '${shown.length == 1 ? 'result' : 'results'}'
                      : null,
                  emptyText: searching
                      ? 'No notes match “${query.trim()}”'
                      : 'No notes',
                  before: [
                    if (subfolders.isNotEmpty)
                      MobileGroup(
                        children: [
                          for (final child in subfolders)
                            MobileRow(
                              icon: Icons.folder_outlined,
                              label: child.name,
                              count: noteCounts[child.id] ?? 0,
                              onTap: () =>
                                  openFolder(context, child.id, from: title),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: gone
          ? null
          : MobileBottomBar(
              center: Text(
                loaded == null
                    ? ''
                    : '${notes.length} ${notes.length == 1 ? 'Note' : 'Notes'}',
              ),
              trailing: MobileBarButton(
                icon: Icons.edit_square,
                tooltip: 'New note',
                onPressed: () => createNoteFlow(
                  context,
                  ref,
                  folderId: folder?.id ?? 'personal',
                  tagId: tag?.id,
                  from: title,
                ),
              ),
            ),
    );
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    WidgetRef ref, {
    required Folder? folder,
    required Tag? tag,
  }) async {
    final box = context.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(box.size.bottomRight(Offset.zero));
    if (tag != null) {
      await showTagActionsMenu(context, ref, tag, position);
      return;
    }
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (folder != null) ...[
          ...folderActionItems(folder),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: 'import',
          child: Text('Import Markdown file…'),
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'import') {
      await importMarkdownNote(
        context,
        ref,
        folderId: folder?.id ?? 'personal',
      );
      return;
    }
    if (folder == null) return;
    final deleted = await runFolderAction(context, ref, folder, action);
    if (deleted && context.mounted) goBack(context);
  }
}
