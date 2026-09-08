import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Radius tokens from `noote-ui-concepts.html` (`--radius` / `--radius-sm`).
abstract final class AppRadius {
  static const double normal = 10;
  static const double small = 6;
}

abstract final class AppTheme {
  static const _lightBg = Color(0xFFFAFAF7);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightBorder = Color(0xFFE4E3DF);
  static const _lightText = Color(0xFF1A1A18);
  static const _lightTextMuted = Color(0xFF6B6B66);

  static const _darkBg = Color(0xFF121212);
  static const _darkSurface = Color(0xFF1C1C1C);
  static const _darkBorder = Color(0xFF2C2C2A);
  static const _darkText = Color(0xFFEDEDEA);
  static const _darkTextMuted = Color(0xFF9A9A94);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        bg: _lightBg,
        colorScheme: ColorScheme.light(
          primary: _lightText,
          onPrimary: _lightBg,
          secondary: _lightTextMuted,
          onSecondary: _lightBg,
          surface: _lightSurface,
          onSurface: _lightText,
          onSurfaceVariant: _lightTextMuted,
          outline: _lightBorder,
          outlineVariant: NooteColors.light.borderSoft,
        ),
        nooteColors: NooteColors.light,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: _darkBg,
        colorScheme: ColorScheme.dark(
          primary: _darkText,
          onPrimary: _darkBg,
          secondary: _darkTextMuted,
          onSecondary: _darkBg,
          surface: _darkSurface,
          onSurface: _darkText,
          onSurfaceVariant: _darkTextMuted,
          outline: _darkBorder,
          outlineVariant: NooteColors.dark.borderSoft,
        ),
        nooteColors: NooteColors.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required ColorScheme colorScheme,
    required NooteColors nooteColors,
  }) {
    final baseTextTheme = ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: 'Inter',
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      fontFamily: 'Inter',
      textTheme: baseTextTheme,
      extensions: [nooteColors],
      dividerColor: colorScheme.outline,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.normal),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: nooteColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 18),
    );
  }
}
