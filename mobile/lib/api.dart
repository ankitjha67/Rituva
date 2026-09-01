import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine/kb.dart';
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
  // Emulator/simulator host aliases differ: the Android emulator reaches the host's
  // localhost at 10.0.2.2, while the iOS simulator (and desktop) use localhost.
  // A CI-baked `--dart-define=RITUVA_API=https://your-host` overrides both.
  static final String _default = _resolveDefault();
  static String _resolveDefault() {
    const baked = String.fromEnvironment('RITUVA_API', defaultValue: '');
    if (baked.isNotEmpty) return baked;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  static const _timeout = Duration(seconds: 15);   // headroom for the LLM-bearing /plans call

  String baseUrl;
  bool offline = false;  // true once any call has fallen back to the on-device engine

  /// The on-device planner. Answers every read the app makes, using the bundled
  /// Knowledge DB (or a fuller one the user downloaded), so the app is fully usable
  /// with no server at all.
  final LocalEngine local = LocalEngine();

  RituvaApi._(this.baseUrl);

  /// Builds a client, restoring a user-saved server URL if one exists, and pointing the
  /// engine at a previously downloaded library if there is one.
  static Future<RituvaApi> create() async {
    var url = _default;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_prefKey);
      if (saved != null && saved.trim().isNotEmpty) url = saved.trim();
    } catch (_) {/* prefs unavailable → default */}
    try {
      final dir = await getApplicationDocumentsDirectory();
      KB.downloadPath = '${dir.path}/rituva_kb_full.json';
    } catch (_) {/* no writable dir → bundled KB only */}
    return RituvaApi._(url);
  }

  /// Pull the server's full Knowledge DB onto the device for offline use.
  ///
  /// This is how the personal-use IFCT library reaches the phone without ever entering
  /// the repo or an APK: it moves from the user's own machine to the user's own device.
  /// Returns a short summary of what landed.
  Future<Map<String, dynamic>> downloadLibrary() async {
    final path = KB.downloadPath;
    if (path == null) throw Exception('No writable storage on this device.');
    final r = await http.get(_u('/kb/export')).timeout(const Duration(seconds: 60));
    if (r.statusCode >= 400) throw Exception('GET /kb/export → ${r.statusCode}');
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final foods = (body['foods'] as List?)?.length ?? 0;
    final recipes = (body['recipes'] as List?)?.length ?? 0;
    if (foods == 0 || recipes == 0) throw Exception('Server returned an empty library.');
    await File(path).writeAsString(r.body);
    await local.refreshKb();
    return {'foods': foods, 'recipes': recipes,
            'llm_recipes': (body['llm_recipes'] as Map?)?.length ?? 0};
  }

  /// Forget a downloaded library and fall back to the bundled one.
  Future<void> clearLibrary() async {
    final path = KB.downloadPath;
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
    await local.refreshKb();
  }

  Future<Map<String, dynamic>> libraryInfo() => local.info();

  static String get defaultUrl => _default;
  bool get isDefaultUrl => baseUrl == _default;

  /// Persists a new backend URL (empty string resets to the default).
  Future<void> setBaseUrl(String url) async {
    final v = url.trim();
    baseUrl = v.isEmpty ? _default : v;
    try {
      final p = await SharedPreferences.getInstance();
      v.isEmpty ? await p.remove(_prefKey) : await p.setString(_prefKey, v);
    } catch (_) {}
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

  /// Fast reachability probe — sets [offline] so subsequent calls go straight to the
  /// local engine instead of each waiting out the full timeout.
  Future<bool> reachable() async {
    try {
      final r = await http.get(_u('/health')).timeout(const Duration(seconds: 3));
      offline = r.statusCode >= 400;
      return !offline;
    } catch (_) {
      offline = true;
      return false;
    }
  }

  /// Run everything on-device even when a server is reachable.
  bool preferOffline = false;

  bool get _useLocal => offline || preferOffline;

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

  String exportUrl(String planId, {int people = 2}) =>
      '$baseUrl/plans/$planId/export.xlsx?people=$people';
  String exportPdfUrl(String planId, {int people = 2}) =>
      '$baseUrl/plans/$planId/export.pdf?people=$people';

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
