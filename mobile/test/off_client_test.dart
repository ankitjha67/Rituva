import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rituva/engine/off_client.dart';

void main() {
  test('parses an OFF product into per-100 g nutrients', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, contains('3017620422003'));
      return http.Response(
        jsonEncode({
          'status': 1,
          'product': {
            'product_name': 'Nutella',
            'brands': 'Ferrero, Nutella',
            'nutriments': {
              'energy-kcal_100g': 539,
              'proteins_100g': 6.3,
              'carbohydrates_100g': 57.5,
              'fat_100g': 30.9,
              'fiber_100g': 0,
              'sugars_100g': 56.3,
              'sodium_100g': 0.0428,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final r = await OffClient(mock).lookup('3017620422003');
    expect(r, isNotNull);
    expect(r!['name'], 'Nutella');
    expect(r['brand'], 'Ferrero'); // first brand only
    expect(r['kcal'], 539);
    expect(r['protein'], 6.3);
    expect((r['sodium_mg'] as double).round(), 43); // 0.0428 g -> 42.8 mg
  });

  test('returns null when OFF has no such product (status 0)', () async {
    final mock =
        MockClient((_) async => http.Response(jsonEncode({'status': 0}), 200));
    expect(await OffClient(mock).lookup('0000000000000'), isNull);
  });

  test('returns null when the product has no energy value', () async {
    final mock = MockClient((_) async => http.Response(
        jsonEncode({
          'status': 1,
          'product': {'product_name': 'Mystery', 'nutriments': {}}
        }),
        200));
    expect(await OffClient(mock).lookup('123'), isNull);
  });
}
