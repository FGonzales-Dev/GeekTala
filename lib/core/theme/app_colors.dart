import 'package:flutter/material.dart';

/// Tokens from `noote-ui-concepts.html` that don't map onto Flutter's
/// standard [ColorScheme] roles. Keep this in sync with the mockup and with
/// §3 of noote-plan.md if either changes.
@immutable
class NooteColors extends ThemeExtension<NooteColors> {
  const NooteColors({
    required this.surfaceAlt,
    required this.surfaceRaised,
    required this.borderSoft,
    required this.textFaint,
    required this.focus,
    required this.selectionBg,
    required this.activeBg,
    required this.codeBg,
    required this.codeBorder,
    required this.avatar1,
    required this.avatar2,
    required this.avatar3,
  });

  final Color surfaceAlt;
  final Color surfaceRaised;
  final Color borderSoft;
  final Color textFaint;
  final Color focus;
  final Color selectionBg;
  final Color activeBg;
  final Color codeBg;
  final Color codeBorder;
  final Color avatar1;
  final Color avatar2;
  final Color avatar3;

  static const light = NooteColors(
    surfaceAlt: Color(0xFFF2F1EE),
    surfaceRaised: Color(0xFFFBFBF9),
    borderSoft: Color(0xFFEDEDE9),
    textFaint: Color(0xFFA3A39D),
    focus: Color(0xFF8A8D91),
    selectionBg: Color(0xFFECEBE7),
    activeBg: Color(0xFFF0EFEB),
    codeBg: Color(0xFFF4F3F0),
    codeBorder: Color(0xFFE6E5E1),
    avatar1: Color(0xFF9CAF9A),
    avatar2: Color(0xFF9AAAB8),
    avatar3: Color(0xFFC2A490),
  );

  static const dark = NooteColors(
    surfaceAlt: Color(0xFF202020),
    surfaceRaised: Color(0xFF232323),
    borderSoft: Color(0xFF252523),
    textFaint: Color(0xFF68685F),
    focus: Color(0xFF7C8085),
    selectionBg: Color(0xFF262624),
    activeBg: Color(0xFF242422),
    codeBg: Color(0xFF181818),
    codeBorder: Color(0xFF2A2A28),
    avatar1: Color(0xFF7C9A78),
    avatar2: Color(0xFF7C93A6),
    avatar3: Color(0xFFAC8B72),
  );

  @override
  NooteColors copyWith({
    Color? surfaceAlt,
    Color? surfaceRaised,
    Color? borderSoft,
    Color? textFaint,
    Color? focus,
    Color? selectionBg,
    Color? activeBg,
    Color? codeBg,
    Color? codeBorder,
    Color? avatar1,
    Color? avatar2,
    Color? avatar3,
  }) {
    return NooteColors(
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      borderSoft: borderSoft ?? this.borderSoft,
      textFaint: textFaint ?? this.textFaint,
      focus: focus ?? this.focus,
      selectionBg: selectionBg ?? this.selectionBg,
      activeBg: activeBg ?? this.activeBg,
      codeBg: codeBg ?? this.codeBg,
      codeBorder: codeBorder ?? this.codeBorder,
      avatar1: avatar1 ?? this.avatar1,
      avatar2: avatar2 ?? this.avatar2,
      avatar3: avatar3 ?? this.avatar3,
    );
  }

  @override
  NooteColors lerp(ThemeExtension<NooteColors>? other, double t) {
    if (other is! NooteColors) return this;
    return NooteColors(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      selectionBg: Color.lerp(selectionBg, other.selectionBg, t)!,
      activeBg: Color.lerp(activeBg, other.activeBg, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeBorder: Color.lerp(codeBorder, other.codeBorder, t)!,
      avatar1: Color.lerp(avatar1, other.avatar1, t)!,
      avatar2: Color.lerp(avatar2, other.avatar2, t)!,
      avatar3: Color.lerp(avatar3, other.avatar3, t)!,
    );
  }
}

extension NooteColorsContext on BuildContext {
  NooteColors get nooteColors => Theme.of(this).extension<NooteColors>()!;
}
