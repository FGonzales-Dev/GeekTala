import 'package:supabase_flutter/supabase_flutter.dart';

/// The server side of sync, behind an interface so `SyncService` can be
/// tested without a network.
abstract interface class SyncRemote {
  /// Applies [changes] in one transaction via the `push_changes` RPC (see
  /// supabase/migrations/). Returns how many were skipped because the
  /// server already had a newer version.
  Future<int> pushChanges(List<Map<String, Object?>> changes);

  /// Every row of [table] the signed-in user owns.
  Future<List<Map<String, dynamic>>> fetchAll(String table);
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  /// Supabase's API returns at most 1,000 rows per request by default.
  static const _pageSize = 1000;

  /// A stable order is what makes paging correct.
  static const _orderBy = {
    'folders': ['id'],
    'tags': ['id'],
    'notes': ['id'],
    'notes_tags': ['note_id', 'tag_id'],
  };

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw const SyncNotSignedInException();
    return user.id;
  }

  @override
  Future<int> pushChanges(List<Map<String, Object?>> changes) async {
    if (_client.auth.currentUser == null) {
      throw const SyncNotSignedInException();
    }
    final result = await _client.rpc(
      'push_changes',
      params: {'p_changes': changes},
    );
    return (result as Map<String, dynamic>)['skipped'] as int? ?? 0;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async {
    final userId = _userId;
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += _pageSize) {
      PostgrestTransformBuilder<List<Map<String, dynamic>>> query = _client
          .from(table)
          .select()
          .eq('owner_id', userId);
      for (final column in _orderBy[table]!) {
        query = query.order(column, ascending: true);
      }
      final page = await query.range(from, from + _pageSize - 1);
      rows.addAll(page);
      if (page.length < _pageSize) return rows;
    }
  }
}

class SyncNotSignedInException implements Exception {
  const SyncNotSignedInException();

  @override
  String toString() => 'Sign in to sync.';
}
