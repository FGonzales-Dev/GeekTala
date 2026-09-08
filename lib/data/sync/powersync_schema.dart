import 'package:powersync/powersync.dart';

/// PowerSync's own schema declaration — separate from (but structurally
/// mirroring) the Drift tables in `../database/tables/`. This is what
/// PowerSync uses to create/manage the locally-synced views; Drift then
/// reads/writes those same views via `SqliteAsyncDriftConnection` (see
/// `../database/connection/connection_native.dart`), so app code never
/// touches this schema directly.
///
/// [Table.name] must match the Postgres table name (it's what PowerSync's
/// sync rules and the `powersync` publication key off — see
/// `supabase/migrations/`), while `viewName` is set to Drift's actual SQL
/// table name (`<TableClass>` → `snake_case_table`, unabridged — Drift
/// does *not* strip a trailing "Table" from the class name) so Drift's
/// generated queries work against these views unmodified.
///
/// Timestamps are declared as TEXT, not INTEGER: Drift is configured with
/// `storeDateTimeAsText: true` (see `connection_native.dart`) specifically
/// so its ISO-8601 representation matches what arrives from Postgres
/// through the sync protocol — mismatching these would silently corrupt
/// every `DateTimeColumn` read after a sync.
final powerSyncSchema = Schema([
  Table(
    'notes',
    [
      Column.text('owner_id'),
      Column.text('folder_id'),
      Column.text('title'),
      Column.text('title_style_json'),
      Column.text('body_json'),
      Column.text('created_at'),
      Column.text('updated_at'),
      Column.integer('is_deleted'),
      Column.text('deleted_at'),
    ],
    viewName: 'notes_table',
    indexes: [
      Index.ascending('owner_id_idx', ['owner_id']),
      Index.ascending('folder_id_idx', ['folder_id']),
    ],
  ),
  Table(
    'folders',
    [
      Column.text('owner_id'),
      Column.text('name'),
      Column.text('parent_id'),
      Column.text('updated_at'),
      Column.integer('is_deleted'),
    ],
    viewName: 'folders_table',
    indexes: [Index.ascending('owner_id_idx', ['owner_id'])],
  ),
  Table(
    'tags',
    [Column.text('owner_id'), Column.text('name')],
    viewName: 'tags_table',
    indexes: [Index.ascending('owner_id_idx', ['owner_id'])],
  ),
  Table(
    'notes_tags',
    [
      Column.text('note_id'),
      Column.text('tag_id'),
      Column.text('owner_id'),
    ],
    viewName: 'notes_tags_table',
  ),
]);
