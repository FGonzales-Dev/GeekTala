import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manual light/dark/system override (noote-plan.md §3: "Respect
/// system-level light/dark preference by default, with a manual override
/// in Settings"). Not persisted yet — persistence lands with Drift/local
/// prefs in a later pass.
class AppThemeMode extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void select(ThemeMode mode) => state = mode;
}

final appThemeModeProvider = NotifierProvider<AppThemeMode, ThemeMode>(
  AppThemeMode.new,
);
