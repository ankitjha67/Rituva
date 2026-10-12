import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Wearable-style analytics — three lenses (Day / Week / Meals) computed entirely
/// from the plan the app already holds, so it works offline too. Every number is
/// summed from the Knowledge DB by the server/validator; nothing here is invented.
class InsightsScreen extends StatefulWidget {
  final Map<String, dynamic> plan, targets, anthro, ctx;
  const InsightsScreen(
      {super.key, required this.plan, required this.targets, required this.anthro, required this.ctx});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int seg = 0; // 0 = Day, 1 = Week, 2 = Meals

  // ---- meal grouping (engine slots → the 4 buckets people think in) ----
  static const _mealColor = {
    'Breakfast': R.gold,
    'Lunch': R.teal,
    'Dinner': R.violet,
    'Snacks': R.green,
  };
  static const _slotToMeal = {
    'breakfast': 'Breakfast',
    'lunch': 'Lunch',
    'dinner': 'Dinner',
    'snack1': 'Snacks',
    'snack2': 'Snacks',
  };

  List get _days => (widget.plan['days'] as List?) ?? const [];
  double _t(String k, double fallback) => (widget.targets[k] as num?)?.toDouble() ?? fallback;

  Map<String, dynamic> _todayDay() {
    final today = widget.ctx['today'];
    for (final d in _days) {
      if (d['date'] == today) return d as Map<String, dynamic>;
    }
    return (_days.isNotEmpty ? _days.first : const {}) as Map<String, dynamic>;
  }

  double _n(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: kScreenPad,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Day')),
            ButtonSegment(value: 1, label: Text('Week')),
            ButtonSegment(value: 2, label: Text('Meals')),
          ],
          selected: {seg},
          onSelectionChanged: (s) => setState(() => seg = s.first),
        ),
        const SizedBox(height: 16),
        if (seg == 0) ..._dayView() else if (seg == 1) ..._weekView() else ..._mealsView(),
        const SizedBox(height: 10),
        _dbNote(),
      ],
    );
  }

  // =====================================================================  DAY
  List<Widget> _dayView() {
    final d = _todayDay();
    if (d.isEmpty) return [const Text('No day data.')];
    final tot = (d['totals'] as Map?) ?? const {};
    final kcal = _n(tot, 'kcal'), prot = _n(tot, 'protein'), fib = _n(tot, 'fibre');
    final carb = _n(tot, 'carb'), fat = _n(tot, 'fat');

    return [
      Row(
        children: [
          Text(prettyDate(d['date']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          _dqsPill((d['validation']?['dqs'] as num?)?.round() ?? 0),
        ],
      ),
      const SizedBox(height: 14),
      // three activity rings
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RingGauge(value: kcal, target: _t('kcal', 2000), label: 'Energy', unit: 'kcal', color: R.gold),
          _RingGauge(value: prot, target: _t('protein_g', 60), label: 'Protein', unit: 'g', color: R.teal),
          _RingGauge(value: fib, target: _t('fibre_g', 30), label: 'Fibre', unit: 'g', color: R.fibre),
        ],
      ),
      const SizedBox(height: 16),
      _card('Nutrient balance · % of target', Column(children: [
        _NutrientRadar(
          labels: const ['Energy', 'Protein', 'Carbs', 'Fat', 'Fibre', 'Iron', 'Calcium', 'B12'],
          ratios: [
            kcal / _t('kcal', 2000),
            prot / _t('protein_g', 60),
            carb / _t('carb_g', 250),
            fat / _t('fat_g', 60),
            fib / _t('fibre_g', 30),
            _n(tot, 'iron') / _t('iron_mg', 19),
            _n(tot, 'calcium') / _t('calcium_mg', 1000),
            _n(tot, 'b12') / _t('b12_ug', 2.2),
          ],
        ),
        const SizedBox(height: 4),
        const Text('A full, even web means every nutrient is on target. Green dots are met.',
            style: TextStyle(color: R.muted, fontSize: 10.5), textAlign: TextAlign.center),
      ])),
      const SizedBox(height: 12),
      _card('Calorie composition', Column(children: [
        _Waffle(segments: [
          _Seg(prot * 4, R.teal),
          _Seg(carb * 4, R.gold),
          _Seg(fat * 9, R.violet),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _legendDot('Protein', R.teal),
          _legendDot('Carbs', R.gold),
          _legendDot('Fat', R.violet),
        ]),
      ])),
      const SizedBox(height: 12),
      _card('Macro balance', Column(
        children: [
          Row(
            children: [
              _Donut(
                size: 108,
                segments: [
                  _Seg(prot * 4, R.teal),
                  _Seg(carb * 4, R.gold),
                  _Seg(fat * 9, R.violet),
                ],
                centerTop: '${kcal.round()}',
                centerBottom: 'kcal',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _macroRow('Protein', prot, _t('protein_g', 60), R.teal, prot * 4, kcal),
                    _macroRow('Carbs', carb, _t('carb_g', 250), R.gold, carb * 4, kcal),
                    _macroRow('Fat', fat, _t('fat_g', 60), R.violet, fat * 9, kcal),
                  ],
                ),
              ),
            ],
          ),
        ],
      )),
      const SizedBox(height: 12),
      _card('Micronutrients · % of RDA', Column(
        children: [
          _budget('Iron', _n(tot, 'iron'), _t('iron_mg', 19), 'mg', higherIsBetter: true),
          _budget('Calcium', _n(tot, 'calcium'), _t('calcium_mg', 1000), 'mg', higherIsBetter: true),
          _budget('Vitamin B12', _n(tot, 'b12'), _t('b12_ug', 2.2), 'µg', higherIsBetter: true),
        ],
      )),
      const SizedBox(height: 12),
      _card('Sodium budget', Column(
        children: [
          _budget('Sodium', _n(tot, 'sodium'), _t('sodium_mg_max', 2000), 'mg', higherIsBetter: false),
        ],
      )),
      const SizedBox(height: 12),
      _mealDistributionCard(d),
      const SizedBox(height: 12),
      _metabolicCard(),
    ];
  }

  Widget _macroRow(String name, double g, double target, Color c, double energy, double dayKcal) {
    final pctEnergy = dayKcal <= 0 ? 0 : (energy / dayKcal * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 12))),
          Text('${g.round()} g  ·  $pctEnergy%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: R.muted)),
      ]);

  Widget _metabolicCard() {
    final a = widget.anthro;
    return _card('Energy engine', Row(
      children: [
        _miniStat('${a['bmr'] ?? '—'}', 'BMR'),
        _miniStat('${a['tdee'] ?? '—'}', 'TDEE'),
        _miniStat('${(widget.targets['kcal'] as num?)?.round() ?? '—'}', 'Target'),
        _miniStat('${a['bmi'] ?? '—'}', 'BMI'),
      ],
    ));
  }

  Widget _mealDistributionCard(Map<String, dynamic> d) {
    final buckets = <String, double>{'Breakfast': 0, 'Lunch': 0, 'Dinner': 0, 'Snacks': 0};
    for (final e in (d['entries'] as List? ?? const [])) {
      final meal = _slotToMeal[e['slot']] ?? 'Snacks';
      buckets[meal] = (buckets[meal] ?? 0) + _n(e['nutrients'] as Map? ?? const {}, 'kcal');
    }
    final total = buckets.values.fold<double>(0, (a, b) => a + b);
    return _card('Where today\'s calories come from', Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StackedBar(
          segments: buckets.entries
              .where((e) => e.value > 0)
              .map((e) => _Seg(e.value, _mealColor[e.key]!))
              .toList(),
        ),
        const SizedBox(height: 10),
        ...buckets.entries.map((e) {
          final pct = total <= 0 ? 0 : (e.value / total * 100).round();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: _mealColor[e.key], shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12))),
              Text('${e.value.round()} kcal · $pct%',
                  style: const TextStyle(fontSize: 12, color: R.muted)),
            ]),
          );
        }),
      ],
    ));
  }

  // ====================================================================  WEEK
  List<Widget> _weekView() {
    final days = _days;
    if (days.isEmpty) return [const Text('No week data.')];
    double avg(String k) =>
        days.fold<double>(0, (a, d) => a + _n(d['totals'] as Map? ?? const {}, k)) / days.length;
    final onTarget = days.where((d) => d['validation']?['in_tolerance'] == true).length;
    final avgDqs =
        (days.fold<double>(0, (a, d) => a + ((d['validation']?['dqs'] as num?)?.toDouble() ?? 0)) / days.length)
            .round();

    // best / worst day by DQS
    final sorted = [...days]
      ..sort((a, b) => ((b['validation']?['dqs'] ?? 0) as num).compareTo((a['validation']?['dqs'] ?? 0) as num));
    final best = sorted.first, worst = sorted.last;

    // adherence heatmap: one row per day, one cell per key nutrient (actual/target)
    const heatKeys = [
      ['kcal', 'kcal'], ['protein', 'protein_g'], ['fibre', 'fibre_g'],
      ['iron', 'iron_mg'], ['calcium', 'calcium_mg'], ['b12', 'b12_ug'],
    ];
    final heatRatios = [
      for (final d in days)
        [for (final k in heatKeys) _n(d['totals'] as Map? ?? const {}, k[0]) / _t(k[1], 1)],
    ];

    // Mean Adequacy Ratio (MAR): per day, average each nutrient's min(actual/target, 1);
    // then average across the week. A single, research-grounded "how complete" score.
    const marKeys = [
      ['protein', 'protein_g'], ['fibre', 'fibre_g'], ['iron', 'iron_mg'],
      ['calcium', 'calcium_mg'], ['b12', 'b12_ug'],
    ];
    double marDay(Map d) {
      final tot = d['totals'] as Map? ?? const {};
      var s = 0.0;
      for (final k in marKeys) {
        s += (_n(tot, k[0]) / _t(k[1], 1)).clamp(0.0, 1.0);
      }
      return s / marKeys.length;
    }

    final mar = days.fold<double>(0, (a, d) => a + marDay(d as Map)) / days.length;

    return [
      Row(children: [
        _miniStat('$onTarget/${days.length}', 'on target'),
        _miniStat('$avgDqs', 'avg score'),
        _miniStat('${avg('kcal').round()}', 'avg kcal'),
        _miniStat('${avg('protein').round()}g', 'avg protein'),
      ]),
      const SizedBox(height: 14),
      _card('Nutrient adequacy (MAR)', Column(children: [
        _SemiGauge(
          value: mar,
          center: '${(mar * 100).round()}%',
          label: 'of needs met, averaged',
          color: mar >= 0.9 ? R.green : (mar >= 0.7 ? R.gold : R.magenta),
        ),
      ])),
      const SizedBox(height: 12),
      _card('Week adherence · each nutrient, each day', Column(children: [
        _AdherenceHeatmap(
          dayLabels: [for (final d in days) _dow(d['date'] as String)],
          nutrientLabels: const ['Energy', 'Prot', 'Fib', 'Iron', 'Calc', 'B12'],
          ratios: heatRatios,
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legendDot('short', R.magenta),
          const SizedBox(width: 10),
          _legendDot('close', R.gold),
          const SizedBox(width: 10),
          _legendDot('on target', R.green),
        ]),
      ])),
      const SizedBox(height: 12),
      _card('Calories · 7-day trend', _TrendBars(
        values: [for (final d in days) _n(d['totals'] as Map? ?? const {}, 'kcal')],
        labels: [for (final d in days) _dow(d['date'] as String)],
        target: _t('kcal', 2000),
        band: 0.12,
        okColor: R.gold,
      )),
      const SizedBox(height: 12),
      _card('Protein · 7-day trend', _TrendBars(
        values: [for (final d in days) _n(d['totals'] as Map? ?? const {}, 'protein')],
        labels: [for (final d in days) _dow(d['date'] as String)],
        target: _t('protein_g', 60),
        band: 0.10,
        okColor: R.teal,
        unit: 'g',
      )),
      const SizedBox(height: 12),
      _card('Diet Quality Score', _TrendBars(
        values: [for (final d in days) ((d['validation']?['dqs'] as num?)?.toDouble() ?? 0)],
        labels: [for (final d in days) _dow(d['date'] as String)],
        maxOverride: 100,
        colorByValue: (v) => v >= 80 ? R.green : R.gold,
      )),
      const SizedBox(height: 12),
      _card('Average macros vs target', Column(children: [
        for (final m in const [
          ['Protein', 'protein', 'protein_g', 0xFF33D6C0],
          ['Carbs', 'carb', 'carb_g', 0xFFFFB020],
          ['Fat', 'fat', 'fat_g', 0xFFB08CFF],
          ['Fibre', 'fibre', 'fibre_g', 0xFF57DF97],
        ])
          _budget(m[0] as String, avg(m[1] as String), _t(m[2] as String, 1), 'g', higherIsBetter: true),
      ])),
      const SizedBox(height: 12),
      _card('Micronutrients · weekly average vs RDA', Column(children: [
        _budget('Iron', avg('iron'), _t('iron_mg', 19), 'mg', higherIsBetter: true),
        _budget('Calcium', avg('calcium'), _t('calcium_mg', 1000), 'mg', higherIsBetter: true),
        _budget('Vitamin B12', avg('b12'), _t('b12_ug', 2.2), 'µg', higherIsBetter: true),
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _dayChip('Best day', best, R.green)),
        const SizedBox(width: 10),
        Expanded(child: _dayChip('Needs work', worst, R.gold)),
      ]),
    ];
  }

  Widget _dayChip(String label, Map day, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: TextStyle(color: c, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(prettyDate(day['date']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            Text('DQS ${day['validation']?['dqs'] ?? 0} · ${_n(day['totals'] as Map? ?? const {}, 'kcal').round()} kcal',
                style: const TextStyle(color: R.muted, fontSize: 11)),
          ],
        ),
      );

  // ===================================================================  MEALS
  List<Widget> _mealsView() {
    final days = _days;
    if (days.isEmpty) return [const Text('No meal data.')];
    // average per meal-bucket across the week
    final k = <String, double>{'Breakfast': 0, 'Lunch': 0, 'Dinner': 0, 'Snacks': 0};
    final p = <String, double>{'Breakfast': 0, 'Lunch': 0, 'Dinner': 0, 'Snacks': 0};
    final f = <String, double>{'Breakfast': 0, 'Lunch': 0, 'Dinner': 0, 'Snacks': 0};
    for (final d in days) {
      for (final e in (d['entries'] as List? ?? const [])) {
        final meal = _slotToMeal[e['slot']] ?? 'Snacks';
        final nut = e['nutrients'] as Map? ?? const {};
        k[meal] = k[meal]! + _n(nut, 'kcal');
        p[meal] = p[meal]! + _n(nut, 'protein');
        f[meal] = f[meal]! + _n(nut, 'fibre');
      }
    }
    final n = days.length;
    k.updateAll((key, v) => v / n);
    p.updateAll((key, v) => v / n);
    f.updateAll((key, v) => v / n);
    final totKcal = k.values.fold<double>(0, (a, b) => a + b);
    final totProt = p.values.fold<double>(0, (a, b) => a + b);
    final order = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

    return [
      const Text('Averages per meal · this week',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 4),
      const Text('Where your energy and protein land across the day',
          style: TextStyle(color: R.muted, fontSize: 11)),
      const SizedBox(height: 14),
      _card('Calorie split', Row(children: [
        _Donut(
          size: 108,
          segments: [for (final m in order) if (k[m]! > 0) _Seg(k[m]!, _mealColor[m]!)],
          centerTop: '${totKcal.round()}',
          centerBottom: 'kcal/day',
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [
            for (final m in order)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: _mealColor[m], shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m, style: const TextStyle(fontSize: 12))),
                  Text('${k[m]!.round()} · ${totKcal <= 0 ? 0 : (k[m]! / totKcal * 100).round()}%',
                      style: const TextStyle(fontSize: 12, color: R.muted)),
                ]),
              ),
          ]),
        ),
      ])),
      const SizedBox(height: 12),
      _card('Protein by meal', Column(children: [
        for (final m in order)
          _bar(m, p[m]!, totProt <= 0 ? 0.0 : p[m]! / totProt, _mealColor[m]!, '${p[m]!.round()} g'),
      ])),
      const SizedBox(height: 12),
      _card('Per-meal detail', Column(children: [
        Row(children: const [
          Expanded(flex: 3, child: Text('MEAL', style: TextStyle(color: R.muted, fontSize: 10, letterSpacing: 1))),
          Expanded(flex: 2, child: Text('KCAL', textAlign: TextAlign.right, style: TextStyle(color: R.muted, fontSize: 10, letterSpacing: 1))),
          Expanded(flex: 2, child: Text('PROTEIN', textAlign: TextAlign.right, style: TextStyle(color: R.muted, fontSize: 10, letterSpacing: 1))),
          Expanded(flex: 2, child: Text('FIBRE', textAlign: TextAlign.right, style: TextStyle(color: R.muted, fontSize: 10, letterSpacing: 1))),
        ]),
        const Divider(color: R.line, height: 14),
        for (final m in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: _mealColor[m], shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(m, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              Expanded(flex: 2, child: Text('${k[m]!.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
              Expanded(flex: 2, child: Text('${p[m]!.round()} g', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
              Expanded(flex: 2, child: Text('${f[m]!.round()} g', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ])),
    ];
  }

  // =================================================================  shared
  Widget _card(String title, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: R.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: R.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.1)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _miniStat(String big, String label) => Expanded(
        child: Column(children: [
          Text(big, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: R.muted, fontSize: 10)),
        ]),
      );

  Widget _dqsPill(int dqs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (dqs >= 80 ? R.green : R.gold).withValues(alpha: .16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('DQS $dqs',
            style: TextStyle(color: dqs >= 80 ? R.green : R.gold, fontWeight: FontWeight.w800, fontSize: 12)),
      );

  /// Progress bar vs a reference. higherIsBetter → green once the goal is met;
  /// otherwise (a limit like sodium) → green while under, red when exceeded.
  Widget _budget(String name, double value, double ref, String unit, {required bool higherIsBetter}) {
    final ratio = ref <= 0 ? 0.0 : (value / ref);
    final pct = (ratio * 100).round();
    final Color c = higherIsBetter
        ? (ratio >= 1.0 ? R.green : ratio >= 0.6 ? R.gold : R.magenta)
        : (ratio <= 1.0 ? R.green : R.magenta);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 12))),
            Text('${_fmt(value)} / ${_fmt(ref)} $unit · $pct%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 7,
                backgroundColor: R.line,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(String name, double value, double frac, Color c, String trailing) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 12))),
              Text(trailing, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                    value: v, minHeight: 7, backgroundColor: R.line, color: c),
              ),
            ),
          ],
        ),
      );

  Widget _dbNote() => Row(children: const [
        Text('◆ ', style: TextStyle(color: R.teal)),
        Expanded(
          child: Text('Every value is summed from the Knowledge DB; RDAs from ICMR-NIN 2020 — never invented.',
              style: TextStyle(color: R.muted, fontSize: 11)),
        ),
      ]);

  static String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _dow(String iso) {
    try {
      return ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime.parse(iso).weekday - 1];
    } catch (_) {
      return '';
    }
  }
}

// ============================================================  small widgets
class _Seg {
  final double value;
  final Color color;
  const _Seg(this.value, this.color);
}

/// A circular progress gauge (kcal / protein / fibre) with a value + % in the middle.
class _RingGauge extends StatelessWidget {
  final double value, target;
  final String label, unit;
  final Color color;
  const _RingGauge(
      {required this.value, required this.target, required this.label, required this.unit, required this.color});
  @override
  Widget build(BuildContext context) {
    final pct = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    final pctLabel = target <= 0 ? 0 : (value / target * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.toDouble()),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => CustomPaint(painter: _RingPainter(v, color), child: child),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _CountUp(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text('$pctLabel%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text('${value.round()} / ${target.round()} $unit', style: const TextStyle(color: R.muted, fontSize: 10)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final Color color;
  _RingPainter(this.pct, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = R.line;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * pct, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct || old.color != color;
}

/// A donut chart from weighted segments, with two lines of centered text.
class _Donut extends StatelessWidget {
  final List<_Seg> segments;
  final double size;
  final String centerTop, centerBottom;
  const _Donut({required this.segments, required this.size, this.centerTop = '', this.centerBottom = ''});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 850),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => CustomPaint(painter: _DonutPainter(segments, progress: v), child: child),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(centerTop, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text(centerBottom, style: const TextStyle(color: R.muted, fontSize: 10)),
            ]),
          ),
        ),
      );
}

class _DonutPainter extends CustomPainter {
  final List<_Seg> segments;
  final double progress; // 0..1 entrance sweep
  _DonutPainter(this.segments, {this.progress = 1.0});
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 7;
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    final rect = Rect.fromCircle(center: c, radius: r);
    if (total <= 0) {
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 14..color = R.line);
      return;
    }
    var start = -math.pi / 2;
    const gap = 0.04;
    for (final s in segments) {
      final full = 2 * math.pi * (s.value / total) * progress;
      final sweep = full - gap;
      canvas.drawArc(
        rect,
        start,
        sweep > 0 ? sweep : 0,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = s.color,
      );
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) {
    if (old.progress != progress) return true;
    if (old.segments.length != segments.length) return true;
    for (var i = 0; i < segments.length; i++) {
      if (old.segments[i].value != segments[i].value ||
          old.segments[i].color != segments[i].color) {
        return true;
      }
    }
    return false;
  }
}

/// A single horizontal 100%-width stacked bar (meal calorie split).
class _StackedBar extends StatelessWidget {
  final List<_Seg> segments;
  const _StackedBar({required this.segments});
  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (final s in segments)
              Expanded(
                  flex: total <= 0 ? 1 : (s.value / total * 1000).round().clamp(1, 1000).toInt(),
                  child: Container(color: s.color)),
          ],
        ),
      ),
    );
  }
}

/// Vertical trend bars with an optional target band (kcal/protein) or 0..max scale (DQS).
class _TrendBars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final double? target;
  final double band;
  final double? maxOverride;
  final Color okColor;
  final String unit;
  final Color Function(double)? colorByValue;
  const _TrendBars({
    required this.values,
    required this.labels,
    this.target,
    this.band = 0.12,
    this.maxOverride,
    this.okColor = R.gold,
    this.unit = '',
    this.colorByValue,
  });
  @override
  Widget build(BuildContext context) {
    final peak = values.fold<double>(0.0, (a, b) => math.max(a, b));
    final maxV = maxOverride ?? math.max(peak, (target ?? 0) * 1.2) * 1.05;
    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(values[i].round().toString(), style: const TextStyle(fontSize: 9, color: R.muted)),
                    const SizedBox(height: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 750),
                      curve: Curves.easeOutCubic,
                      builder: (_, g, __) => Container(
                        height: (maxV <= 0 ? 0.0 : values[i] / maxV * 92).clamp(3.0, 92.0) * g,
                        decoration: BoxDecoration(
                          color: _color(values[i]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(i < labels.length ? labels[i] : '', style: const TextStyle(fontSize: 9, color: R.muted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _color(double v) {
    if (colorByValue != null) return colorByValue!(v);
    if (target == null) return okColor;
    final lo = target! * (1 - band), hi = target! * (1 + band);
    return (v >= lo && v <= hi) ? R.green : okColor;
  }
}

// ======================================================= new animated charts

/// A number that counts up from 0 on build (easeOut), for stat headlines.
class _CountUp extends StatelessWidget {
  final double value;
  final TextStyle? style;
  const _CountUp(this.value, {this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('${v.round()}', style: style),
      );
}

/// Nutrient radar / spider — each axis is one nutrient's actual/target ratio; the web
/// expands from the centre on entrance. Dots turn green once an axis meets its target.
class _NutrientRadar extends StatelessWidget {
  final List<String> labels;
  final List<double> ratios; // actual / target, per axis
  const _NutrientRadar({required this.labels, required this.ratios});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 232,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, p, __) =>
              CustomPaint(size: Size.infinite, painter: _RadarPainter(ratios, labels, p)),
        ),
      );
}

class _RadarPainter extends CustomPainter {
  final List<double> ratios;
  final List<String> labels;
  final double progress;
  _RadarPainter(this.ratios, this.labels, this.progress);
  static const _maxVal = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ratios.length;
    if (n < 3) return;
    final c = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 30;
    Offset pt(int i, double v) {
      final ang = -math.pi / 2 + 2 * math.pi * (i % n) / n;
      final r = (v / _maxVal).clamp(0.0, 1.0) * radius;
      return c + Offset(math.cos(ang) * r, math.sin(ang) * r);
    }

    for (final lvl in [0.5, 1.0]) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = lvl == 1.0 ? R.teal.withValues(alpha: .45) : R.line;
      final path = Path();
      for (var i = 0; i <= n; i++) {
        final q = pt(i, lvl * _maxVal);
        i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, ring);
    }
    final axis = Paint()..color = R.line..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, pt(i, _maxVal), axis);
    }

    final poly = Path();
    for (var i = 0; i < n; i++) {
      final q = pt(i, ratios[i] * progress);
      i == 0 ? poly.moveTo(q.dx, q.dy) : poly.lineTo(q.dx, q.dy);
    }
    poly.close();
    canvas.drawPath(poly, Paint()..style = PaintingStyle.fill..color = R.teal.withValues(alpha: .20));
    canvas.drawPath(poly, Paint()..style = PaintingStyle.stroke..color = R.teal..strokeWidth = 2);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(
          pt(i, ratios[i] * progress), 3, Paint()..color = ratios[i] >= 1.0 ? R.green : R.gold);
    }

    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + 2 * math.pi * i / n;
      final lp = c + Offset(math.cos(ang) * (radius + 15), math.sin(ang) * (radius + 15));
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(color: R.muted, fontSize: 9.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

/// A 100-cell waffle (proportion of a whole), cells filling left→right on entrance.
class _Waffle extends StatelessWidget {
  final List<_Seg> segments;
  const _Waffle({required this.segments});
  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    final cells = <Color>[];
    if (total > 0) {
      for (final s in segments) {
        final count = (s.value / total * 100).round();
        for (var i = 0; i < count && cells.length < 100; i++) {
          cells.add(s.color);
        }
      }
    }
    while (cells.length < 100) {
      cells.add(R.line);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (_, p, __) {
        final shown = (p * 100).round();
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 100,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10, mainAxisSpacing: 3, crossAxisSpacing: 3),
          itemBuilder: (_, i) => Container(
            decoration: BoxDecoration(
              color: i < shown ? cells[i] : R.line.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      },
    );
  }
}

/// Days × nutrients adherence grid; cells wave in as the animation progresses.
class _AdherenceHeatmap extends StatelessWidget {
  final List<String> dayLabels;
  final List<String> nutrientLabels;
  final List<List<double>> ratios; // [day][nutrient] actual/target
  const _AdherenceHeatmap(
      {required this.dayLabels, required this.nutrientLabels, required this.ratios});

  Color _cell(double r) {
    if (r > 1.35) return R.teal; // well over
    if (r >= 0.9) return R.green; // on target
    if (r >= 0.7) return R.gold; // close
    return R.magenta; // short
  }

  @override
  Widget build(BuildContext context) {
    final cols = nutrientLabels.length;
    final totalCells = ratios.length * cols;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOut,
      builder: (_, p, __) => Column(
        children: [
          for (var di = 0; di < ratios.length; di++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                    width: 32,
                    child: Text(dayLabels[di],
                        style: const TextStyle(fontSize: 10, color: R.muted))),
                for (var ni = 0; ni < cols; ni++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Opacity(
                        opacity: (p * totalCells - (di * cols + ni)).clamp(0.0, 1.0),
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(
                              color: _cell(ratios[di][ni]),
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 32),
            for (final l in nutrientLabels)
              Expanded(
                  child: Text(l,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, color: R.muted))),
          ]),
        ],
      ),
    );
  }
}

/// A half-circle gauge (0..1) with a sweeping fill and a centred value.
class _SemiGauge extends StatelessWidget {
  final double value;
  final String label, center;
  final Color color;
  const _SemiGauge(
      {required this.value, required this.label, required this.center, this.color = R.gold});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 118,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          // Align (no size factors) fills the full width so the painter spans
          // the whole card; the label/value then sit centred inside the bowl
          // instead of cramping the arc into the text's own width.
          builder: (_, v, __) => CustomPaint(
            size: Size.infinite,
            painter: _GaugePainter(v, color),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                Text(label, style: const TextStyle(color: R.muted, fontSize: 11)),
                const SizedBox(height: 10),
              ]),
            ),
          ),
        ),
      );
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  _GaugePainter(this.value, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 6);
    final r = math.min(size.width / 2, size.height) - 16;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, math.pi, math.pi, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round..color = R.line);
    canvas.drawArc(rect, math.pi, math.pi * value, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round..color = color);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}
