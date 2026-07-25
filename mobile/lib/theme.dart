import 'package:flutter/material.dart';

/// Rituva design tokens — the approved "spice-garden futurism" palette (PRD §17).
class R {
  static const bg = Color(0xFF0A1410);
  static const bg2 = Color(0xFF0E1B16);
  static const surface = Color(0x14FFFFFF);
  static const line = Color(0x1AFFFFFF);
  static const ink = Color(0xFFEAF2ED);
  static const muted = Color(0xFF93A99E);
  static const gold = Color(0xFFFFB020); // signature accent
  static const green = Color(0xFF57DF97);
  static const magenta = Color(0xFFFF5D8F);
  static const teal = Color(0xFF33D6C0); // protein
  static const violet = Color(0xFFB08CFF); // fat
  static const fibre = Color(0xFF57DF97);

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(primary: gold, secondary: teal, surface: bg2),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    );
  }
}

Color regionColor(String? r) {
  switch (r) {
    case 'north':
      return R.magenta;
    case 'south':
      return R.teal;
    case 'east':
      return R.gold;
    case 'west':
      return R.violet;
    default:
      return R.muted;
  }
}
