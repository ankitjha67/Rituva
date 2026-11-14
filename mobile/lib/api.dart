import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine/kb.dart';
import 'engine/llm.dart';
import 'engine/local_engine.dart';

/// Raised only for the handful of things that genuinely cannot work without a server —
/// today that is live LLM chat. Everything else (planning, swaps, recipes, groceries,
/// analytics, profiles, logging) runs on-device via [LocalEngine].
class OfflineException implements Exception {
  final String feature;
  OfflineException([this.feature = 'This feature']);
  @override
  String toString() => '$feature needs a connected Rituva server (set it in Profile → Server).';
}

/// Thin client for the Rituva FastAPI backend. Every value returned here is
/// computed by the server — or, when no server is reachable, read from a bundled
/// demo built by the same deterministic engine — from the Knowledge DB. The app
/// never invents nutrition numbers.
///
/// If the configured backend is unreachable, read endpoints transparently fall
/// back to `assets/demo.json` and [offline] flips to true, so a freshly-installed
/// APK is usable with no backend at all.
class RituvaApi {
  static const _prefKey = 'rituva_server_url';
  static const _nvKeyPref = 'rituva_nvidia_key';
  // Emulator/simulator host aliases differ: the Android emulator reaches the host's
  // Standalone by default: no server unless one is baked at build
  // (`--dart-define=RITUVA_API=https://your-host`) or set in Profile. With no server the
  // whole app runs on the bundled Knowledge DB + on-device engine, and the assistant talks
  // to NVIDIA directly — nothing to connect, nothing to go wrong on launch.
  static final String _default = _resolveDefault();
  static String _resolveDefault() => String.fromEnvironment('RITUVA_API', defaultValue: '');

  // The NVIDIA key for the standalone LLM path (direct from the app, no server). Baked at
  // build via `--dart-define=RITUVA_NVIDIA_KEY=...`, overridable in Profile → Assistant.
  static const _bakedNvKey = String.fromEnvironment('RITUVA_NVIDIA_KEY', defaultValue: '');

  static const _timeout = Duration(seconds: 15);   // headroom for the LLM-bearing /plans call

  String baseUrl;
  String nvidiaKey = _bakedNvKey;
  bool offline = false;  // true once any call has fallen back to the on-device engine

  /// The on-device planner. Answers every read the app makes, using the bundled
  /// Knowledge DB (or a fuller one the user downloaded), so the app is fully usable
  /// with no server at all.
  final LocalEngine local = LocalEngine();

  RituvaApi._(this.baseUrl);

  /// Builds a client. The app is standalone — every read is computed on-device — so no
  /// server URL is restored; any one saved by an older build is cleared. (A developer can
  /// still point a build at the backend with `--dart-define=RITUVA_API=…`.) Restores the
  /// saved NVIDIA key and points the engine at a previously downloaded library if present.
  static Future<RituvaApi> create() async {
    var nvKey = _bakedNvKey;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefKey);   // standalone: drop any server URL a previous build saved
      final nv = p.getString(_nvKeyPref);
      if (nv != null && nv.trim().isNotEmpty) nvKey = nv.trim();
    } catch (_) {/* prefs unavailable → defaults */}
    try {
      final dir = await getApplicationDocumentsDirectory();
      KB.downloadPath = '${dir.path}/rituva_kb_full.json';
    } catch (_) {/* no writable dir → bundled KB only */}
    final api = RituvaApi._(_default);
    api.nvidiaKey = nvKey;
    return api;
  }

  /// Counts for the on-device library (bundled, or a previously downloaded snapshot).
  Future<Map<String, dynamic>> libraryInfo() => local.info();

  // ------------------------------------------------------- the assistant ----
  /// Whether the in-app LLM assistant can run (an NVIDIA key is configured). When true,
  /// the assistant works fully standalone — no backend server is involved.
  bool get hasLLM => nvidiaKey.trim().isNotEmpty;

  /// Persist the NVIDIA key (empty resets to the build-baked key, if any).
  Future<void> setNvidiaKey(String key) async {
    final v = key.trim();
    nvidiaKey = v.isEmpty ? _bakedNvKey : v;
    try {
      final p = await SharedPreferences.getInstance();
      v.isEmpty ? await p.remove(_nvKeyPref) : await p.setString(_nvKeyPref, v);
    } catch (_) {}
  }

  static const _assistantSystem =
      'You are Rituva, a warm, practical Indian nutrition assistant built into a meal-planning app. '
      "You are given the user's profile, health conditions, daily nutrient targets, their whole week's "
      'menu, and engine-computed EQUAL-NUTRIENT SWAP OPTIONS for the dishes in that menu. '
      'Hard rules: (1) Use ONLY the numbers and dish names given in the context — never invent a '
      'calorie or protein value, and never suggest a dish that is not listed in the menu or the swap '
      'options. (2) When the user wants a change (a different dish for a meal, fewer calories, more '
      'protein, etc.), name the specific day and meal, pick concrete dishes from the SWAP OPTIONS, and '
      'show the calorie/protein difference using the given numbers. (3) Respect their conditions — '
      'diabetes: prefer lower-calorie, higher-fibre, lower-GI choices; hypertension: lower sodium. '
      '(4) To cut calories, compare the menu to the daily target and recommend the few highest-impact '
      'swaps; you may also mention they can set their goal to "lose" in Edit Profile, which lowers the '
      'daily target by about 500 kcal. Keep replies short, specific and encouraging — a sentence or two, '
      'or a short bullet list. Never be preachy, and never output a nutrient number not in the context.';

  /// The intelligent assistant. Grounded in the member's profile, health, daily targets,
  /// the whole week's menu and engine-computed iso-nutrient alternatives for its dishes.
  /// The LLM reasons and suggests; every number and candidate dish is supplied by the
  /// deterministic engine, never invented by the model. Runs standalone via [NvidiaLLM].
  Future<String> assistant(
    String question, {
    required Map<String, dynamic> member,
    required Map<String, dynamic> targets,
    required Map<String, dynamic> plan,
    List<Map<String, String>> history = const [],
  }) async {
    if (!hasLLM) throw OfflineException('The assistant');
    final ctx = await _assistantContext(member, targets, plan);
    final convo = history.isEmpty
        ? ''
        : '\n\nEarlier in this chat:\n${history.map((m) => "${m['role'] == 'you' ? 'User' : 'You'}: ${m['text']}").join('\n')}';
    final user = '$ctx$convo\n\nUser: $question';
    // Per-model timeout. The free-tier survivor (gpt-oss-20b, a reasoning model) can take
    // ~50s on a big prompt; retired models fail in 0.1s (HTTP 410) so they cost nothing to
    // skip, which keeps the walk fast despite the long cap. Winner cache ⇒ one attempt next time.
    return NvidiaLLM(nvidiaKey).chat(_assistantSystem, user, timeout: const Duration(seconds: 60));
  }

  /// Build the grounded context block: who the member is, their targets, the week's menu,
  /// and a bounded set of engine-computed equal-nutrient swap options for its dishes.
  Future<String> _assistantContext(
      Map<String, dynamic> member, Map<String, dynamic> targets, Map<String, dynamic> plan) async {
    final b = StringBuffer();
    num tg(String k) => (targets[k] as num?) ?? 0;
    final conds = ((member['conditions'] as List?) ?? const []).join(', ');
    b.writeln('MEMBER: ${member['name']} · ${member['sex']} · age ${member['age']} · '
        '${member['weight_kg']}kg / ${member['height_cm']}cm · goal ${member['goal']} · '
        'diet ${member['diet_type']}${conds.isEmpty ? '' : ' · conditions: $conds'}.');
    b.writeln('DAILY TARGETS: ${tg('kcal').round()} kcal, protein ${tg('protein_g').round()} g, '
        'carb ${tg('carb_g').round()} g, fat ${tg('fat_g').round()} g, fibre ${tg('fibre_g').round()} g, '
        'sodium <= ${tg('sodium_mg_max').round()} mg, added sugar <= ${tg('added_sugar_g_max').round()} g, '
        'iron ${tg('iron_mg')} mg, calcium ${tg('calcium_mg').round()} mg, B12 ${tg('b12_ug')} ug.');

    final days = (plan['days'] as List?) ?? const [];
    final uniqueDishes = <String, String>{}; // recipe_id -> name
    b.writeln('\nTHIS WEEK (date | meal | dishes | kcal | protein g):');
    for (final d in days) {
      final date = '${d['date']}';
      for (final e in ((d['entries'] as List?) ?? const [])) {
        final comps = (e['components'] as List?) ?? const [];
        if (comps.isEmpty) continue;
        final names = comps.map((c) => '${c['name']}').join(' + ');
        final n = (e['nutrients'] as Map?) ?? const {};
        b.writeln('  $date | ${e['slot']} | $names | '
            '${(n['kcal'] as num?)?.round() ?? '?'} | ${(n['protein'] as num?)?.round() ?? '?'}');
        for (final c in comps) {
          final rid = '${c['recipe_id'] ?? ''}';
          if (rid.isNotEmpty) uniqueDishes.putIfAbsent(rid, () => '${c['name']}');
        }
      }
    }

    final anchorDay = days.isNotEmpty ? '${days.first['date']}' : '';
    final mid = '${member['id']}';
    b.writeln('\nSWAP OPTIONS (engine-computed equal-nutrient alternatives — suggest ONLY these):');
    var budget = 6; // bound the on-device work + context size (keeps the prompt small/fast)
    for (final entry in uniqueDishes.entries) {
      if (budget-- <= 0) break;
      try {
        final res = await alternatives(mid, entry.key, anchorDay);
        final alts = (res['alternatives'] as List?) ?? const [];
        if (alts.isEmpty) continue;
        final line = alts.take(3).map((a) {
          final an = (a['nutrients'] as Map?) ?? const {};
          return '${a['name']} (${(an['kcal'] as num?)?.round() ?? '?'} kcal, '
              '${(an['protein'] as num?)?.round() ?? '?'} g protein)';
        }).join('; ');
        b.writeln('  instead of ${entry.value}: $line');
      } catch (_) {/* no alternatives for this dish → skip */}
    }
    return b.toString();
  }

  // ---------------------------------------------------------------- HTTP ----
  Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse('$baseUrl$path')
      .replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  Future<dynamic> _get(String path, [Map<String, dynamic>? q]) async {
    final r = await http.get(_u(path, q)).timeout(_timeout);
    if (r.statusCode >= 400) throw Exception('GET $path → ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(_timeout);
    if (r.statusCode >= 400) throw Exception('POST $path → ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Future<void> _delete(String path, Map<String, dynamic> q) async {
    final r = await http.delete(_u(path, q)).timeout(_timeout);
    if (r.statusCode >= 400) throw Exception('DELETE $path → ${r.statusCode}');
  }

  /// Whether an error means "the network/server is down" (→ fall back to demo)
  /// as opposed to a real server-side error (→ surface it).
  bool _isNet(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is http.ClientException;

  // ------------------------------------------- endpoints (live → on-device) ----
  // Each read tries the server first and falls back to [local], the on-device
  // deterministic engine. The fallback is not a frozen sample any more: it plans,
  // validates, swaps and costs out groceries from the Knowledge DB on the phone, so
  // "offline" means "computed here", not "degraded".

  /// Whether an optional backend server is configured (only via a dev `--dart-define`;
  /// there is no in-app setting). When false — the default — the app is fully standalone:
  /// every read is computed on-device and nothing touches the network.
  bool get hasServer => baseUrl.trim().isNotEmpty;

  /// Run everything on-device even when a server is reachable.
  bool preferOffline = false;

  bool get _useLocal => offline || preferOffline || !hasServer;

  Future<T> _tryServer<T>(Future<T> Function() remote, Future<T> Function() fallback) async {
    if (_useLocal) return fallback();
    try {
      final v = await remote();
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        return fallback();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> context() async =>
      _tryServer(() async => await _get('/context') as Map<String, dynamic>,
          () async => _localContext());

  Future<List> members() async =>
      _tryServer(() async => await _get('/members') as List, () => local.members());

  Future<Map<String, dynamic>> member(String id) async => _tryServer(
      () async => await _get('/members/$id') as Map<String, dynamic>,
      () => local.member(id));

  Future<Map<String, dynamic>> targets(String id) async => _tryServer(
      () async => await _get('/members/$id/targets') as Map<String, dynamic>,
      () => local.targets(id));

  Future<Map<String, dynamic>> createPlan(String id,
          {int days = 7, String? start, int variant = 0}) async =>
      _tryServer(
        () async => await _post('/plans', {
          'member_id': id,
          'days': days,
          'variant': variant,
          if (start != null) 'start': start,
        }) as Map<String, dynamic>,
        () => local.createPlan(id, days: days, start: start, variant: variant),
      );

  /// Grocery list. Offline needs the plan itself (the server looks it up by id), so
  /// callers pass the plan they already hold.
  Future<Map<String, dynamic>> grocery(String planId,
          {int people = 2, Map<String, dynamic>? plan}) async =>
      _tryServer(
        () async =>
            await _get('/plans/$planId/grocery', {'people': people}) as Map<String, dynamic>,
        () async => plan == null
            ? throw OfflineException('The grocery list')
            : await local.grocery(plan, people: people),
      );

  Future<Map<String, dynamic>> alternatives(String id, String recipeId, String day) async =>
      _tryServer(
        () async => await _get('/members/$id/alternatives',
            {'recipe_id': recipeId, 'day': day}) as Map<String, dynamic>,
        () => local.alternatives(id, recipeId),
      );

  /// Browse the dish library (Discover).
  Future<List> recipes({String? region, String? role}) async => _tryServer(
        () async {
          final v = await _get('/recipes', {
            if (region != null) 'region': region,
            if (role != null) 'role': role,
          }) as Map<String, dynamic>;
          return v['recipes'] as List;
        },
        () => local.recipes(region: region, role: role),
      );

  /// Full recipe card: DB ingredients, cooking method, chef videos.
  Future<Map<String, dynamic>> recipe(String recipeId, {bool llm = true}) async => _tryServer(
        () async =>
            await _get('/recipes/$recipeId', {if (llm) 'llm': 1}) as Map<String, dynamic>,
        () => local.recipe(recipeId),
      );

  /// ICMR-NIN daily requirements by life stage + deficiency disorders.
  Future<Map<String, dynamic>> reference({String? memberId}) async => _tryServer(
        () async => await _get('/reference/rda',
            {if (memberId != null) 'member_id': memberId}) as Map<String, dynamic>,
        () => local.reference(memberId: memberId),
      );

  Future<Map<String, dynamic>> memory(String id) async => _tryServer(
      () async => await _get('/members/$id/memory') as Map<String, dynamic>,
      () => local.memory(id));

  Future<void> addMemory(String id, String kind, String value) async => _tryServer(
      () async => await _post('/members/$id/memory', {'kind': kind, 'value': value}),
      () => local.addMemory(id, kind, value));

  Future<void> removeMemory(String id, String kind, String value) async => _tryServer(
      () async => await _delete('/members/$id/memory', {'kind': kind, 'value': value}),
      () => local.removeMemory(id, kind, value));

  Future<Map<String, dynamic>> adherence(String id, String day, String planId,
          {Map<String, dynamic>? plan}) async =>
      _tryServer(
        () async => await _get('/members/$id/adherence', {'date': day, 'plan_id': planId})
            as Map<String, dynamic>,
        () => local.adherence(id, day, plan),
      );

  /// Log a day's dishes as eaten (each recipe expands to its ingredients for the totals).
  Future<void> logDayAsEaten(String id, String day, List<String> recipeIds) async =>
      _tryServer(
        () async => await _post('/members/$id/intake', {
          'date': day,
          'items': [for (final r in recipeIds) {'recipe_id': r, 'scale': 1.0}],
        }),
        () => local.logDayAsEaten(id, day, recipeIds),
      );

  /// Create or update a member profile (upsert by id), on the server or on the device.
  Future<Map<String, dynamic>> saveMember(Map<String, dynamic> m) async => _tryServer(
        () async => await _post('/members', m) as Map<String, dynamic>,
        () => local.saveMember(m),
      );

  /// Delete a member profile by id, on the server or on the device.
  Future<void> deleteMember(String id) async => _tryServer(
        () async => _delete('/members/$id', const {}),
        () => local.deleteMember(id),
      );

  /// Ask the LLM about a day's meals. The one genuinely server-only feature: running a
  /// language model needs the backend, and the app will not fake an answer offline.
  Future<String> ask(String id, String question, {String? planId, String? date}) async {
    if (_useLocal) throw OfflineException('The meal assistant');
    try {
      final v = await _post('/members/$id/ask', {
        'question': question,
        if (planId != null) 'plan_id': planId,
        if (date != null) 'date': date,
      }) as Map<String, dynamic>;
      offline = false;
      return '${v['answer'] ?? ''}';
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('The meal assistant');
      }
      rethrow;
    }
  }

  // ---------------------------------- offline system context (mirrors context.py) ----
  Map<String, dynamic> _localContext() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final h = now.hour;
    final greeting = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : h < 21
                ? 'Good evening'
                : 'Good night';
    final m = now.month;
    final season = (m == 12 || m <= 2)
        ? 'winter'
        : (m <= 4)
            ? 'spring'
            : (m <= 6)
                ? 'summer'
                : 'monsoon'; // Jul–Nov
    final mins = now.hour * 60 + now.minute;
    final slot = mins < 630
        ? 'breakfast'
        : mins < 750
            ? 'snack1'
            : mins < 930
                ? 'lunch'
                : mins < 1140
                    ? 'snack2'
                    : mins < 1380
                        ? 'dinner'
                        : 'breakfast';
    return {
      'today': '${now.year}-${two(m)}-${two(now.day)}',
      'time': '${two(now.hour)}:${two(now.minute)}',
      'season': season,
      'current_slot': slot,
      'greeting': greeting,
    };
  }
}
