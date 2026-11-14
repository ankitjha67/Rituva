import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../api.dart';
import '../theme.dart';
import '../engine/pdf_export.dart';
import 'recipe_sheet.dart';

class PlanScreen extends StatelessWidget {
  final Map<String, dynamic> plan, ctx, member;
  final RituvaApi api;
  final Future<void> Function() onRegenerate;
  final bool regenerating;
  const PlanScreen({
    super.key,
    required this.plan,
    required this.ctx,
    required this.member,
    required this.api,
    required this.onRegenerate,
    required this.regenerating,
  });

  @override
  Widget build(BuildContext context) {
    final days = plan['days'] as List;
    final summary = plan['summary'] as Map;
    return ListView(
      padding: kScreenPad,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This week', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('${summary['on_target']}/7 on target · avg DQS ${summary['avg_dqs']}',
                      style: const TextStyle(color: R.muted, fontSize: 12)),
                ],
              ),
            ),
            // On-device PDF of the week (+ grocery) — generated on the phone, no server.
            PopupMenuButton<String>(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: R.gold),
              tooltip: 'Export PDF',
              onSelected: (v) => _exportPdf(context, share: v == 'share'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'print', child: Text('Print / Save as PDF')),
                PopupMenuItem(value: 'share', child: Text('Share PDF')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: regenerating ? null : onRegenerate,
              style: OutlinedButton.styleFrom(
                  foregroundColor: R.gold, side: const BorderSide(color: R.line)),
              icon: regenerating
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: R.gold))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate week'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _grocery(context),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('Grocery'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('Tap a day to see its meals', style: TextStyle(color: R.muted, fontSize: 11)),
        const SizedBox(height: 8),
        ...days.map((d) => Card(
              color: R.surface,
              child: ListTile(
                onTap: () => _showDay(context, d as Map<String, dynamic>),
                title: Text('${prettyDate(d['date'])}${d['date'] == ctx['today'] ? ' · today' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text('${(d['totals']['kcal'] as num).round()} kcal · DQS ${d['validation']['dqs']}',
                    style: const TextStyle(color: R.muted, fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle,
                        size: 10, color: (d['validation']['in_tolerance'] as bool) ? R.green : R.gold),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: R.muted),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  /// Day-detail sheet: the meals planned for the tapped day.
  void _showDay(BuildContext context, Map<String, dynamic> d) {
    final entries = d['entries'] as List;
    final totals = d['totals'] as Map;
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .7,
        maxChildSize: .92,
        minChildSize: .4,
        expand: false,
        builder: (c, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          children: [
            Text(prettyDate(d['date']),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(
              '${(totals['kcal'] as num).round()} kcal · '
              'P ${(totals['protein'] as num).round()}g · '
              'Fibre ${(totals['fibre'] as num).round()}g · DQS ${d['validation']['dqs']}',
              style: const TextStyle(color: R.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...entries.map((e) => _mealRow(context, e as Map)),
          ],
        ),
      ),
    );
  }

  Widget _mealRow(BuildContext context, Map e) {
    final comps = e['components'] as List;
    if (comps.isEmpty) return const SizedBox.shrink();
    final names = comps.map((c) => c['name']).join(' + ');
    final slot = e['slot'] as String;
    final main = (slot == 'lunch' || slot == 'dinner') && comps.length > 1 ? comps[1] : comps.first;
    final region = main['region'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => RecipeSheet.showForMeal(context, api, comps),
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
            decoration: BoxDecoration(color: R.gold.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
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
          if (region != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: regionColor(region).withValues(alpha: .2), borderRadius: BorderRadius.circular(6)),
              child: Text(region[0].toUpperCase(),
                  style: TextStyle(color: regionColor(region), fontWeight: FontWeight.w800, fontSize: 10)),
            ),
        ]),
        ),
      ),
    );
  }

  /// Generate the week's plan (+ grocery) as a PDF on the phone, then hand it to
  /// the OS print dialog (print / save-as-PDF) or the share sheet. No server.
  Future<void> _exportPdf(BuildContext context, {required bool share}) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1), content: Text('Building PDF…')));
    try {
      // Grocery is best-effort: a clean plan PDF is still useful if it can't be built.
      Map<String, dynamic>? grocery;
      try {
        grocery = await api.grocery(plan['plan_id'] as String, people: 2, plan: plan);
      } catch (_) {/* skip grocery section */}
      final bytes = await buildPlanPdf(plan: plan, member: member, grocery: grocery);
      final name = '${member['name'] ?? 'plan'}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      final file = 'rituva-$name-week.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: file);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: file);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, content: Text('Could not make the PDF: $e')));
    }
  }

  Future<void> _grocery(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FutureBuilder(
        future: api.grocery(plan['plan_id'] as String, people: 2, plan: plan),
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
          final g = snap.data as Map<String, dynamic>;
          final cats = g['categories'] as List;
          return DraggableScrollableSheet(
            initialChildSize: .7,
            maxChildSize: .92,
            minChildSize: .4,
            expand: false,
            builder: (c2, sc) => ListView(
              controller: sc,
              padding: const EdgeInsets.all(16),
              children: [
                Text('Grocery · ${g['total_items']} items · ${g['people']} ppl',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 8),
                ...cats.expand<Widget>((cat) => [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text('${cat['category']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                      ...(cat['items'] as List).map((it) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(child: Text('${it['item']}')),
                                const SizedBox(width: 10),
                                Text('${it['quantity']} ${it['unit']}', style: const TextStyle(color: R.muted)),
                              ],
                            ),
                          )),
                    ]),
              ],
            ),
          );
        },
      ),
    );
  }
}
