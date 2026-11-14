import 'dart:convert';
import 'package:http/http.dart' as http;

/// Open Food Facts lookup (ODbL open data, free, no API key). Given a scanned
/// barcode it returns the product's name/brand and **per-100 g** nutrients, or
/// null when OFF has no usable record. Network-only; callers handle offline.
///
/// Consistent with Rituva's rule that numbers come from a database, not a model:
/// every value here is what the OFF community recorded for that product.
class OffClient {
  static const _base = 'https://world.openfoodfacts.org/api/v2';
  static const _fields =
      'product_name,brands,nutriments,serving_size,quantity';

  final http.Client _http;
  OffClient([http.Client? client]) : _http = client ?? http.Client();

  Future<Map<String, dynamic>?> lookup(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final uri = Uri.parse('$_base/product/$code.json?fields=$_fields');
    final r = await _http.get(uri, headers: {
      // OFF asks every app to identify itself in the User-Agent.
      'User-Agent': 'Rituva/1.0 (open-source nutrition planner)',
    }).timeout(const Duration(seconds: 12));
    if (r.statusCode >= 400) return null;
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (body['status'] != 1) return null; // 0 = product not found
    final p = (body['product'] as Map?) ?? const {};
    final n = (p['nutriments'] as Map?) ?? const {};

    double? per100(String k) {
      final v = n[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final kcal = per100('energy-kcal_100g');
    if (kcal == null) return null; // no usable energy value → treat as not found
    final name = '${p['product_name'] ?? ''}'.trim();
    return {
      'barcode': code,
      'name': name.isEmpty ? 'Unknown product' : name,
      'brand': '${p['brands'] ?? ''}'.split(',').first.trim(),
      'serving_size': '${p['serving_size'] ?? ''}'.trim(),
      // all per 100 g
      'kcal': kcal,
      'protein': per100('proteins_100g') ?? 0,
      'carb': per100('carbohydrates_100g') ?? 0,
      'fat': per100('fat_100g') ?? 0,
      'fibre': per100('fiber_100g') ?? 0,
      'sugar': per100('sugars_100g') ?? 0,
      'sodium_mg': (per100('sodium_100g') ?? 0) * 1000, // OFF reports sodium in g
      'source': 'Open Food Facts',
    };
  }
}
