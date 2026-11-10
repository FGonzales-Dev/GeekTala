import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noote/data/database/app_database.dart';
import 'package:noote/data/database/daos/sync_dao.dart';
import 'package:noote/data/providers/auth_provider.dart';
import 'package:noote/data/providers/database_provider.dart';
import 'package:noote/data/providers/device_settings_provider.dart';
import 'package:noote/data/providers/sync_provider.dart';
import 'package:noote/data/sync/sync_remote.dart';
import 'package:noote/data/sync/sync_service.dart';
import 'package:noote/data/providers/attachments_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_attachments.dart';

/// A server that keeps what's pushed, so a download returns it.
class FakeServer implements SyncRemote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  var pushes = 0;

  @override
  Future<int> pushChanges(List<Map<String, Object?>> changes) async {
    pushes++;
    for (final change in changes) {
      final table = tables.putIfAbsent(change['table']! as String, () => {});
      final id = change['id']! as String;
      if (change['op'] == 'delete') {
        table.remove(id);
        continue;
      }
      final row = Map<String, dynamic>.from(change['row']! as Map);
      table[id] = {'owner_id': 'user-1', 'id': id, ...row};
    }
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async =>
      tables[table]?.values.toList() ?? [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late FakeServer server;
  late ProviderContainer container;

  setUp(() async {
    autoUploadDelay = const Duration(milliseconds: 100);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = FakeServer();
    final (attachments, _, dir) = await testAttachmentStore(db);
    addTearDown(() => dir.delete(recursive: true));
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        attachmentStoreProvider.overrideWithValue(attachments),
        syncServiceProvider.overrideWithValue(SyncService(db, server)),
        currentUserProvider.overrideWithValue(
          User(
            id: 'user-1',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-11-09T00:00:00Z',
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> waitUntil(Future<bool> Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    fail('Timed out');
  }

  Future<int> pending() => db.syncDao.pendingCount();

  Future<void> editNote() => db.notesDao.updateNote(
    'grocery-list',
    NotesTableCompanion(
      title: const Value('Edited'),
      updatedAt: Value(DateTime.now()),
    ),
  );

  test('on open: uploads what is waiting, then downloads', () async {
    container.listen(syncCoordinatorProvider, (_, _) {});

    await waitUntil(
      () async =>
          await db.syncDao.readState(SyncDao.lastDownloadedAtKey) != null,
    );
    expect(await pending(), 0);
    expect(server.tables['notes'], hasLength(6));
    // The round trip kept everything.
    expect(await db.select(db.notesTable).get(), hasLength(6));
    expect(container.read(syncControllerProvider).error, isNull);
  });

  test('changes are uploaded shortly after they are made', () async {
    container.listen(syncCoordinatorProvider, (_, _) {});
    await waitUntil(() async => await pending() == 0 && server.pushes > 0);
    final pushesBefore = server.pushes;

    await editNote();
    expect(await pending(), 1);
    await waitUntil(() async => await pending() == 0);

    expect(server.pushes, pushesBefore + 1);
    expect(server.tables['notes']!['grocery-list']!['title'], 'Edited');
  });

  test('nothing runs automatically when it is turned off', () async {
    container.listen(autoSyncEnabledProvider, (_, _) {});
    await container.read(writeDeviceSettingProvider)(
      DeviceSettingKeys.autoSync,
      'off',
    );
    await waitUntil(() async => !container.read(autoSyncEnabledProvider));
    container.listen(syncCoordinatorProvider, (_, _) {});

    await editNote();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(server.pushes, 0);
    expect(await pending(), greaterThan(0));
  });

  test('a download that is skipped does not reload the open editor', () async {
    // Something is edited after the upload and before the download.
    var edited = false;
    final remote = _EditDuringUpload(server, () async {
      if (!edited) {
        edited = true;
        await editNote();
      }
    });
    final manual = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncServiceProvider.overrideWithValue(SyncService(db, remote)),
      ],
    );
    addTearDown(manual.dispose);
    manual.listen(syncControllerProvider, (_, _) {});

    expect(
      await manual.read(syncControllerProvider.notifier).syncOnOpen(),
      isTrue,
    );
    expect(manual.read(syncControllerProvider).downloadCount, 0);
    expect(await pending(), 1); // the edit waits for the next upload
  });
}

/// Runs [onPushed] after each push — an edit landing mid-sync.
class _EditDuringUpload implements SyncRemote {
  _EditDuringUpload(this._server, this.onPushed);

  final FakeServer _server;
  final Future<void> Function() onPushed;

  @override
  Future<int> pushChanges(List<Map<String, Object?>> changes) async {
    final skipped = await _server.pushChanges(changes);
    await onPushed();
    return skipped;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) =>
      _server.fetchAll(table);
}
