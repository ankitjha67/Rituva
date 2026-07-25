import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin client for the Rituva FastAPI backend. Every value returned here is
/// computed by the server from the Knowledge DB — the app never invents nutrition.
class RituvaApi {
  /// Android emulator reaches the host machine's localhost via 10.0.2.2.
  /// For a physical device use your PC's LAN IP; for prod, the deployed URL.
  final String baseUrl;
  // Default is the Android-emulator alias for the host's localhost. CI can bake a
  // real backend URL via `--dart-define=RITUVA_API=https://your-host`.
  const RituvaApi({
    this.baseUrl = const String.fromEnvironment('RITUVA_API', defaultValue: 'http://10.0.2.2:8000'),
  });

  Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse('$baseUrl$path')
      .replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  Future<dynamic> _get(String path, [Map<String, dynamic>? q]) async {
    final r = await http.get(_u(path, q));
    if (r.statusCode >= 400) throw Exception('GET $path → ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(_u(path),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode >= 400) throw Exception('POST $path → ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Future<void> _delete(String path, Map<String, dynamic> q) async {
    final r = await http.delete(_u(path, q));
    if (r.statusCode >= 400) throw Exception('DELETE $path → ${r.statusCode}');
  }

  Future<Map<String, dynamic>> context() async =>
      (await _get('/context')) as Map<String, dynamic>;
  Future<List> members() async => (await _get('/members')) as List;
  Future<Map<String, dynamic>> member(String id) async =>
      (await _get('/members/$id')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> targets(String id) async =>
      (await _get('/members/$id/targets')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> createPlan(String id, {int days = 7, String? start}) async =>
      (await _post('/plans',
          {'member_id': id, 'days': days, if (start != null) 'start': start}))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> grocery(String planId, {int people = 2}) async =>
      (await _get('/plans/$planId/grocery', {'people': people})) as Map<String, dynamic>;
  Future<Map<String, dynamic>> alternatives(String id, String recipeId, String day) async =>
      (await _get('/members/$id/alternatives', {'recipe_id': recipeId, 'day': day}))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> memory(String id) async =>
      (await _get('/members/$id/memory')) as Map<String, dynamic>;
  Future<void> addMemory(String id, String kind, String value) async =>
      _post('/members/$id/memory', {'kind': kind, 'value': value});
  Future<void> removeMemory(String id, String kind, String value) async =>
      _delete('/members/$id/memory', {'kind': kind, 'value': value});
  Future<Map<String, dynamic>> adherence(String id, String day, String planId) async =>
      (await _get('/members/$id/adherence', {'date': day, 'plan_id': planId}))
          as Map<String, dynamic>;

  String exportUrl(String planId, {int people = 2}) =>
      '$baseUrl/plans/$planId/export.xlsx?people=$people';
}
