import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';

class PlanScreen extends StatelessWidget {
  final Map<String, dynamic> plan, ctx;
  final RituvaApi api;
  const PlanScreen({super.key, required this.plan, required this.ctx, required this.api});

  @override
  Widget build(BuildContext context) {
    final days = plan['days'] as List;
    final summary = plan['summary'] as Map;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This week', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text('${summary['on_target']}/7 on target · avg DQS ${summary['avg_dqs']}',
                    style: const TextStyle(color: R.muted, fontSize: 12)),
              ],
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (!'${plan['plan_id']}'.startsWith('demo'))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: 'Export',
                  onSelected: (v) => _export(context, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                    PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
                  ],
                ),
              FilledButton.tonalIcon(
                onPressed: () => _grocery(context),
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: const Text('Grocery'),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Tap a day to see its meals', style: TextStyle(color: R.muted, fontSize: 11)),
        const SizedBox(height: 8),
        ...days.map((d) => Card(
              color: R.surface,
              child: ListTile(
                onTap: () => _showDay(context, d as Map<String, dynamic>),
                title: Text('${_pretty(d['date'] as String)}${d['date'] == ctx['today'] ? ' · today' : ''}',
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
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .7,
        maxChildSize: .92,
        minChildSize: .4,
        expand: false,
        builder: (c, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          children: [
            Text(_pretty(d['date'] as String),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(
              '${(totals['kcal'] as num).round()} kcal · '
              'P ${(totals['protein'] as num).round()}g · '
              'Fibre ${(totals['fibre'] as num).round()}g · DQS ${d['validation']['dqs']}',
              style: const TextStyle(color: R.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...entries.map((e) => _mealRow(e as Map)),
          ],
        ),
      ),
    );
  }

  Widget _mealRow(Map e) {
    final comps = e['components'] as List;
    final names = comps.map((c) => c['name']).join(' + ');
    final slot = e['slot'] as String;
    final main = (slot == 'lunch' || slot == 'dinner') && comps.length > 1 ? comps[1] : comps.first;
    final region = main['region'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
          if (region != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: regionColor(region).withOpacity(.2), borderRadius: BorderRadius.circular(6)),
              child: Text(region[0].toUpperCase(),
                  style: TextStyle(color: regionColor(region), fontWeight: FontWeight.w800, fontSize: 10)),
            ),
        ]),
      ),
    );
  }

  /// "2026-07-25" → "Sat, 25 Jul" (falls back to the raw string on any parse issue).
  static String _pretty(String iso) {
    try {
      final d = DateTime.parse(iso);
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _export(BuildContext context, String kind) async {
    final id = plan['plan_id'] as String;
    final url = kind == 'pdf' ? api.exportPdfUrl(id) : api.exportUrl(id);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open export — connect a server in Profile.')));
    }
  }

  Future<void> _grocery(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      builder: (_) => FutureBuilder(
        future: api.grocery(plan['plan_id'] as String, people: 2),
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${it['item']}'),
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
