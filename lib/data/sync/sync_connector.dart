import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// PowerSync's other half — see `supabase/migrations/` for the stored
/// procedures this calls and noote-plan.md §4/§6 for why it's RPC-only,
/// never a raw table write.
class SupabaseSyncConnector extends PowerSyncBackendConnector {
  SupabaseSyncConnector(this._client, {required this.powerSyncUrl});

  final supabase.SupabaseClient _client;
  final String powerSyncUrl;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // supabase_flutter auto-refreshes the session's access token in the
    // background, so reading it here is enough — no manual refresh call
    // needed.
    final session = _client.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: powerSyncUrl,
      token: session.accessToken,
      userId: session.user.id,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    for (final entry in transaction.crud) {
      await _uploadEntry(database, entry);
    }
    await transaction.complete();
  }

  /// PATCH entries only carry the columns that *changed*, not the full
  /// row — but the stored procedures are full upserts (see
  /// `upsert_note`/`upsert_folder` in supabase/migrations/), so blindly
  /// forwarding a PATCH's partial `opData` would null out every column it
  /// didn't happen to touch. Re-reading the row's current full state from
  /// the local view sidesteps that entirely, for both PUT and PATCH.
  Future<void> _uploadEntry(PowerSyncDatabase database, CrudEntry entry) async {
    switch (entry.table) {
      case 'notes':
        if (entry.op == UpdateType.delete) {
          await _client.rpc('delete_note', params: {'p_id': entry.id});
          return;
        }
        final row = await _currentRow(database, 'notes_table', entry.id);
        if (row == null) return;
        await _client.rpc(
          'upsert_note',
          params: {
            'p_id': entry.id,
            'p_folder_id': row['folder_id'],
            'p_title': row['title'] as String? ?? '',
            'p_title_style_json': jsonDecode(
              row['title_style_json'] as String? ?? '[]',
            ),
            'p_body_json': jsonDecode(row['body_json'] as String? ?? '{}'),
            'p_created_at': row['created_at'],
            'p_updated_at': row['updated_at'],
          },
        );
      case 'folders':
        if (entry.op == UpdateType.delete) {
          await _client.rpc('delete_folder', params: {'p_id': entry.id});
          return;
        }
        final row = await _currentRow(database, 'folders_table', entry.id);
        if (row == null) return;
        await _client.rpc(
          'upsert_folder',
          params: {
            'p_id': entry.id,
            'p_name': row['name'] as String? ?? '',
            'p_parent_id': row['parent_id'],
            'p_updated_at': row['updated_at'],
          },
        );
      case 'tags':
        if (entry.op == UpdateType.delete) {
          // No delete_tag procedure exists yet — tags are only ever
          // created today (see TagsRepository), never removed.
          return;
        }
        final row = await _currentRow(database, 'tags_table', entry.id);
        if (row == null) return;
        await _client.rpc(
          'upsert_tag',
          params: {'p_id': entry.id, 'p_name': row['name'] as String? ?? ''},
        );
      case 'notes_tags':
        // id is always `'$noteId::$tagId'` (see NotesTagsTable's doc
        // comment) — deriving from it works for deletes too, where
        // opData is null.
        final parts = entry.id.split('::');
        if (parts.length != 2) return;
        final params = {'p_note_id': parts[0], 'p_tag_id': parts[1]};
        if (entry.op == UpdateType.delete) {
          await _client.rpc('detach_tag', params: params);
        } else {
          await _client.rpc('attach_tag', params: params);
        }
    }
  }

  Future<Map<String, dynamic>?> _currentRow(
    PowerSyncDatabase database,
    String viewName,
    String id,
  ) async {
    final rows = await database.getAll(
      'SELECT * FROM $viewName WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }
}
