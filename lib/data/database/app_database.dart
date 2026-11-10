import 'package:drift/drift.dart';

import '../models/title_style_run.dart';
import 'connection/connection.dart' as connection;
import 'daos/attachments_dao.dart';
import 'daos/folders_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/sync_dao.dart';
import 'daos/tags_dao.dart';
import 'tables/attachments_table.dart';
import 'tables/folders_table.dart';
import 'tables/notes_table.dart';
import 'tables/notes_tags_table.dart';
import 'tables/tags_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    NotesTable,
    FoldersTable,
    TagsTable,
    NotesTagsTable,
    AttachmentsTable,
  ],
  daos: [NotesDao, FoldersDao, TagsDao, SyncDao, AttachmentsDao],
  include: {'sync.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connection.connect());

  /// For widget/unit tests — avoids `connection.connect()`'s
  /// `path_provider`/`WasmDatabase` platform-channel calls, which aren't
  /// available under `flutter test`. Pass `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.executor);

  // ISO-8601 text rather than drift's default epoch integers: readable in
  // a SQLite browser and the same shape Postgres timestamps arrive in.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // Creates the tables, sync_outbox/sync_state and the outbox
          // triggers (sync.drift) — triggers first, so the seed below is
          // queued for upload like any other local change.
          await m.createAll();
          await seedDemoContent();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Folder order, for drag-to-reorder. Existing folders keep the
            // order they were shown in (creation order within each parent).
            // The update goes through the outbox triggers, so the new
            // order is uploaded with the next sync.
            await m.addColumn(foldersTable, foldersTable.sortOrder);
            await customStatement(
              'UPDATE folders_table SET sort_order = ('
              'SELECT COUNT(*) FROM folders_table AS earlier '
              'WHERE earlier.parent_id IS folders_table.parent_id '
              'AND earlier.rowid < folders_table.rowid)',
            );
          }
          if (from < 3) {
            // Attachments (images in notes).
            await m.createTable(attachmentsTable);
          }
        },
      );

  /// First-launch content. Also used by `SyncService` when an account with
  /// nothing on the server signs in on a device that held another
  /// account's notes. Rows that already exist (e.g. the Personal/Shared
  /// folders) are left as they are.
  Future<void> seedDemoContent() => _seed(this);
}

// ---- appflowy_editor document JSON builders (seed data only) ----
// Shape verified against the installed appflowy_editor package's own
// example/assets/example.json and Document.fromJson/toJson source —
// see the plan for Build Order step 3.

Map<String, dynamic> _document(List<Map<String, dynamic>> children) => {
      'document': {'type': 'page', 'children': children},
    };

Map<String, dynamic> _heading(String text, {int level = 2}) => {
      'type': 'heading',
      'data': {
        'level': level,
        'delta': [
          {'insert': text},
        ],
      },
    };

Map<String, dynamic> _paragraph(String text) => {
      'type': 'paragraph',
      'data': {
        'delta': text.isEmpty
            ? <Object>[]
            : [
                {'insert': text},
              ],
      },
    };

/// Temporary stand-in for a real code block (Build Order step 4 — no
/// plugin exists for appflowy_editor 6.x, see noote-plan.md §2) — a
/// paragraph using the inline `code` delta attribute (monospace +
/// background), a real supported style, not a placeholder widget.
Map<String, dynamic> _codeParagraph(String code) => {
      'type': 'paragraph',
      'data': {
        'delta': [
          {
            'insert': code,
            'attributes': {'code': true},
          },
        ],
      },
    };

List<Map<String, dynamic>> _bulletList(List<String> items) => [
      for (final item in items)
        {
          'type': 'bulleted_list',
          'data': {
            'delta': [
              {'insert': item},
            ],
          },
        },
    ];

Map<String, dynamic> _table(List<String> headers, List<List<String>> rows) {
  final allRows = [headers, ...rows];
  final cells = <Map<String, dynamic>>[];
  for (var row = 0; row < allRows.length; row++) {
    for (var col = 0; col < headers.length; col++) {
      cells.add({
        'type': 'table/cell',
        'children': [_paragraph(allRows[row][col])],
        'data': {
          'colPosition': col,
          'rowPosition': row,
          'height': 40.0,
          'width': 200.0,
        },
      });
    }
  }
  return {
    'type': 'table',
    'children': cells,
    'data': {
      'colsLen': headers.length,
      'rowsLen': allRows.length,
      'colDefaultWidth': 200.0,
      'rowDefaultHeight': 40.0,
      'colMinimumWidth': 40.0,
      'colsHeight': 40.0 * allRows.length,
    },
  };
}

/// First-launch content — identical in substance to what the earlier
/// UI-shell pass's `MockData` (now removed) held, so the seeded app looks
/// the same as what was already screenshot-verified, but as real persisted
/// rows using appflowy_editor's own document format (not a custom block
/// model). The image block from that original mock content is dropped
/// here — see plan for Build Order step 3 (real attachments are step 5).
Future<void> _seed(AppDatabase db) async {
  final now = DateTime(2026, 8, 19, 14, 30);

  await db.batch((batch) {
    const ignore = InsertMode.insertOrIgnore;
    batch.insertAll(db.foldersTable, mode: ignore, [
      FoldersTableCompanion.insert(
        id: 'work',
        name: 'Work',
        updatedAt: now,
        sortOrder: const Value(0),
      ),
      FoldersTableCompanion.insert(
        id: 'engineering',
        name: 'Engineering',
        parentId: const Value('work'),
        updatedAt: now,
        sortOrder: const Value(0),
      ),
      FoldersTableCompanion.insert(
        id: 'product-specs',
        name: 'Product Specs',
        parentId: const Value('work'),
        updatedAt: now,
        sortOrder: const Value(1),
      ),
      FoldersTableCompanion.insert(
        id: 'personal',
        name: 'Personal',
        updatedAt: now,
        sortOrder: const Value(1),
      ),
      // 'personal' and 'shared' are permanent — see protectedFolderIds
      // (models/folder.dart).
      FoldersTableCompanion.insert(
        id: 'shared',
        name: 'Shared',
        updatedAt: now,
        sortOrder: const Value(2),
      ),
    ]);

    batch.insertAll(db.tagsTable, mode: ignore, [
      TagsTableCompanion.insert(id: 'ideas', name: 'ideas'),
      TagsTableCompanion.insert(id: 'recipes', name: 'recipes'),
      TagsTableCompanion.insert(id: 'architecture', name: 'architecture'),
    ]);

    batch.insertAll(db.notesTable, mode: ignore, [
      NotesTableCompanion.insert(
        id: 'sync-architecture',
        folderId: const Value('engineering'),
        title: const Value('Local-First Sync Architecture'),
        bodyJson: Value(
          _document([
            _heading('Overview'),
            _paragraph(
              'Every write hits the local SQLite database first — the UI '
              'never waits on a network call. Every change is queued in a '
              'local outbox; Upload sends the queue to Supabase, and Download '
              'replaces the local copy with what is on the server.',
            ),
            ..._bulletList([
              'Drift for local storage (SQLite)',
              'A local outbox of changes for upload',
              'Supabase for backend, auth, and storage',
            ]),
            _codeParagraph(
              'final note = await notesRepository.watchNote(noteId);\n'
              'await ref.read(syncControllerProvider.notifier).upload();',
            ),
            _table(
              ['Layer', 'Tool'],
              [
                ['Local DB', 'Drift'],
                ['Sync', 'Outbox + push_changes RPC'],
                ['Backend', 'Supabase'],
              ],
            ),
          ]),
        ),
        createdAt: now.subtract(const Duration(minutes: 2)),
        updatedAt: now.subtract(const Duration(minutes: 2)),
      ),
      NotesTableCompanion.insert(
        id: 'api-auth-flow',
        folderId: const Value('engineering'),
        title: const Value('API Auth Flow'),
        bodyJson: Value(
          _document([
            _heading('Overview'),
            _paragraph(
              'PKCE flow for web, native deep link for mobile/desktop, both '
              'via Supabase Auth.',
            ),
          ]),
        ),
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      ),
      NotesTableCompanion.insert(
        id: 'sprint-retro-aug-18',
        folderId: const Value('engineering'),
        title: const Value('Sprint Retro — Aug 18'),
        bodyJson: Value(
          _document([
            _paragraph(
              "What went well: shipped the offline queue. What didn't: table "
              'merge conflicts on edit.',
            ),
          ]),
        ),
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      NotesTableCompanion.insert(
        id: 'attachment-upload-queue',
        folderId: const Value('engineering'),
        title: const Value('Attachment Upload Queue'),
        bodyJson: Value(
          _document([
            _paragraph(
              'Local-first cache, background upload, thumbnail generation on '
              'device.',
            ),
          ]),
        ),
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      NotesTableCompanion.insert(
        id: 'grocery-list',
        folderId: const Value('personal'),
        title: const Value('Grocery List'),
        bodyJson: Value(
          _document([
            ..._bulletList([
              'Oat milk',
              'Coffee beans',
              'Basil',
              'Parmesan',
              'Eggs',
            ]),
          ]),
        ),
        createdAt: DateTime(now.year, now.month, now.day - 1),
        updatedAt: DateTime(now.year, now.month, now.day - 1),
      ),
      NotesTableCompanion.insert(
        id: 'book-notes-deep-work',
        folderId: const Value('personal'),
        title: const Value('Book notes: Deep Work'),
        bodyJson: Value(
          _document([
            _paragraph(
              'Chapter 2 — the value of sustained, undistracted focus over '
              'shallow busywork.',
            ),
          ]),
        ),
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
    ]);

    batch.insertAll(db.notesTagsTable, mode: ignore, [
      NotesTagsTableCompanion.insert(
        id: 'sync-architecture::architecture',
        noteId: 'sync-architecture',
        tagId: 'architecture',
      ),
      NotesTagsTableCompanion.insert(
        id: 'book-notes-deep-work::ideas',
        noteId: 'book-notes-deep-work',
        tagId: 'ideas',
      ),
    ]);
  });
}
