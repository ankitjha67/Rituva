import 'package:flutter/material.dart';
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
            FilledButton.tonalIcon(
              onPressed: () => _grocery(context),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('Grocery'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...days.map((d) => Card(
              color: R.surface,
              child: ListTile(
                title: Text('${d['date']}${d['date'] == ctx['today'] ? ' · today' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text('${(d['totals']['kcal'] as num).round()} kcal · DQS ${d['validation']['dqs']}',
                    style: const TextStyle(color: R.muted, fontSize: 11)),
                trailing: Icon(Icons.circle,
                    size: 10, color: (d['validation']['in_tolerance'] as bool) ? R.green : R.gold),
              ),
            )),
      ],
    );
  }

  Future<void> _grocery(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      builder: (_) => FutureBuilder(
        future: api.grocery(plan['plan_id'] as String, people: 2),
        builder: (c, snap) {
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
