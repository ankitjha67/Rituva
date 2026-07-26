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

/// Standard scroll padding for a tab body — the extra bottom clears the
/// navigation bar / gesture area so the last card or button is never cramped.
const EdgeInsets kScreenPad = EdgeInsets.fromLTRB(16, 16, 16, 32);

/// "2026-07-26" → "Sat, 26 Jul" (falls back to the raw string on any parse issue).
String prettyDate(Object? iso) {
  final s = '${iso ?? ''}';
  try {
    final d = DateTime.parse(s);
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]}';
  } catch (_) {
    return s;
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

/// Turn any snake_case / lowercase identifier into a friendly label
/// (e.g. `lacto_veg` → "Lacto veg", `kidney_stones` → "Kidney stones").
String humanize(String? s) {
  if (s == null || s.isEmpty) return '';
  return s
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Human-facing meal-slot names (the engine uses snack1/snack2 internally).
String slotLabel(String s) => const {
      'breakfast': 'Breakfast',
      'snack1': 'Mid-morning',
      'lunch': 'Lunch',
      'snack2': 'Evening snack',
      'dinner': 'Dinner',
    }[s] ??
    humanize(s);

String mealEmoji(String s) => const {
      'breakfast': '🥣',
      'lunch': '🍚',
      'dinner': '🫓',
      'snack1': '🥜',
      'snack2': '🍎',
    }[s] ??
    '🍽️';
