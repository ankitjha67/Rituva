import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Raised when a server-only feature (swap, save preference) is used while the
/// app is running on the bundled offline demo.
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

  static const _timeout = Duration(seconds: 4);

  String baseUrl;
  bool offline = false; // true once any call has fallen back to the demo bundle
  Map<String, dynamic>? _demo;

  RituvaApi._(this.baseUrl);

  /// Builds a client, restoring a user-saved server URL if one exists.
  static Future<RituvaApi> create() async {
    var url = _default;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_prefKey);
      if (saved != null && saved.trim().isNotEmpty) url = saved.trim();
    } catch (_) {/* prefs unavailable → default */}
    return RituvaApi._(url);
  }

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

  // -------------------------------------------------------- demo bundle ----
  Future<Map<String, dynamic>> _bundle() async {
    _demo ??= jsonDecode(await rootBundle.loadString('assets/demo.json')) as Map<String, dynamic>;
    return _demo!;
  }

  Map<String, dynamic> _member(Map<String, dynamic> b, String id) {
    final bm = b['byMember'] as Map<String, dynamic>;
    return (bm[id] ?? bm['aarav']) as Map<String, dynamic>;
  }

  // ------------------------------------------------ endpoints (live→demo) ----
  /// Fast reachability probe (2 s) — sets [offline] so the subsequent read calls
  /// short-circuit to the bundled demo instead of each waiting out the full timeout.
  /// This keeps startup snappy when a configured server is unreachable.
  Future<bool> reachable() async {
    try {
      final r = await http.get(_u('/health')).timeout(const Duration(seconds: 2));
      offline = r.statusCode >= 400;
      return !offline;
    } catch (_) {
      offline = true;
      return false;
    }
  }

  Future<Map<String, dynamic>> context() async {
    if (offline) return _localContext();
    try {
      final v = await _get('/context') as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        return _localContext();
      }
      rethrow;
    }
  }

  Future<List> members() async {
    if (offline) return (await _bundle())['members'] as List;
    try {
      final v = await _get('/members') as List;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        return (await _bundle())['members'] as List;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> member(String id) async {
    if (offline) {
      final ms = (await _bundle())['members'] as List;
      return ms.firstWhere((m) => m['id'] == id, orElse: () => ms.first) as Map<String, dynamic>;
    }
    try {
      final v = await _get('/members/$id') as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        final ms = (await _bundle())['members'] as List;
        return ms.firstWhere((m) => m['id'] == id, orElse: () => ms.first) as Map<String, dynamic>;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> targets(String id) async {
    if (offline) return _member(await _bundle(), id)['targets'] as Map<String, dynamic>;
    try {
      final v = await _get('/members/$id/targets') as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        return _member(await _bundle(), id)['targets'] as Map<String, dynamic>;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createPlan(String id, {int days = 7, String? start}) async {
    if (offline) return _member(await _bundle(), id)['plan'] as Map<String, dynamic>;
    try {
      final v = await _post('/plans', {'member_id': id, 'days': days, if (start != null) 'start': start})
          as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        return _member(await _bundle(), id)['plan'] as Map<String, dynamic>;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> grocery(String planId, {int people = 2}) async {
    try {
      final v = await _get('/plans/$planId/grocery', {'people': people}) as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        final bm = (await _bundle())['byMember'] as Map<String, dynamic>;
        for (final v in bm.values) {
          if ((v['plan'] as Map)['plan_id'] == planId) return v['grocery'] as Map<String, dynamic>;
        }
        return (bm['aarav'] as Map)['grocery'] as Map<String, dynamic>;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> alternatives(String id, String recipeId, String day) async {
    try {
      final v = await _get('/members/$id/alternatives', {'recipe_id': recipeId, 'day': day})
          as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('Swapping dishes');
      }
      rethrow;
    }
  }

  /// Browse the dish library (Discover). Server-only (throws offline).
  Future<List> recipes({String? region, String? role}) async {
    try {
      final v = await _get('/recipes',
              {if (region != null) 'region': region, if (role != null) 'role': role})
          as Map<String, dynamic>;
      offline = false;
      return v['recipes'] as List;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('Browsing all dishes');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> memory(String id) async {
    try {
      final v = await _get('/members/$id/memory') as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        return {
          'member_id': id,
          'memory': {'never': [], 'dislike': [], 'like': []},
        };
      }
      rethrow;
    }
  }

  Future<void> addMemory(String id, String kind, String value) async {
    try {
      await _post('/members/$id/memory', {'kind': kind, 'value': value});
      offline = false;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('Saving preferences');
      }
      rethrow;
    }
  }

  Future<void> removeMemory(String id, String kind, String value) async {
    try {
      await _delete('/members/$id/memory', {'kind': kind, 'value': value});
      offline = false;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('Saving preferences');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> adherence(String id, String day, String planId) async {
    try {
      final v = await _get('/members/$id/adherence', {'date': day, 'plan_id': planId})
          as Map<String, dynamic>;
      offline = false;
      return v;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('Logging & adherence');
      }
      rethrow;
    }
  }

  /// Log a day's dishes as eaten (each recipe expands to its ingredient BOM server-side).
  Future<void> logDayAsEaten(String id, String day, List<String> recipeIds) async {
    try {
      await _post('/members/$id/intake', {
        'date': day,
        'items': [for (final r in recipeIds) {'recipe_id': r, 'scale': 1.0}],
      });
      offline = false;
    } catch (e) {
      if (_isNet(e)) {
        offline = true;
        throw OfflineException('Logging meals');
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
