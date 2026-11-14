import 'package:flutter_test/flutter_test.dart';
import 'package:rituva/engine/pdf_export.dart';

/// A minimal plan shaped like what the engine returns, so the generator is
/// exercised end to end without a device.
Map<String, dynamic> _samplePlan() => {
      'plan_id': 'test',
      'summary': {'on_target': 7, 'avg_dqs': 88},
      'days': [
        {
          'date': '2026-11-14',
          'totals': {'kcal': 2200, 'protein': 100, 'fibre': 42},
          'validation': {'dqs': 90, 'in_tolerance': true},
          'entries': [
            {
              'slot': 'breakfast',
              'nutrients': {'kcal': 420},
              'components': [
                {'name': 'Sattu paratha'},
                {'name': 'Curd'}
              ],
            },
            {
              'slot': 'lunch',
              'nutrients': {'kcal': 650},
              'components': [
                {'name': 'Rice'},
                {'name': 'Chana ghugni'}
              ],
            },
          ],
        },
      ],
    };

void main() {
  test('buildPlanPdf produces a valid PDF from a plan (no grocery)', () async {
    final bytes = await buildPlanPdf(
      plan: _samplePlan(),
      member: {'name': 'Aarav', 'diet_type': 'lacto_veg', 'goal': 'maintain'},
    );
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-'); // PDF magic header
  });

  test('buildPlanPdf includes a grocery section when supplied', () async {
    final a = await buildPlanPdf(
      plan: _samplePlan(),
      member: {'name': 'Diya', 'diet_type': 'lacto_veg', 'goal': 'lose'},
    );
    final b = await buildPlanPdf(
      plan: _samplePlan(),
      member: {'name': 'Diya', 'diet_type': 'lacto_veg', 'goal': 'lose'},
      grocery: {
        'total_items': 2,
        'people': 2,
        'categories': [
          {
            'category': 'Pulses',
            'items': [
              {'item': 'Chana dal', 'quantity': 200, 'unit': 'g'},
              {'item': 'Masoor dal', 'quantity': 150, 'unit': 'g'},
            ],
          },
        ],
      },
    );
    expect(String.fromCharCodes(b.take(5)), '%PDF-');
    // The grocery section adds content, so the document is larger.
    expect(b.length, greaterThan(a.length));
  });
}
