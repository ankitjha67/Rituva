import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// Browse the dish library by region (N/S/E/W). Online → the full library from
/// `/recipes`; offline → the dishes in the current week's plan, with a note.
class DiscoverScreen extends StatefulWidget {
  final RituvaApi api;
  final Map<String, dynamic> plan;
  const DiscoverScreen({super.key, required this.api, required this.plan});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List all = [];
  bool loading = true, offline = false;
  String region = 'all';
  String dietSel = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      all = await widget.api.recipes();
      offline = false;
    } catch (_) {
      offline = true;
      all = _fromPlan();
    }
    if (mounted) setState(() => loading = false);
  }

  List _fromPlan() {
    final seen = <String>{};
    final out = [];
    for (final d in (widget.plan['days'] as List)) {
      for (final e in (d['entries'] as List)) {
        final kcal = (e['nutrients']?['kcal'] as num?)?.round() ?? 0;
        for (final c in (e['components'] as List)) {
          final id = '${c['recipe_id'] ?? c['name']}';
          if (seen.add(id)) {
            out.add({'id': id, 'name': c['name'], 'region': c['region'], 'role': '', 'kcal': kcal});
          }
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: R.gold));
    }
    const regions = ['all', 'north', 'south', 'east', 'west'];
    const diets = ['all', 'veg', 'nonveg', 'vegan', 'jain', 'gluten_free'];
    const dietLabel = {
      'all': 'All', 'veg': 'Veg', 'nonveg': 'Non-veg', 'vegan': 'Vegan',
      'jain': 'Jain', 'gluten_free': 'Gluten-free'
    };
    final list = all.where((r) {
      final okR = region == 'all' || r['region'] == region;
      final okD = dietSel == 'all' || ((r['diet'] as List?)?.contains(dietSel) ?? true);
      return okR && okD;
    }).toList();
    Widget chipRow(List<String> opts, String sel, void Function(String) onSel, String Function(String) lbl) =>
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: opts
                .map((o) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(lbl(o)),
                        selected: sel == o,
                        selectedColor: R.gold.withOpacity(.25),
                        onSelected: (_) => onSel(o),
                      ),
                    ))
                .toList(),
          ),
        );
    return Column(
      children: [
        if (offline)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text("Offline — showing this week's dishes. Connect a server to browse all 1000+.",
                style: TextStyle(color: R.gold, fontSize: 11), textAlign: TextAlign.center),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: chipRow(diets, dietSel, (o) => setState(() => dietSel = o), (o) => dietLabel[o]!),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: chipRow(regions, region, (o) => setState(() => region = o),
              (o) => o == 'all' ? 'All' : humanize(o)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${list.length} dishes', style: const TextStyle(color: R.muted, fontSize: 12)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final r = list[i] as Map;
              final rg = r['region'] as String?;
              final role = '${r['role'] ?? ''}';
              return Card(
                color: R.surface,
                child: ListTile(
                  dense: true,
                  title: Text('${r['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('${r['kcal']} kcal${role.isNotEmpty ? ' · ${humanize(role)}' : ''}',
                      style: const TextStyle(color: R.muted, fontSize: 11)),
                  trailing: rg != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: regionColor(rg).withOpacity(.2),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(humanize(rg),
                              style: TextStyle(
                                  color: regionColor(rg), fontWeight: FontWeight.w700, fontSize: 10)),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
