import 'package:flutter/material.dart';
import '../theme.dart';

/// Plan-based analytics (works offline): weekly Diet-Quality-Score trend,
/// on-target summary, and average macros vs targets. All numbers come from the
/// validator / Knowledge DB, never invented.
class InsightsScreen extends StatelessWidget {
  final Map<String, dynamic> plan, targets;
  const InsightsScreen({super.key, required this.plan, required this.targets});

  @override
  Widget build(BuildContext context) {
    final days = plan['days'] as List;
    final summary = plan['summary'] as Map;

    double avg(String k) => days.isEmpty
        ? 0
        : days.fold<double>(0, (a, d) => a + ((d['totals'][k] as num?)?.toDouble() ?? 0)) / days.length;

    final macros = <List<Object>>[
      ['Protein', 'protein', 'protein_g', R.teal],
      ['Carb', 'carb', 'carb_g', R.gold],
      ['Fat', 'fat', 'fat_g', R.violet],
      ['Fibre', 'fibre', 'fibre_g', R.fibre],
    ];

    return ListView(
      padding: kScreenPad,
      children: [
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _stat('${summary['on_target']}/${days.length}', 'days on target'),
              _stat('${summary['avg_dqs']}', 'avg diet score'),
              _stat('${days.length}', 'days planned'),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Diet Quality Score · this week',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: days.map<Widget>((d) {
                  final dqs = (d['validation']['dqs'] as num).toDouble();
                  final ok = d['validation']['in_tolerance'] as bool;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${dqs.round()}', style: const TextStyle(fontSize: 9, color: R.muted)),
                          const SizedBox(height: 2),
                          Container(
                            height: (dqs / 100 * 90).clamp(4, 90),
                            decoration: BoxDecoration(
                              color: ok ? R.green : R.gold,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(_dow(d['date'] as String),
                              style: const TextStyle(fontSize: 9, color: R.muted)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Average macros vs target',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: macros.map((m) {
                final cur = avg(m[1] as String);
                final t = (targets[m[2]] as num?)?.toDouble() ?? 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(m[0] as String, style: const TextStyle(color: R.muted, fontSize: 12)),
                          Text('${cur.round()} / ${t.round()} g avg',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(
                          value: (cur / (t == 0 ? 1 : t)).clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor: R.line,
                          color: m[3] as Color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          color: R.surface,
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Text('◆ ', style: TextStyle(color: R.teal)),
              Expanded(
                child: Text('Scores from the validator; macros summed from the Knowledge DB — never invented.',
                    style: TextStyle(color: R.muted, fontSize: 11)),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _stat(String big, String label) => Expanded(
        child: Column(children: [
          Text(big, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: R.muted, fontSize: 10)),
        ]),
      );

  static String _dow(String iso) {
    try {
      return ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime.parse(iso).weekday - 1];
    } catch (_) {
      return '';
    }
  }
}
