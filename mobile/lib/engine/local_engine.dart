import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'cooking.dart' as cook;
import 'kb.dart';
import 'planner.dart';

/// The offline brain. Answers exactly the shapes the Rituva API returns, so every screen
/// works identically whether the data came from a server or from here.
///
/// What it does NOT do is pretend to be an LLM. Menus, nutrients, swaps, groceries and
/// cooking methods are all deterministic and computed on-device from the Knowledge DB.
/// Recipe prose written by a real model is only shown when it was generated earlier and
/// travelled with a downloaded library — never invented on the phone.
class LocalEngine {
  static const _membersKey = 'rituva_local_members';
  static const _memoryKey = 'rituva_local_memory';
  static const _intakeKey = 'rituva_local_intake';

  KB? _kb;
  Future<KB> kb() async => _kb ??= await KB.load();

  /// Reload after a library download so the new dishes appear immediately.
  Future<void> refreshKb() async {
    KB.invalidate();
    _kb = null;
    await kb();
  }

  Future<bool> get isFullLibrary async => (await kb()).isFull;

  Future<Map<String, dynamic>> info() async {
    final k = await kb();
    return {
      'foods': k.foods.length,
      'recipes': k.recipes.length,
      'kb': k.version,
      'full': k.isFull,
    };
  }

  /// RDA tables + deficiency disorders, with the row matching this member flagged.
  Future<Map<String, dynamic>> reference({String? memberId}) async {
    final k = await kb();
    final out = Map<String, dynamic>.from(k.rda);
    if (memberId != null && out['groups'] is List) {
      final m = await member(memberId);
      out['matched'] = _matchGroup(
          out['groups'] as List, '${m['sex'] ?? 'M'}',
          (m['age'] as num?)?.toInt() ?? 30, (m['pal'] as num?)?.toDouble() ?? 1.4);
    }
    return out;
  }

  /// Mirrors rda.for_member() — pick the life-stage row that fits this person.
  Map<String, dynamic>? _matchGroup(List groups, String sex, int age, double pal) {
    final stage = pal < 1.45 ? 'Sedentary work' : (pal < 1.7 ? 'Moderate work' : 'Heavy work');
    late String g, s;
    if (age < 1) {
      g = 'Infant';
      s = '6-12 months';
    } else if (age <= 3) {
      g = 'Child';
      s = '1-3 years';
    } else if (age <= 6) {
      g = 'Child';
      s = '4-6 years';
    } else if (age <= 9) {
      g = 'Child';
      s = '7-9 years';
    } else if (age <= 12) {
      g = sex == 'M' ? 'Boy' : 'Girl';
      s = '10-12 years';
    } else if (age <= 15) {
      g = sex == 'M' ? 'Boy' : 'Girl';
      s = '13-15 years';
    } else if (age <= 17) {
      g = sex == 'M' ? 'Boy' : 'Girl';
      s = '16-17 years';
    } else {
      g = sex == 'M' ? 'Man' : 'Woman';
      s = stage;
    }
    for (final r in groups) {
      if (r['group'] == g && r['stage'] == s) return (r as Map).cast<String, dynamic>();
    }
    return null;
  }

  // ------------------------------------------------------------- members ----
  Future<List> members() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_membersKey);
    if (saved != null && saved.isNotEmpty) {
      try {
        return jsonDecode(saved) as List;
      } catch (_) {/* corrupt -> seed */}
    }
    final seeded = (await kb()).members;
    await p.setString(_membersKey, jsonEncode(seeded));
    return seeded;
  }

  Future<Map<String, dynamic>> member(String id) async {
    final all = await members();
    return (all.firstWhere((m) => m['id'] == id, orElse: () => all.first))
        as Map<String, dynamic>;
  }

  /// Create or update a profile, on device. Same upsert-by-id semantics as the server.
  Future<Map<String, dynamic>> saveMember(Map<String, dynamic> m) async {
    final p = await SharedPreferences.getInstance();
    final all = [...await members()];
    final i = all.indexWhere((x) => x['id'] == m['id']);
    if (i >= 0) {
      all[i] = m;
    } else {
      all.add(m);
    }
    await p.setString(_membersKey, jsonEncode(all));
    return m;
  }

  Future<Map<String, dynamic>> targets(String id) async =>
      computeTargets(await member(id));

  // ---------------------------------------------------------------- plan ----
  Future<Map<String, dynamic>> createPlan(String id,
      {int days = 7, String? start, int variant = 0}) async {
    final k = await kb();
    final m = await member(id);
    final tr = computeTargets(m);
    final t = (tr['targets'] as Map).cast<String, dynamic>();
    final startDate = start != null ? DateTime.parse(start) : DateTime.now();

    // Long-term memory ("never" / "dislike") narrows the pool, same as the server.
    final mem = await memory(id);
    final blocked = <String>{
      ...(((mem['memory'] as Map)['never'] as List?) ?? const []).map((e) => '$e'),
      ...(((mem['memory'] as Map)['dislike'] as List?) ?? const []).map((e) => '$e'),
    };
    final effective = {
      ...m,
      'excludes': [...((m['excludes'] as List?) ?? const []), ...blocked],
    };

    final dayList = planDays(k, effective, t, startDate, days, variant: variant);
    final onTarget = dayList.where((d) => d['validation']['in_tolerance'] == true).length;
    final avgDqs = dayList.isEmpty
        ? 0
        : (dayList.fold<int>(0, (a, d) => a + (d['validation']['dqs'] as int)) / dayList.length)
            .round();

    return {
      'plan_id': 'local-${startDate.millisecondsSinceEpoch}-$variant',
      'member_id': id,
      'start': isoDate(startDate),
      'days_count': days,
      'targets': t,
      'days': dayList,
      'summary': {'on_target': onTarget, 'avg_dqs': avgDqs},
      'explanation': _explain(m, dayList, t),
      'provenance': {
        'kb': k.version,
        'llm_provider': 'offline',
        'engine': 'on-device deterministic planner',
        'citations': [
          {
            'text': 'Half the plate vegetables and fruit; prefer whole grains and pulses.',
            'source': 'DGI 2024',
            'display': 'Dietary Guidelines for Indians 2024',
          }
        ],
      },
    };
  }

  /// A plain-language summary of the week. Written from the computed plan, and labelled
  /// as offline so it is never mistaken for the model-written line the server produces.
  String _explain(Map member, List<Map<String, dynamic>> days, Map<String, dynamic> t) {
    if (days.isEmpty) return '';
    final name = '${member['name'] ?? 'there'}';
    final avgKcal =
        (days.fold<double>(0, (a, d) => a + (d['totals']['kcal'] as num).toDouble()) / days.length)
            .round();
    final avgProt =
        (days.fold<double>(0, (a, d) => a + (d['totals']['protein'] as num).toDouble()) / days.length)
            .round();
    final onTarget = days.where((d) => d['validation']['in_tolerance'] == true).length;
    final dishes = <String>{};
    for (final d in days) {
      for (final e in (d['entries'] as List)) {
        for (final c in (e['components'] as List)) {
          dishes.add('${c['name']}');
        }
      }
    }
    return 'Planned on your phone for $name: $avgKcal kcal and ${avgProt}g protein a day on '
        'average, $onTarget of ${days.length} days inside the energy window, and '
        '${dishes.length} different dishes across the week so nothing gets repetitive.';
  }

  // ------------------------------------------------------------- recipes ----
  Future<List> recipes({String? region, String? role, String? diet}) async {
    final k = await kb();
    final out = [];
    for (final r in k.recipes.values) {
      if (region != null && (r.region ?? '') != region) continue;
      if (role != null && r.role != role) continue;
      final lab = dietLabels(k, r);
      if (diet != null && !lab.contains(diet)) continue;
      final n = makeComponent(k, r).nutrients;
      out.add({
        'id': r.id,
        'name': r.name,
        'region': r.region,
        'role': r.role,
        'diet': lab.toList()..sort(),
        'kcal': (n['kcal'] ?? 0).round(),
        'protein': double.parse((n['protein'] ?? 0).toStringAsFixed(1)),
      });
    }
    return out;
  }

  Future<Map<String, dynamic>> recipe(String id, {double scale = 1.0}) async {
    final k = await kb();
    final r = k.recipes[id];
    if (r == null) throw Exception('recipe not found offline');
    final comp = makeComponent(k, r, scale);
    final m = cook.method(k, r);

    // Prose written by a real model earlier (it travels with a downloaded library). If
    // it's absent we show the deterministic method — we never fabricate it on-device.
    final pre = k.llmRecipes[id];
    if (pre is Map) {
      m['intro'] = '${pre['intro'] ?? ''}';
      final s = (pre['steps'] as List?)?.map((e) => '$e').toList();
      if (s != null && s.isNotEmpty) m['steps'] = s;
      m['tips'] = (pre['tips'] as List?)?.map((e) => '$e').toList() ?? <String>[];
      m['source'] = '${pre['source'] ?? 'llm'} (cached offline)';
    }

    return {
      'id': r.id,
      'name': r.name,
      'role': r.role,
      'region': r.region,
      'diet': dietLabels(k, r).toList()..sort(),
      'tags': r.tags.toList()..sort(),
      'method': m,
      'videos': cook.videoLinks(k, r),
      'nutrients': {
        for (final e in comp.nutrients.entries)
          e.key: double.parse(e.value.toStringAsFixed(1))
      },
      'ingredients': comp.ingredients,
      'scale': scale,
    };
  }

  /// Iso-nutrient swaps: dishes in the same role closest on the macro vector.
  Future<Map<String, dynamic>> alternatives(String memberId, String recipeId) async {
    final k = await kb();
    final target = k.recipes[recipeId];
    if (target == null) throw Exception('dish not found offline');
    final m = await member(memberId);
    final orig = makeComponent(k, target).nutrients;

    const keys = ['kcal', 'protein', 'carb', 'fat', 'fibre'];
    const scaleBy = {'kcal': 400.0, 'protein': 25.0, 'carb': 50.0, 'fat': 20.0, 'fibre': 12.0};
    double dist(Map<String, double> a) {
      var s = 0.0;
      for (final key in keys) {
        final d = ((a[key] ?? 0) - (orig[key] ?? 0)) / scaleBy[key]!;
        s += d * d;
      }
      return math.sqrt(s);
    }

    final pool = k.recipes.values
        .where((r) => r.role == target.role && r.id != recipeId && dietOk(k, r, m))
        .map((r) => MapEntry(r, makeComponent(k, r).nutrients))
        .toList()
      ..sort((a, b) => dist(a.value).compareTo(dist(b.value)));

    // Full shape, matching the server's /alternatives: recipe_id + all nutrients + the
    // ingredient BOM, so a tap-to-swap can replace the dish and recompute totals/grocery.
    final out = <Map<String, dynamic>>[];
    for (final e in pool.take(3)) {
      final comp = makeComponent(k, e.key);
      out.add({
        'recipe_id': e.key.id,
        'id': e.key.id,
        'name': e.key.name,
        'region': e.key.region,
        'nutrients': {
          for (final kk in comp.nutrients.keys)
            kk: double.parse((comp.nutrients[kk] ?? 0).toStringAsFixed(1))
        },
        'ingredients': comp.ingredients,
        'delta': _delta(e.value, orig),
      });
    }
    return {'declined': {'name': target.name}, 'alternatives': out};
  }

  String _delta(Map<String, double> alt, Map<String, double> orig) {
    final dk = ((alt['kcal'] ?? 0) - (orig['kcal'] ?? 0)).round();
    final dp = (alt['protein'] ?? 0) - (orig['protein'] ?? 0);
    final parts = ['${dk >= 0 ? '+' : ''}$dk kcal'];
    if (dp.abs() >= 0.5) {
      parts.add('${dp >= 0 ? '+' : ''}${dp.toStringAsFixed(1)} g protein');
    }
    return parts.join(' · ');
  }

  /// Shopping list: every ingredient across the plan, summed and grouped by aisle.
  Future<Map<String, dynamic>> grocery(Map<String, dynamic> plan, {int people = 2}) async {
    final k = await kb();
    final totals = <String, double>{};
    for (final d in (plan['days'] as List? ?? const [])) {
      for (final e in (d['entries'] as List)) {
        for (final c in (e['components'] as List)) {
          for (final ing in ((c['ingredients'] as List?) ?? const [])) {
            final id = '${ing['food_id']}';
            totals[id] = (totals[id] ?? 0) + ((ing['qty_g'] as num?)?.toDouble() ?? 0) * people;
          }
        }
      }
    }
    final byCat = <String, List<Map<String, dynamic>>>{};
    for (final e in totals.entries) {
      final f = k.foods[e.key];
      if (f == null) continue;
      final qty = e.value;
      (byCat[f.group] ??= []).add({
        'item': f.name,
        'quantity': qty >= 1000
            ? double.parse((qty / 1000).toStringAsFixed(2))
            : qty.round(),
        'unit': qty >= 1000 ? 'kg' : 'g',
      });
    }
    final cats = byCat.keys.toList()..sort();
    return {
      'total_items': totals.length,
      'people': people,
      'categories': [
        for (final c in cats)
          {
            'category': c,
            'items': (byCat[c]!..sort((a, b) => '${a['item']}'.compareTo('${b['item']}')))
          }
      ],
    };
  }

  // -------------------------------------------------------------- memory ----
  Future<Map<String, dynamic>> memory(String id) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('${_memoryKey}_$id');
    final mem = raw == null
        ? {'never': [], 'dislike': [], 'like': []}
        : (jsonDecode(raw) as Map).cast<String, dynamic>();
    return {'member_id': id, 'memory': mem};
  }

  Future<void> addMemory(String id, String kind, String value) async {
    final p = await SharedPreferences.getInstance();
    final mem = (await memory(id))['memory'] as Map;
    final list = ((mem[kind] as List?) ?? []).map((e) => '$e').toList();
    if (!list.contains(value)) list.add(value);
    mem[kind] = list;
    await p.setString('${_memoryKey}_$id', jsonEncode(mem));
  }

  Future<void> removeMemory(String id, String kind, String value) async {
    final p = await SharedPreferences.getInstance();
    final mem = (await memory(id))['memory'] as Map;
    final list = ((mem[kind] as List?) ?? []).map((e) => '$e').toList()..remove(value);
    mem[kind] = list;
    await p.setString('${_memoryKey}_$id', jsonEncode(mem));
  }

  // ---------------------------------------------------- logging & adherence ----
  Future<void> logDayAsEaten(String id, String day, List<String> recipeIds) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_intakeKey}_${id}_$day', jsonEncode(recipeIds));
  }

  /// Actual vs planned vs target, summed from the DB for whatever was logged.
  Future<Map<String, dynamic>> adherence(
      String id, String day, Map<String, dynamic>? plan) async {
    final k = await kb();
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('${_intakeKey}_${id}_$day');
    final ids = raw == null ? <String>[] : (jsonDecode(raw) as List).map((e) => '$e').toList();

    var actual = zeroNutrients();
    for (final rid in ids) {
      final r = k.recipes[rid];
      if (r != null) actual = addNutrients(actual, makeComponent(k, r).nutrients);
    }

    Map<String, double>? planned;
    if (plan != null) {
      for (final d in (plan['days'] as List? ?? const [])) {
        if (d['date'] == day) {
          planned = (d['totals'] as Map).map((key, v) => MapEntry('$key', (v as num).toDouble()));
        }
      }
    }

    final t = (await targets(id))['targets'] as Map<String, dynamic>;
    const rows = [
      ['kcal', 'kcal', 'kcal'],
      ['protein', 'protein_g', 'g'],
      ['fibre', 'fibre_g', 'g'],
      ['iron', 'iron_mg', 'mg'],
      ['calcium', 'calcium_mg', 'mg'],
    ];
    final per = <Map<String, dynamic>>[];
    var hit = 0;
    for (final r in rows) {
      final a = actual[r[0]] ?? 0;
      final tgt = (t[r[1]] as num?)?.toDouble() ?? 0;
      final pct = tgt <= 0 ? 0.0 : (a / tgt * 100);
      if (pct >= 90 && pct <= 120) hit++;
      per.add({
        'nutrient': r[0],
        'actual': double.parse(a.toStringAsFixed(1)),
        'target': tgt.round(),
        'unit': r[2],
        'planned': planned == null
            ? null
            : double.parse((planned[r[0]] ?? 0).toStringAsFixed(1)),
        'pct_of_target': double.parse(pct.toStringAsFixed(1)),
      });
    }
    return {
      'member_id': id,
      'date': day,
      'score': ids.isEmpty ? 0 : (hit / rows.length * 100).round(),
      'per_nutrient': per,
    };
  }
}
