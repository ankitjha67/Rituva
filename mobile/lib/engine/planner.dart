import 'dart:math' as math;
import 'kb.dart';

/// A Dart port of the deterministic planner (`rituva/planner.py`), so the phone can build
/// real, validated menus with no server.
///
/// It is a port, not a re-imagining: the same role pools, the same min-gap and frequency
/// caps, the same grain scaling to hit the energy target, the same validator and Diet
/// Quality Score, and the same regenerate rotation (variant 0 is the canonical plan;
/// variant N rotates through the top-K best dishes per role). Numbers come only from the
/// Knowledge DB — this file computes, it never invents.

// ---------------------------------------------------------------- nutrition ----
const kNutrients = [
  'kcal', 'protein', 'carb', 'fat', 'fibre', 'iron', 'calcium', 'b12', 'sodium'
];
const _sodiumMgPerGSalt = 393.0;

Map<String, double> zeroNutrients() => {for (final n in kNutrients) n: 0.0};

Map<String, double> addNutrients(Map<String, double> a, Map<String, double> b) =>
    {for (final n in kNutrients) n: (a[n] ?? 0) + (b[n] ?? 0)};

/// One dish on the plate, at a given scale, with its per-ingredient breakdown.
class Component {
  final Recipe recipe;
  final double scale;
  final Map<String, double> nutrients;
  final List<Map<String, dynamic>> ingredients;
  const Component(this.recipe, this.scale, this.nutrients, this.ingredients);

  String get name => recipe.name;
  String? get region => recipe.region;
}

Component makeComponent(KB kb, Recipe r, [double scale = 1.0]) {
  var total = zeroNutrients();
  final rows = <Map<String, dynamic>>[];
  for (final ing in r.ingredients) {
    final food = kb.foods[ing.foodId];
    if (food == null) continue;
    final qty = ing.qtyG * scale;
    final nut = food.per(qty);
    rows.add({
      'food_id': food.id,
      'name': food.name,
      'qty_g': double.parse(qty.toStringAsFixed(1)),
      'kcal': nut['kcal']!.round(),
      'protein': double.parse(nut['protein']!.toStringAsFixed(1)),
      'fibre': double.parse(nut['fibre']!.toStringAsFixed(1)),
      'source': food.source,
    });
    total = addNutrients(total, nut);
  }
  if (r.addedSaltG > 0) {
    total['sodium'] = (total['sodium'] ?? 0) + r.addedSaltG * scale * _sodiumMgPerGSalt;
  }
  return Component(r, scale, total, rows);
}

// --------------------------------------------------------------------- diet ----
const _nonvegGroups = {'Eggs', 'Poultry', 'Meat', 'Fish', 'Shellfish'};
const _glutenKeys = [
  'atta', 'wheat', 'suji', 'semolina', 'rava', 'maida', 'daliya', 'dalia',
  'vermicelli', 'seviyan', 'bread', 'pasta', 'noodle', 'barley'
];
const _jainBadIds = {'onion', 'garlic', 'spring_onion', 'ginger', 'shallot'};
const _rootKeys = [
  'potato', 'onion', 'garlic', 'carrot', 'radish', 'beet', 'beetroot', 'sweet potato',
  'colocasia', 'arbi', 'yam', 'tapioca', 'turnip', 'mooli', 'lotus root', 'ginger',
  'shallot', 'elephant foot'
];

final Map<String, Set<String>> _dietCache = {};

/// Diet labels derived from a dish's actual ingredients — never hand-tagged.
Set<String> dietLabels(KB kb, Recipe r) {
  final hit = _dietCache[r.id];
  if (hit != null) return hit;
  final ids = r.ingredients.map((i) => i.foodId).toList();
  final groups = ids.map((f) => kb.foods[f]?.group ?? '').toList();
  String nm(String f) => (kb.foods[f]?.name ?? f.replaceAll('_', ' ')).toLowerCase();

  final contains = <String>{...r.contains};
  if (groups.contains('Eggs')) contains.add('egg');
  if (groups.any((g) => g == 'Poultry' || g == 'Meat')) contains.add('meat');
  if (groups.any((g) => g == 'Fish' || g == 'Shellfish')) contains.add('fish');
  if (groups.contains('Dairy')) contains.add('dairy');
  if (groups.contains('Nuts')) contains.add('nut');
  if (ids.any((f) => _glutenKeys.any((k) => nm(f).contains(k) || f.contains(k)))) {
    contains.add('gluten');
  }

  final nonveg = contains.contains('egg') || contains.contains('meat') || contains.contains('fish');
  final root = ids.any((f) => _jainBadIds.contains(f)) ||
      ids.any((f) => _rootKeys.any((k) => nm(f).contains(k)));

  final labels = <String>{nonveg ? 'nonveg' : 'veg'};
  if (!nonveg && !contains.contains('dairy')) labels.add('vegan');
  if (!nonveg && !root) labels.add('jain');
  if (!contains.contains('gluten')) labels.add('gluten_free');
  for (final t in ['egg', 'meat', 'fish', 'dairy']) {
    if (contains.contains(t)) labels.add(t);
  }
  return _dietCache[r.id] = labels;
}

bool dietOk(KB kb, Recipe r, Map member) {
  final lab = dietLabels(kb, r);
  final dt = '${member['diet_type'] ?? 'lacto_veg'}';
  final excludes = ((member['excludes'] as List?) ?? const []).map((e) => '$e').toSet();
  if (excludes.contains('gluten_free') || excludes.contains('gluten')) {
    if (!lab.contains('gluten_free')) return false;
  }
  switch (dt) {
    case 'vegan':
      return lab.contains('vegan');
    case 'jain':
      return lab.contains('jain');
    case 'lacto_veg':
      return !lab.contains('nonveg');
    case 'lacto_ovo':
      return !lab.contains('meat') && !lab.contains('fish');
    case 'pescatarian':
      return !lab.contains('meat');
    case 'nonveg':
    case 'omnivore':
      return true;
    default:
      return !lab.contains('nonveg');
  }
}

// ------------------------------------------------------------------ targets ----
const _fatPct = 0.27;
const _fibrePer1000 = 25.0;
const _sodiumMax = 2000.0;
const _addedSugarMax = 25.0;
const _energyFloor = 1000.0;
const _proteinPerKg = {'maintain': 1.0, 'lose': 1.2, 'gain': 1.4, 'muscle': 1.5};
const _goalKcalAdj = {'maintain': 0.0, 'lose': -500.0, 'gain': 350.0, 'muscle': 300.0};
const _ironRda = {'M': 19.0, 'F': 29.0};

double _bmr(String sex, double kg, double cm, int age) =>
    10 * kg + 6.25 * cm - 5 * age + (sex == 'M' ? 5 : -161);

/// Targets + the anthropometry they were derived from — mirrors `targets.py`.
Map<String, dynamic> computeTargets(Map member) {
  final sex = '${member['sex'] ?? 'M'}';
  final kg = (member['weight_kg'] as num?)?.toDouble() ?? 65;
  final cm = (member['height_cm'] as num?)?.toDouble() ?? 165;
  final age = (member['age'] as num?)?.toInt() ?? 30;
  final pal = (member['pal'] as num?)?.toDouble() ?? 1.4;
  final goal = '${member['goal'] ?? 'maintain'}';

  final bmr = _bmr(sex, kg, cm, age);
  final tdee = bmr * pal;
  var kcal = tdee + (_goalKcalAdj[goal] ?? 0);
  if (kcal < _energyFloor) kcal = _energyFloor;
  final proteinG = (_proteinPerKg[goal] ?? 1.0) * kg;
  final fatG = kcal * _fatPct / 9.0;
  final carbG = math.max(kcal - proteinG * 4 - fatG * 9, 0) / 4.0;
  final fibreG = _fibrePer1000 * kcal / 1000.0;

  final t = <String, dynamic>{
    'kcal': kcal.round(),
    'protein_g': proteinG.round(),
    'fat_g': fatG.round(),
    'carb_g': carbG.round(),
    'fibre_g': fibreG.round(),
    'sodium_mg_max': _sodiumMax,
    'added_sugar_g_max': _addedSugarMax,
    'iron_mg': _ironRda[sex] ?? 19.0,
    'calcium_mg': 1000.0,
    'b12_ug': 2.2,
    'source': 'computed',
    'citations': ['DGI 2024 p.54/58', 'WHO FS-394', 'ICMR-NIN RDA 2020'],
  };

  // User/doctor-supplied values are facts — used verbatim, never re-optimised.
  final known = (member['known_targets'] as Map?) ?? const {};
  final doctor = (member['doctor_diet'] as Map?) ?? const {};
  for (final src in [known, doctor]) {
    if (src.isEmpty) continue;
    for (final k in ['kcal', 'protein_g', 'fat_g', 'carb_g', 'fibre_g', 'sodium_mg_max',
                     'added_sugar_g_max', 'iron_mg', 'calcium_mg', 'b12_ug']) {
      if (src[k] != null) t[k] = src[k];
    }
    t['source'] = src == doctor ? 'doctor_prescription' : 'user_provided';
  }

  final h = cm / 100.0;
  final bmi = kg / (h * h);
  return {
    'targets': t,
    'anthropometry': {
      'bmi': double.parse(bmi.toStringAsFixed(1)),
      'bmi_category': bmi < 18.5
          ? 'Underweight'
          : bmi < 23
              ? 'Normal'
              : bmi < 27.5
                  ? 'Overweight'
                  : 'Obese',
      'bmr': bmr.round(),
      'tdee': tdee.round(),
    },
  };
}

// ------------------------------------------------------------------ planner ----
const _kcalTolerance = 0.12;
const _grainScaleBounds = [0.4, 2.4];

const _formats = {
  'chilla', 'cheela', 'chila', 'paratha', 'dosa', 'idli', 'uttapam', 'pesarattu',
  'upma', 'poha', 'porridge', 'pongal', 'dhokla', 'thepla', 'adai', 'sabzi', 'bhaji',
  'masala', 'curry', 'poriyal', 'thoran', 'bhaja', 'fry', 'kadhi', 'kofta', 'bharta',
  'tadka', 'khichdi', 'pulao', 'biryani', 'raita', 'roti', 'sambar', 'rasam', 'stew',
  'roast', 'bhurji', 'tikka', 'salad', 'soup', 'ghugni',
};

String dishFormat(Recipe r) {
  final words = r.name
      .toLowerCase()
      .replaceAll('(', ' ')
      .replaceAll(')', ' ')
      .replaceAll('-', ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  for (final w in words.reversed) {
    final c = w.replaceAll(RegExp(r'[.,]'), '');
    if (_formats.contains(c)) return c;
  }
  return words.isEmpty ? r.id : words.last;
}

String seasonForMonth(int m) {
  if (m == 12 || m <= 2) return 'winter';
  if (m <= 4) return 'spring';
  if (m <= 6) return 'summer';
  return 'monsoon';
}

/// Tracks what has been served, so nothing repeats too soon and no ingredient, region or
/// dish format dominates the week.
class Ledger {
  final Map<String, dynamic> policy;
  final Set<String> pulseIds;
  final bool singleRegion;
  final int variant;
  final Map<String, int> dishLast = {};
  final Map<String, List<int>> heroDays = {}, pulseDays = {}, regionDays = {}, fmtDays = {};

  Ledger(this.policy, this.pulseIds, {this.singleRegion = false, this.variant = 0});

  int _num(String key, int fallback) => (policy[key] as num?)?.toInt() ?? fallback;

  static int _count(List<int>? days, int di, {int window = 7}) =>
      (days ?? const []).where((d) => di - window < d && d <= di).length;

  bool dishAllowed(Recipe r, int di) {
    if (r.tags.contains('staple')) return true;
    final gap = r.role == 'snack'
        ? _num('snack_min_gap_days', 2)
        : r.role == 'veg'
            ? _num('veg_min_gap_days', 3)
            : _num('dish_min_gap_days', 5);
    final last = dishLast[r.id];
    return last == null || (di - last) >= gap;
  }

  bool freqAllowed(KB kb, Recipe r, int di) {
    final perWeek = (policy['ingredient_per_week'] as Map?) ?? const {};
    if (r.hero != null && perWeek[r.hero] != null) {
      if (_count(heroDays[r.hero], di) >= (perWeek[r.hero] as num).toInt()) return false;
    }
    for (final ing in r.ingredients) {
      if (pulseIds.contains(ing.foodId)) {
        if (_count(pulseDays[ing.foodId], di) >= _num('pulse_per_week', 2)) return false;
      }
    }
    if (r.region != null && !singleRegion) {
      if (_count(regionDays[r.region], di) >= _num('region_days_per_week', 4)) return false;
    }
    if (!r.tags.contains('staple')) {
      if (_count(fmtDays[dishFormat(r)], di) >= _num('format_per_week', 3)) return false;
    }
    return true;
  }

  bool allowed(KB kb, Recipe r, int di) => dishAllowed(r, di) && freqAllowed(kb, r, di);

  void record(KB kb, Recipe r, int di) {
    dishLast[r.id] = di;
    if (r.hero != null) (heroDays[r.hero!] ??= []).add(di);
    for (final ing in r.ingredients) {
      if (pulseIds.contains(ing.foodId)) (pulseDays[ing.foodId] ??= []).add(di);
    }
    if (r.region != null) (regionDays[r.region!] ??= []).add(di);
    (fmtDays[dishFormat(r)] ??= []).add(di);
  }

  int daysSince(Recipe r, int di) {
    final last = dishLast[r.id];
    return last == null ? 999 : di - last;
  }
}

double _score(KB kb, Recipe r, Map member, Ledger led, int di) {
  var s = 0.0;
  final prefs = ((member['region_prefs'] as List?) ?? const []).map((e) => '$e').toSet();
  if (r.region != null && prefs.contains(r.region)) s += 3.0;
  if (r.tags.contains('high_protein') && '${member['goal']}' == 'muscle') s += 2.0;
  s -= Ledger._count(led.fmtDays[dishFormat(r)], di, window: 2) * 0.9;
  s += math.min(led.daysSince(r, di), 12) * 0.1;
  s += ((Crc32.of(r.id) + di * 7) % 5) * 0.06;
  return s;
}

/// variant 0 → the best pick (canonical). Regenerate rotates through the top-K best, so
/// every press yields a visibly different menu that is still one of the strongest options.
Recipe _variantChoice(List<Recipe> ranked, Ledger led, int di, String label) {
  if (led.variant == 0 || ranked.length <= 1) return ranked.first;
  final k = math.min(ranked.length, 8);
  final base = Crc32.of('$label:$di');
  return ranked[(base + led.variant) % k];
}

Recipe? _pick(KB kb, List<Recipe> pool, Map member, Ledger led, int di,
    List<String> warnings, String label) {
  if (pool.isEmpty) return null;
  final cands = [...pool]..sort((a, b) => _score(kb, b, member, led, di).compareTo(_score(kb, a, member, led, di)));
  final allowed = cands.where((r) => led.allowed(kb, r, di)).toList();
  if (allowed.isNotEmpty) return _variantChoice(allowed, led, di, label);
  final relaxed = cands.where((r) => led.freqAllowed(kb, r, di)).toList();
  if (relaxed.isNotEmpty) {
    final r = _variantChoice(relaxed, led, di, label);
    warnings.add("$label: library thin — reused '${r.name}' inside the gap window");
    return r;
  }
  return cands.first;
}

List<Recipe> _basePool(KB kb, String role, Map member, String season) {
  final excludes = ((member['excludes'] as List?) ?? const []).map((e) => '$e').toSet();
  return kb.recipes.values.where((r) {
    if (r.role != role) return false;
    if (!dietOk(kb, r, member)) return false;
    if (r.seasons != null && !r.seasons!.contains(season)) return false;
    if (excludes.isNotEmpty) {
      if (r.hero != null && excludes.contains(r.hero)) return false;
      if (r.tags.any(excludes.contains)) return false;
      if (r.ingredients.any((i) => excludes.contains(i.foodId))) return false;
    }
    return true;
  }).toList();
}

const _slotOrder = ['breakfast', 'lunch', 'dinner', 'snack1', 'snack2'];

/// Build `days` days of menus for a member. Same shape the server's /plans returns, so the
/// UI can't tell which engine produced it.
List<Map<String, dynamic>> planDays(
  KB kb,
  Map member,
  Map<String, dynamic> targets,
  DateTime start,
  int days, {
  int variant = 0,
}) {
  final prefs = ((member['region_prefs'] as List?) ?? const []).length;
  final led = Ledger(kb.frequency, kb.pulseIds, singleRegion: prefs == 1, variant: variant);
  final out = <Map<String, dynamic>>[];
  for (var di = 0; di < days; di++) {
    out.add(_oneDay(kb, member, targets, start.add(Duration(days: di)), di, led));
  }
  return out;
}

Map<String, dynamic> _oneDay(
    KB kb, Map member, Map<String, dynamic> t, DateTime d, int di, Ledger led) {
  final season = seasonForMonth(d.month);
  final warnings = <String>[];
  final goal = '${member['goal'] ?? 'maintain'}';
  final mainScale0 = goal == 'muscle' ? 1.5 : (goal == 'gain' ? 1.3 : 1.1);
  final targetKcal = (t['kcal'] as num).toDouble();
  final targetProtein = (t['protein_g'] as num).toDouble();

  Recipe? pickAndRecord(String role, String label) {
    final r = _pick(kb, _basePool(kb, role, member, season), member, led, di, warnings, label);
    if (r != null) led.record(kb, r, di);
    return r;
  }

  final bf = pickAndRecord('breakfast', 'Breakfast');
  final lMain = pickAndRecord('main', 'Lunch main');
  final lVeg = pickAndRecord('veg', 'Lunch veg');
  final dMain = pickAndRecord('main', 'Dinner main');
  final dVeg = pickAndRecord('veg', 'Dinner veg');

  final snacks = <Recipe>[];
  final snackPool = _basePool(kb, 'snack', member, season);
  for (var i = 0; i < 2; i++) {
    final cands = snackPool.where((r) => !snacks.any((c) => c.id == r.id)).toList()
      ..sort((a, b) => _score(kb, b, member, led, di).compareTo(_score(kb, a, member, led, di)));
    if (cands.isEmpty) break;
    final ok = cands.where((r) => led.allowed(kb, r, di)).toList();
    final pick = _variantChoice(ok.isNotEmpty ? ok : cands, led, di, 'snack$i');
    snacks.add(pick);
    led.record(kb, pick, di);
  }

  // Staple grains alternate by slot and day; they're Tier-0 and exempt from the caps.
  final grains = kb.recipes.values.where((r) => r.tags.contains('staple')).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final rice = kb.recipes['rice_plain'] ?? (grains.isNotEmpty ? grains.first : null);
  final roti = kb.recipes['roti'] ?? (grains.length > 1 ? grains[1] : rice);
  final lunchGrain = di % 2 == 0 ? rice : roti;
  final dinnerGrain = di % 2 == 0 ? roti : rice;

  // Grow the mains (bounded) until protein is ~met, then let the grains fill the rest of
  // the energy — the same two-stage fit the server uses.
  var ms = mainScale0;
  Component? bfC, lMainC, lVegC, dMainC, dVegC, lg, dg;
  var snackC = <Component>[];
  for (var attempt = 0; attempt < 5; attempt++) {
    bfC = bf == null ? null : makeComponent(kb, bf);
    lMainC = lMain == null ? null : makeComponent(kb, lMain, ms);
    lVegC = lVeg == null ? null : makeComponent(kb, lVeg);
    dMainC = dMain == null ? null : makeComponent(kb, dMain, ms);
    dVegC = dVeg == null ? null : makeComponent(kb, dVeg);
    snackC = snacks.map((s) => makeComponent(kb, s)).toList();

    final fixed = <Component>[
      if (bfC != null) bfC, if (lMainC != null) lMainC, if (lVegC != null) lVegC,
      if (dMainC != null) dMainC, if (dVegC != null) dVegC, ...snackC,
    ];
    final fixedKcal = fixed.fold<double>(0, (a, c) => a + (c.nutrients['kcal'] ?? 0));
    final grainKcal = math.max(targetKcal - fixedKcal, 250.0);
    lg = _grainComponent(kb, lunchGrain, grainKcal / 2);
    dg = _grainComponent(kb, dinnerGrain, grainKcal / 2);
    final protein = fixed.fold<double>(0, (a, c) => a + (c.nutrients['protein'] ?? 0)) +
        (lg.nutrients['protein'] ?? 0) + (dg.nutrients['protein'] ?? 0);
    if (protein >= 0.9 * targetProtein || ms >= 2.0) break;
    ms = math.min(2.0, ms + 0.3);
  }

  Map<String, dynamic> entry(String slot, List<Component> comps) {
    var n = zeroNutrients();
    for (final c in comps) {
      n = addNutrients(n, c.nutrients);
    }
    return {
      'slot': slot,
      'nutrients': _round(n),
      'components': [
        for (final c in comps)
          {
            'recipe_id': c.recipe.id,
            'name': c.name,
            'region': c.region,
            'nutrients': _round(c.nutrients),
            'ingredients': c.ingredients,
          }
      ],
    };
  }

  final bySlot = <String, List<Component>>{
    'breakfast': [if (bfC != null) bfC],
    'lunch': [if (lg != null) lg, if (lMainC != null) lMainC, if (lVegC != null) lVegC],
    'dinner': [if (dg != null) dg, if (dMainC != null) dMainC, if (dVegC != null) dVegC],
    'snack1': snackC.isNotEmpty ? [snackC[0]] : <Component>[],
    'snack2': snackC.length > 1 ? [snackC[1]] : <Component>[],
  };

  final entries = [for (final s in _slotOrder) entry(s, bySlot[s] ?? const [])];
  var totals = zeroNutrients();
  for (final e in entries) {
    totals = addNutrients(totals, (e['nutrients'] as Map).cast<String, double>());
  }

  return {
    'date': _iso(d),
    'member_id': '${member['id']}',
    'season': season,
    'totals': _round(totals),
    'entries': entries,
    'validation': _validate(totals, t, warnings),
  };
}

Component _grainComponent(KB kb, Recipe? grain, double kcalTarget) {
  if (grain == null) {
    return Component(
      const Recipe(id: 'none', name: '', role: 'grain', region: null, seasons: null,
          ingredients: [], addedSaltG: 0, hero: null, contains: {}, tags: {}),
      1, zeroNutrients(), const [],
    );
  }
  final base = makeComponent(kb, grain).nutrients['kcal'] ?? 0;
  final scale = base <= 0
      ? 1.0
      : math.max(_grainScaleBounds[0], math.min(_grainScaleBounds[1], kcalTarget / base));
  return makeComponent(kb, grain, scale);
}

Map<String, dynamic> _validate(
    Map<String, double> tot, Map<String, dynamic> t, List<String> warnings) {
  final warns = <String>[...warnings];
  final hard = <String>[];
  final tKcal = (t['kcal'] as num).toDouble();
  final tProt = (t['protein_g'] as num).toDouble();
  final tNa = (t['sodium_mg_max'] as num).toDouble();
  final tFib = (t['fibre_g'] as num).toDouble();

  final kcal = tot['kcal'] ?? 0, prot = tot['protein'] ?? 0;
  final na = tot['sodium'] ?? 0, fib = tot['fibre'] ?? 0;

  final kcalOk = kcal >= tKcal * (1 - _kcalTolerance) && kcal <= tKcal * (1 + _kcalTolerance);
  if (!kcalOk) {
    warns.add('Energy ${kcal.round()} kcal outside ±${(_kcalTolerance * 100).round()}% of ${tKcal.round()}');
  }
  final protOk = prot >= 0.9 * tProt;
  if (prot < 0.7 * tProt) {
    hard.add('Protein ${prot.round()} g well below target ${tProt.round()} g');
  } else if (!protOk) {
    warns.add('Protein ${prot.round()} g just under target ${tProt.round()} g — add a protein source');
  }
  final naOk = na <= tNa;
  if (!naOk) hard.add('Sodium ${na.round()} mg over limit ${tNa.round()} mg');
  final fibOk = fib >= 0.85 * tFib;

  final checks = {
    'kcal': [kcal.round(), tKcal.round(), kcalOk],
    'protein': [double.parse(prot.toStringAsFixed(1)), tProt.round(), protOk],
    'sodium': [na.round(), tNa.round(), naOk],
    'fibre': [double.parse(fib.toStringAsFixed(1)), tFib.round(), fibOk],
  };
  final passed = [kcalOk, protOk, naOk, fibOk].where((b) => b).length;
  var dqs = 60 + passed * 8 + (warns.isEmpty ? 8 : 0) + (hard.isEmpty ? 4 : 0);
  dqs = math.max(0, math.min(100, dqs));

  return {
    'in_tolerance': kcalOk && hard.isEmpty,
    'dqs': dqs,
    'checks': checks,
    'hard_violations': hard,
    'warnings': warns.toSet().toList(),
  };
}

Map<String, double> _round(Map<String, double> m) =>
    {for (final e in m.entries) e.key: double.parse(e.value.toStringAsFixed(1))};

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String isoDate(DateTime d) => _iso(d);
