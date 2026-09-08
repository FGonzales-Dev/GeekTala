import 'package:drift/drift.dart';

import '../models/title_style_run.dart';
import 'connection/connection.dart' as connection;
import 'daos/folders_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/tags_dao.dart';
import 'tables/folders_table.dart';
import 'tables/notes_table.dart';
import 'tables/notes_tags_table.dart';
import 'tables/tags_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [NotesTable, FoldersTable, TagsTable, NotesTagsTable],
  daos: [NotesDao, FoldersDao, TagsDao],
)
class AppDatabase extends _$AppDatabase {
  // connection.connect() returns a DatabaseConnection (SqliteAsyncDriftConnection
  // wrapping PowerSync — see connection_native.dart), not a bare
  // QueryExecutor. Passing it here still does the right thing: drift's
  // DatabaseConnectionUser constructor detects when the executor it's
  // given already *is* a DatabaseConnection and reuses its streamQueries
  // as-is rather than creating a separate one — required for Drift's
  // watch() streams to see updates PowerSync pulls down from sync, since
  // those arrive through that same connection, not through Drift's own
  // write path.
  AppDatabase() : _isPowerSyncManaged = true, super(connection.connect());

  /// For widget/unit tests — avoids `connection.connect()`'s
  /// `path_provider`/PowerSync/`WasmDatabase` platform-channel calls, which
  /// aren't available under `flutter test`. Pass `NativeDatabase.memory()`.
  /// Unlike the real constructor, this isn't PowerSync-managed — there's no
  /// separate process creating the tables, so `onCreate` below has to.
  AppDatabase.forTesting(super.executor) : _isPowerSyncManaged = false;

  final bool _isPowerSyncManaged;

  // PowerSync ISO-8601-encodes timestamps when syncing from Postgres —
  // this must match, or every DateTimeColumn read after a sync silently
  // corrupts (Drift's default is integer-epoch storage). See
  // lib/data/sync/powersync_schema.dart's doc comment.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  // schemaVersion/MigrationStrategy no longer own table creation for
  // notes/folders/tags/notesTags — those are PowerSync-managed views now
  // (see connection_native.dart), created and auto-migrated by PowerSync
  // itself from lib/data/sync/powersync_schema.dart. Calling m.createAll()
  // or m.addColumn() against them here would collide with views that
  // already exist by the time this runs (PowerSync initializes before
  // Drift's first query) — schema changes to those four tables go through
  // powersync_schema.dart, not this file, from here on. This still fires
  // exactly once per fresh local database file (Drift's own PRAGMA
  // user_version bookkeeping, independent of PowerSync's), which is all
  // that's needed to seed first-launch content.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          if (!_isPowerSyncManaged) {
            await m.createAll();
          }
          await _seed(this);
        },
      );
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
    batch.insertAll(db.foldersTable, [
      FoldersTableCompanion.insert(id: 'work', name: 'Work', updatedAt: now),
      FoldersTableCompanion.insert(
        id: 'engineering',
        name: 'Engineering',
        parentId: const Value('work'),
        updatedAt: now,
      ),
      FoldersTableCompanion.insert(
        id: 'product-specs',
        name: 'Product Specs',
        parentId: const Value('work'),
        updatedAt: now,
      ),
      FoldersTableCompanion.insert(
        id: 'personal',
        name: 'Personal',
        updatedAt: now,
      ),
      // 'personal' and 'shared' are permanent — FoldersRepository.
      // protectedFolderIds refuses to delete either.
      FoldersTableCompanion.insert(
        id: 'shared',
        name: 'Shared',
        updatedAt: now,
      ),
    ]);

    batch.insertAll(db.tagsTable, [
      TagsTableCompanion.insert(id: 'ideas', name: 'ideas'),
      TagsTableCompanion.insert(id: 'recipes', name: 'recipes'),
      TagsTableCompanion.insert(id: 'architecture', name: 'architecture'),
    ]);

    batch.insertAll(db.notesTable, [
      NotesTableCompanion.insert(
        id: 'sync-architecture',
        folderId: const Value('engineering'),
        title: const Value('Local-First Sync Architecture'),
        bodyJson: Value(
          _document([
            _heading('Overview'),
            _paragraph(
              'Every write hits the local SQLite database first — the UI '
              'never waits on a network call. PowerSync then pushes changes '
              'to Postgres once the device is back online, and pulls down '
              'changes made elsewhere.',
            ),
            ..._bulletList([
              'Drift for local storage (SQLite)',
              'PowerSync for offline-first sync',
              'Supabase for backend, auth, and storage',
            ]),
            _codeParagraph(
              'final note = await notesRepository.watchNote(noteId);\n'
              'final status = syncStatusProvider.value;',
            ),
            _table(
              ['Layer', 'Tool'],
              [
                ['Local DB', 'Drift'],
                ['Sync', 'PowerSync'],
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

    batch.insertAll(db.notesTagsTable, [
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
