import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/device_settings_provider.dart';

/// Manual light/dark/system override (noote-plan.md §3: "Respect
/// system-level light/dark preference by default, with a manual override
/// in Settings"). Remembered on this device.
class AppThemeMode extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.watch(
      deviceSettingsProvider.select(
        (s) => s.value?[DeviceSettingKeys.themeMode],
      ),
    );
    return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
  }

  void select(ThemeMode mode) {
    state = mode;
    ref.read(writeDeviceSettingProvider)(
      DeviceSettingKeys.themeMode,
      mode.name,
    );
  }
}

final appThemeModeProvider = NotifierProvider<AppThemeMode, ThemeMode>(
  AppThemeMode.new,
);
