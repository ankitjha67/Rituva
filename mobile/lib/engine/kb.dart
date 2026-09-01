import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// The Knowledge DB, on the device.
///
/// Two sources, in priority order:
///   1. a full KB the user downloaded from their own Rituva server (601 foods / 1302
///      dishes). That library is IFCT-derived and licensed for personal use, so it may
///      never be committed or shipped in an APK — it travels from the user's machine to
///      the user's phone and no further.
///   2. `assets/kb.json`, the curated public KB baked into every build (95 foods /
///      94 dishes), so a fresh install plans real menus with no server at all.
class KB {
  final Map<String, Food> foods;
  final Map<String, Recipe> recipes;
  final Map<String, dynamic> policy;
  final List members;
  final String version;
  final bool isFull; // true when the downloaded library is in use

  KB({
    required this.foods,
    required this.recipes,
    required this.policy,
    required this.members,
    required this.version,
    required this.isFull,
  });

  static KB? _cached;

  /// Where a downloaded full KB is kept. Null on platforms without a writable dir.
  static String? downloadPath;

  static Future<KB> load() async {
    if (_cached != null) return _cached!;
    Map<String, dynamic>? raw;
    var full = false;
    final p = downloadPath;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) {
          raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          full = true;
        }
      } catch (_) {
        raw = null; // corrupt download — fall back to the bundled KB rather than failing
      }
    }
    raw ??= jsonDecode(await rootBundle.loadString('assets/kb.json')) as Map<String, dynamic>;
    return _cached = KB.fromJson(raw, isFull: full);
  }

  /// Drop the cache so the next load() picks up a freshly downloaded library.
  static void invalidate() => _cached = null;

  factory KB.fromJson(Map<String, dynamic> j, {bool isFull = false}) {
    final foods = <String, Food>{};
    for (final f in (j['foods'] as List)) {
      final food = Food.fromJson(f as Map<String, dynamic>);
      foods[food.id] = food;
    }
    final recipes = <String, Recipe>{};
    for (final r in (j['recipes'] as List)) {
      final rec = Recipe.fromJson(r as Map<String, dynamic>);
      // Only keep dishes whose every ingredient resolves — the same rule the server
      // applies, so a partial KB can never produce a dish with missing nutrients.
      if (rec.ingredients.every((i) => foods.containsKey(i.foodId))) recipes[rec.id] = rec;
    }
    return KB(
      foods: foods,
      recipes: recipes,
      policy: (j['policy'] as Map?)?.cast<String, dynamic>() ?? const {},
      members: (j['members'] as List?) ?? const [],
      version: '${j['kb_version'] ?? 'kb'}',
      isFull: isFull,
    )
      ..llmRecipes = (j['llm_recipes'] as Map?)?.cast<String, dynamic>() ?? {}
      ..rda = (j['rda'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// ICMR-NIN Recommended Dietary Allowances by life stage, plus the deficiency
  /// disorders each shortfall causes. Transcribed from the Dietary Guidelines for
  /// Indians, so the reference screen works offline like everything else.
  Map<String, dynamic> rda = {};

  /// Recipe prose written by a real model on the server and carried along with a
  /// downloaded library. Absent for the bundled KB — in that case the app shows the
  /// deterministic method rather than inventing prose on-device.
  Map<String, dynamic> llmRecipes = {};

  int get pulseCount => (policy['pulse_ids'] as List?)?.length ?? 0;
  Set<String> get pulseIds =>
      ((policy['pulse_ids'] as List?) ?? const []).map((e) => '$e').toSet();
  Map<String, dynamic> get frequency =>
      (policy['frequency'] as Map?)?.cast<String, dynamic>() ?? const {};
}

class Food {
  final String id, name, group, source;
  final double kcal, protein, carb, fat, fibre, iron, calcium, b12, sodium;
  const Food({
    required this.id,
    required this.name,
    required this.group,
    required this.source,
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.fibre,
    required this.iron,
    required this.calcium,
    required this.b12,
    required this.sodium,
  });

  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: '${j['id']}',
        name: '${j['name']}',
        group: '${j['group']}',
        source: '${j['source'] ?? 'IFCT 2017'}',
        kcal: _d(j['kcal']),
        protein: _d(j['protein']),
        carb: _d(j['carb']),
        fat: _d(j['fat']),
        fibre: _d(j['fibre']),
        iron: _d(j['iron']),
        calcium: _d(j['calcium']),
        b12: _d(j['b12']),
        sodium: _d(j['sodium']),
      );

  /// Nutrients for `qtyG` grams — a pure DB lookup times a scale, exactly as the server
  /// computes it. Nothing here is estimated.
  Map<String, double> per(double qtyG) {
    final f = qtyG / 100.0;
    return {
      'kcal': kcal * f,
      'protein': protein * f,
      'carb': carb * f,
      'fat': fat * f,
      'fibre': fibre * f,
      'iron': iron * f,
      'calcium': calcium * f,
      'b12': b12 * f,
      'sodium': sodium * f,
    };
  }
}

class Ingredient {
  final String foodId;
  final double qtyG;
  const Ingredient(this.foodId, this.qtyG);
}

class Recipe {
  final String id, name, role;
  final String? region;
  final List<String>? seasons;
  final List<Ingredient> ingredients;
  final double addedSaltG;
  final String? hero;
  final Set<String> contains, tags;

  const Recipe({
    required this.id,
    required this.name,
    required this.role,
    required this.region,
    required this.seasons,
    required this.ingredients,
    required this.addedSaltG,
    required this.hero,
    required this.contains,
    required this.tags,
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: '${j['id']}',
        name: '${j['name']}',
        role: '${j['role']}',
        region: j['region'] == null ? null : '${j['region']}',
        seasons: (j['seasons'] as List?)?.map((e) => '$e').toList(),
        ingredients: ((j['ingredients'] as List?) ?? const [])
            .map((i) => Ingredient('${i['food_id']}', ((i['qty_g'] as num?)?.toDouble() ?? 0)))
            .toList(),
        addedSaltG: (j['added_salt_g'] as num?)?.toDouble() ?? 0,
        hero: j['hero'] == null ? null : '${j['hero']}',
        contains: ((j['contains'] as List?) ?? const []).map((e) => '$e').toSet(),
        tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toSet(),
      );
}

/// CRC32, matching Python's `zlib.crc32`. The planner uses it for stable tie-breaks and
/// for the regenerate rotation; Dart's `hashCode` varies between runs, which would make
/// plans non-reproducible in exactly the way the server side was fixed for.
class Crc32 {
  static final List<int> _table = _build();
  static List<int> _build() {
    final t = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[i] = c;
    }
    return t;
  }

  static int of(String s) {
    var crc = 0xFFFFFFFF;
    for (final b in utf8.encode(s)) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
