import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';

/// How to cook a dish: numbered method, the Knowledge-DB ingredient breakdown, and
/// links to renowned chefs' takes on it.
///
/// Both halves are honest by construction — the gram amounts in the steps are the same
/// DB quantities the nutrition is computed from, and the video links are YouTube search
/// endpoints (or API-resolved real videos), never a guessed video ID.
class RecipeSheet extends StatefulWidget {
  final RituvaApi api;
  final String recipeId;
  final String fallbackName;
  const RecipeSheet(
      {super.key, required this.api, required this.recipeId, required this.fallbackName});

  /// Convenience: open the sheet for a dish.
  static void show(BuildContext context, RituvaApi api, String recipeId, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecipeSheet(api: api, recipeId: recipeId, fallbackName: name),
    );
  }

  /// A meal is often several dishes (rice + dal + sabzi). Open the recipe directly when
  /// there's only one, otherwise let the user pick which dish they're cooking.
  static void showForMeal(BuildContext context, RituvaApi api, List components) {
    final dishes = components.where((c) => c['recipe_id'] != null).toList();
    if (dishes.isEmpty) return;
    if (dishes.length == 1) {
      show(context, api, '${dishes.first['recipe_id']}', '${dishes.first['name']}');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      useSafeArea: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Which dish?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          ...dishes.map((c) => ListTile(
                leading: const Icon(Icons.menu_book_outlined, color: R.gold, size: 20),
                title: Text('${c['name']}', style: const TextStyle(fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: R.muted),
                onTap: () {
                  Navigator.pop(context);
                  show(context, api, '${c['recipe_id']}', '${c['name']}');
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  State<RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends State<RecipeSheet> {
  Map<String, dynamic>? card;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      card = await widget.api.recipe(widget.recipeId);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open YouTube.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .85,
      maxChildSize: .95,
      minChildSize: .5,
      expand: false,
      builder: (c, sc) {
        if (loading) {
          return const Center(child: CircularProgressIndicator(color: R.gold));
        }
        if (error != null) {
          return ListView(controller: sc, padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 30),
            const Icon(Icons.cloud_off, color: R.gold, size: 34),
            const SizedBox(height: 12),
            Text(widget.fallbackName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            Text(error!,
                textAlign: TextAlign.center, style: const TextStyle(color: R.muted, fontSize: 12)),
          ]);
        }
        final d = card!;
        final m = (d['method'] as Map?) ?? const {};
        final steps = (m['steps'] as List?) ?? const [];
        final ings = (d['ingredients'] as List?) ?? const [];
        final vids = (d['videos'] as List?) ?? const [];
        final nut = (d['nutrients'] as Map?) ?? const {};
        final diet = ((d['diet'] as List?) ?? const []).map((e) => '$e').toList();

        return ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (d['region'] != null) _pill(humanize('${d['region']}'), regionColor('${d['region']}')),
              ...diet.where((t) => t != 'dairy').map((t) => _pill(_dietLabel(t), R.teal)),
              _pill('${(nut['kcal'] as num?)?.round() ?? 0} kcal', R.gold),
            ]),
            const SizedBox(height: 14),

            // ---- at-a-glance timing ----
            Row(children: [
              _stat('${m['hands_on_min'] ?? '—'}m', 'hands-on'),
              _stat('${m['total_min'] ?? '—'}m', 'total'),
              _stat('${(nut['protein'] as num?)?.round() ?? 0}g', 'protein'),
              _stat('${(nut['fibre'] as num?)?.round() ?? 0}g', 'fibre'),
            ]),
            const SizedBox(height: 18),

            // ---- method ----
            const Text('HOW TO MAKE IT',
                style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            if ('${m['intro'] ?? ''}'.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: R.gold.withOpacity(.09),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: R.gold.withOpacity(.28)),
                ),
                child: Text('${m['intro']}',
                    style: const TextStyle(fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 14),
            ],
            ...steps.asMap().entries.map((e) => _step(e.key + 1, '${e.value}')),
            if (((m['tips'] as List?) ?? const []).isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text("COOK'S TIPS",
                  style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ...((m['tips'] as List).map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('• ', style: TextStyle(color: R.teal, fontSize: 13)),
                      Expanded(
                          child: Text('$t',
                              style: const TextStyle(fontSize: 12.5, height: 1.4, color: R.muted))),
                    ]),
                  ))),
            ],
            const SizedBox(height: 10),
            _sourceLine('${m['source'] ?? ''}'),
            const SizedBox(height: 6),
            _note('${m['grounding'] ?? ''}'),
            const SizedBox(height: 20),

            // ---- chef videos ----
            const Text('WATCH A CHEF MAKE IT',
                style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            const Text('Opens that chef\'s videos for this dish on YouTube',
                style: TextStyle(color: R.muted, fontSize: 11)),
            const SizedBox(height: 10),
            ...vids.map((v) => _videoTile(v as Map)),
            const SizedBox(height: 20),

            // ---- ingredients ----
            const Text('INGREDIENTS · FROM THE KNOWLEDGE DB',
                style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: R.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: R.line),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                for (final i in ings) _ingRow(i as Map),
                const Divider(color: R.line, height: 18),
                Row(children: [
                  const Expanded(
                    child: Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
                  Text(
                    '${(nut['kcal'] as num?)?.round() ?? 0} kcal · '
                    'P ${(nut['protein'] as num?)?.round() ?? 0}g',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: R.gold),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            _note('Spices, salt and aromatics are "to taste" — the DB does not carry their '
                'quantities, so Rituva will not invent them.'),
          ],
        );
      },
    );
  }

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: R.gold.withOpacity(.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$n',
                style: const TextStyle(color: R.gold, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45))),
        ]),
      );

  Widget _videoTile(Map v) {
    final isVideo = v['kind'] == 'video';
    final lang = '${v['lang'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _open('${v['url']}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: R.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: R.line),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: R.magenta.withOpacity(.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(isVideo ? Icons.play_arrow : Icons.search, color: R.magenta, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${v['chef']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(
                  isVideo && '${v['title']}'.isNotEmpty
                      ? '${v['title']}'
                      : '${v['channel']}${lang.isNotEmpty ? ' · $lang' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: R.muted, fontSize: 11),
                ),
              ]),
            ),
            const Icon(Icons.open_in_new, size: 16, color: R.muted),
          ]),
        ),
      ),
    );
  }

  Widget _ingRow(Map i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Text('${i['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
          Expanded(
            flex: 2,
            child: Text('${(i['qty_g'] as num?)?.round() ?? 0} g',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 3,
            child: Text('${i['kcal']} kcal',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5, color: R.muted)),
          ),
        ]),
      );

  Widget _stat(String big, String label) => Expanded(
        child: Column(children: [
          Text(big, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: const TextStyle(color: R.muted, fontSize: 10)),
        ]),
      );

  Widget _pill(String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withOpacity(.18), borderRadius: BorderRadius.circular(8)),
        child: Text(s, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 10.5)),
      );

  /// Who wrote the steps — an LLM-authored recipe says so plainly, and says what the
  /// model was and wasn't allowed to decide.
  Widget _sourceLine(String source) {
    if (source.isEmpty || source == 'deterministic') {
      return const Text('Steps built from this dish\'s Knowledge-DB ingredients.',
          style: TextStyle(color: R.muted, fontSize: 11));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.auto_awesome, size: 12, color: R.gold),
      const SizedBox(width: 6),
      Expanded(
        child: Text('Method written by $source — quantities still come from the DB.',
            style: const TextStyle(color: R.gold, fontSize: 11)),
      ),
    ]);
  }

  Widget _note(String s) => s.trim().isEmpty
      ? const SizedBox.shrink()
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('◆ ', style: TextStyle(color: R.teal, fontSize: 11)),
          Expanded(child: Text(s, style: const TextStyle(color: R.muted, fontSize: 11, height: 1.35))),
        ]);

  static String _dietLabel(String t) => const {
        'veg': 'Veg',
        'nonveg': 'Non-veg',
        'vegan': 'Vegan',
        'jain': 'Jain',
        'gluten_free': 'Gluten-free',
        'egg': 'Egg',
      }[t] ??
      humanize(t);
}
