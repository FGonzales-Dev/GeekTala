import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/device_settings_provider.dart';

/// Folders whose subfolders are hidden in the folder tree (sidebar and
/// mobile Folders screen). Everything starts open; remembered on this
/// device.
class CollapsedFolders extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final saved = ref.watch(
      deviceSettingsProvider.select(
        (s) => s.value?[DeviceSettingKeys.collapsedFolders],
      ),
    );
    if (saved == null) return const {};
    try {
      return {...(jsonDecode(saved) as List).cast<String>()};
    } catch (_) {
      return const {};
    }
  }

  void toggle(String folderId) => _save(
    state.contains(folderId)
        ? ({...state}..remove(folderId))
        : {...state, folderId},
  );

  void expand(String folderId) {
    if (state.contains(folderId)) _save({...state}..remove(folderId));
  }

  void _save(Set<String> collapsed) {
    state = collapsed;
    ref.read(writeDeviceSettingProvider)(
      DeviceSettingKeys.collapsedFolders,
      jsonEncode(collapsed.toList()..sort()),
    );
  }
}

final collapsedFoldersProvider =
    NotifierProvider<CollapsedFolders, Set<String>>(CollapsedFolders.new);
