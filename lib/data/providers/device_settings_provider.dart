import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

/// Keys for [deviceSettingsProvider].
abstract final class DeviceSettingKeys {
  static const themeMode = 'pref.theme_mode';
  static const sidebarWidth = 'pref.sidebar_width';
  static const notesListWidth = 'pref.notes_list_width';
  static const pasteMarkdown = 'pref.paste_markdown';
  static const autoSync = 'pref.auto_sync';
}

/// Small preferences for this device (theme, pane widths, …), kept in the
/// local key/value table sync also uses for its own state (`SyncDao`). They
/// are never uploaded.
///
/// Watch one key with `deviceSettingsProvider.select((s) => s.value?[key])`
/// so unrelated writes (sync records its times here) don't rebuild you.
final deviceSettingsProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(appDatabaseProvider).syncDao.watchState();
});

/// Saves a [deviceSettingsProvider] value.
final writeDeviceSettingProvider =
    Provider<Future<void> Function(String key, String value)>((ref) {
      final dao = ref.watch(appDatabaseProvider).syncDao;
      return dao.writeState;
    });
