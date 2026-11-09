import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/device_settings_provider.dart';

/// Drag-to-resize state for the desktop three-pane shell's sidebar and
/// notes-list panes. Remembered on this device; saved when a drag ends
/// (not on every pixel of it).
class _PaneWidth extends Notifier<double> {
  _PaneWidth(this._key, this._initial, this.min, this.max);

  final String _key;
  final double _initial;
  final double min;
  final double max;

  @override
  double build() {
    final saved = ref.watch(
      deviceSettingsProvider.select((s) => s.value?[_key]),
    );
    final width = double.tryParse(saved ?? '');
    return width == null ? _initial : width.clamp(min, max);
  }

  void dragBy(double delta) {
    state = (state + delta).clamp(min, max);
  }

  void save() => ref.read(writeDeviceSettingProvider)(_key, '$state');
}

final sidebarWidthProvider = NotifierProvider<_PaneWidth, double>(
  () => _PaneWidth(DeviceSettingKeys.sidebarWidth, 210, 160, 400),
);

final notesListWidthProvider = NotifierProvider<_PaneWidth, double>(
  () => _PaneWidth(DeviceSettingKeys.notesListWidth, 250, 200, 480),
);
