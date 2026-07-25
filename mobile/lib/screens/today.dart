import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class TodayScreen extends StatelessWidget {
  final Map<String, dynamic> ctx, targets, day, plan;
  final RituvaApi api;
  final String memberId;
  const TodayScreen({
    super.key,
    required this.ctx,
    required this.targets,
    required this.day,
    required this.plan,
    required this.api,
    required this.memberId,
  });

  @override
  Widget build(BuildContext context) {
    final totals = day['totals'] as Map;
    final kcal = (totals['kcal'] as num).round();
    final tgtKcal = (targets['kcal'] as num).round();
    final cites = ((plan['provenance']?['citations']) as List?) ?? const [];
    final entries = day['entries'] as List;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _energyCard(kcal, tgtKcal, totals),
        if (cites.isNotEmpty) _citeCard(cites.first as Map),
        const SizedBox(height: 14),
        const Text("Today's menu · tap to swap",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        ...entries.map((e) => _mealCard(context, e as Map)),
      ],
    );
  }

  Widget _energyCard(int kcal, int tgt, Map totals) {
    final pct = (kcal / (tgt == 0 ? 1 : tgt)).clamp(0.0, 1.0);
    final macros = <List<Object>>[
      ['Protein', 'protein', 'protein_g', R.teal],
      ['Carb', 'carb', 'carb_g', R.gold],
      ['Fat', 'fat', 'fat_g', R.violet],
      ['Fibre', 'fibre', 'fibre_g', R.fibre],
    ];
    return Card(
      color: R.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              height: 108,
              child: CustomPaint(
                painter: _RingPainter(pct),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$kcal', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                    Text('of $tgt kcal', style: const TextStyle(color: R.muted, fontSize: 10)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: macros.map((m) {
                  final cur = (totals[m[1]] as num?)?.toDouble() ?? 0;
                  final t = (targets[m[2]] as num?)?.toDouble() ?? 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(m[0] as String, style: const TextStyle(color: R.muted, fontSize: 11)),
                            Text('${cur.round()} / ${t.round()} g',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 3),
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
          ],
        ),
      ),
    );
  }

  Widget _citeCard(Map c) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Text('◆ ', style: TextStyle(color: R.teal)),
              Expanded(
                child: Text('${c['text']} — ${c['source']}',
                    style: const TextStyle(color: R.muted, fontSize: 11)),
              ),
            ]),
          ),
        ),
      );

  Widget _mealCard(BuildContext context, Map e) {
    final comps = e['components'] as List;
    final names = comps.map((c) => c['name']).join(' + ');
    final slot = e['slot'] as String;
    final main = (slot == 'lunch' || slot == 'dinner') && comps.length > 1 ? comps[1] : comps.first;
    final region = main['region'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _swap(context, main['recipe_id'] as String),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: R.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: R.line),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: R.gold.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
              child: Text(mealEmoji(slot), style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(names, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${slotLabel(slot)} · ${(e['nutrients']['kcal'] as num).round()} kcal',
                    style: const TextStyle(color: R.muted, fontSize: 10.5)),
              ]),
            ),
            if (region != null) _tag(region),
          ]),
        ),
      ),
    );
  }

  Future<void> _swap(BuildContext context, String recipeId) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      builder: (_) => FutureBuilder(
        future: api.alternatives(memberId, recipeId, day['date'] as String),
        builder: (c, snap) {
          if (snap.hasError) {
            return SizedBox(
              height: 180,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${snap.error}',
                      textAlign: TextAlign.center, style: const TextStyle(color: R.muted)),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: R.gold)));
          }
          final res = snap.data as Map<String, dynamic>;
          final alts = res['alternatives'] as List;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Swap · ${res['declined']['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const Text('matched on calories & nutrients, from the DB',
                    style: TextStyle(color: R.muted, fontSize: 12)),
                const SizedBox(height: 8),
                ...alts.map((a) => Card(
                      color: R.surface,
                      child: ListTile(
                        title: Text('${a['name']}'),
                        subtitle: Text(
                          '${(a['nutrients']['kcal'] as num).round()} kcal · '
                          'P${a['nutrients']['protein']} · Fib${a['nutrients']['fibre']}  (${a['delta']})',
                          style: const TextStyle(color: R.muted, fontSize: 11),
                        ),
                        trailing: a['region'] != null ? _tag(a['region'] as String) : null,
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _tag(String r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: regionColor(r).withOpacity(.2), borderRadius: BorderRadius.circular(6)),
        child: Text(r[0].toUpperCase(),
            style: TextStyle(color: regionColor(r), fontWeight: FontWeight.w800, fontSize: 10)),
      );
}

class _RingPainter extends CustomPainter {
  final double pct;
  _RingPainter(this.pct);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = R.line;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = R.gold;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * pct, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}
