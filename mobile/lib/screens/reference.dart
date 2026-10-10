import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// Daily nutrient requirements by life stage, and what a shortfall of each nutrient
/// does. Transcribed from ICMR-NIN's Dietary Guidelines for Indians (Annexure 3) —
/// nothing here is computed or model-written, and the row matching the current member
/// is highlighted so the numbers are personal rather than abstract.
class ReferenceScreen extends StatefulWidget {
  final RituvaApi api;
  final String memberId;
  final String memberName;
  const ReferenceScreen(
      {super.key, required this.api, required this.memberId, required this.memberName});

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  Map<String, dynamic>? data;
  String? error;
  int seg = 0; // 0 = requirements, 1 = deficiencies
  String filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      data = await widget.api.reference(memberId: widget.memberId);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: R.bg,
        title: const Text('Daily requirements'),
      ),
      body: SafeArea(
        top: false,
        child: data == null
            ? Center(
                child: error != null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: R.muted, fontSize: 12)),
                      )
                    : const CircularProgressIndicator(color: R.gold))
            : ListView(
                padding: kScreenPad,
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Requirements')),
                      ButtonSegment(value: 1, label: Text('Deficiencies')),
                    ],
                    selected: {seg},
                    onSelectionChanged: (s) => setState(() => seg = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (seg == 0) ..._requirements() else ..._deficiencies(),
                  const SizedBox(height: 16),
                  _sourceNote(),
                ],
              ),
      ),
    );
  }

  // ------------------------------------------------------------ requirements ----
  List<Widget> _requirements() {
    final groups = (data!['groups'] as List?) ?? const [];
    final matched = data!['matched'] as Map?;
    final families = ['All', 'Man', 'Woman', 'Child', 'Boy', 'Girl', 'Infant'];
    final shown = filter == 'All'
        ? groups
        : groups.where((g) => g['group'] == filter).toList();

    return [
      if (matched != null) ...[
        _matchedCard(matched),
        const SizedBox(height: 16),
      ],
      if ((data!['reconciliation'] as List?)?.isNotEmpty ?? false) ...[
        _reconciliationCard(),
        const SizedBox(height: 16),
      ],
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in families)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f),
                  selected: filter == f,
                  selectedColor: R.gold.withValues(alpha: .25),
                  onSelected: (_) => setState(() => filter = f),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ...shown.map((g) => _groupCard(g as Map,
          isMatch: matched != null &&
              g['group'] == matched['group'] &&
              g['stage'] == matched['stage'])),
    ];
  }

  Widget _matchedCard(Map m) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: R.gold.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: R.gold.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.memberName.toUpperCase()} · YOUR REFERENCE GROUP',
                style: const TextStyle(color: R.gold, fontSize: 10.5, letterSpacing: 1.1)),
            const SizedBox(height: 6),
            Text('${m['group']} · ${m['stage']}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Row(children: [
              _big('${m['kcal'] ?? '—'}', 'kcal'),
              _big('${m['protein_g'] ?? '—'}', 'protein g'),
              _big('${m['iron_mg'] ?? '—'}', 'iron mg'),
              _big('${m['calcium_mg'] ?? '—'}', 'calcium mg'),
            ]),
            if ('${m['note'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${m['note']}',
                  style: const TextStyle(color: R.muted, fontSize: 11, height: 1.35)),
            ],
          ],
        ),
      );

  /// Why this table and the app's own targets can disagree. Shown up front rather than
  /// buried, because the alternative is a reader spotting two different numbers for the
  /// same nutrient and trusting neither.
  Widget _reconciliationCard() {
    final rows = (data!['reconciliation'] as List?) ?? const [];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: R.violet.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: R.violet.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.compare_arrows, size: 15, color: R.violet),
            SizedBox(width: 7),
            Text('WHY YOUR TARGETS DIFFER FROM THIS TABLE',
                style: TextStyle(color: R.violet, fontSize: 10.5, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          Text('${data!['reconciliation_note'] ?? ''}',
              style: const TextStyle(fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: const [
            Expanded(flex: 4, child: Text('NUTRIENT',
                style: TextStyle(color: R.muted, fontSize: 9.5, letterSpacing: .8))),
            Expanded(flex: 4, child: Text('THIS TABLE',
                style: TextStyle(color: R.muted, fontSize: 9.5, letterSpacing: .8))),
            Expanded(flex: 4, child: Text('YOUR PLAN',
                style: TextStyle(color: R.muted, fontSize: 9.5, letterSpacing: .8))),
          ]),
          const Divider(color: R.line, height: 12),
          for (final r in rows) ...[
            Row(children: [
              Expanded(flex: 4,
                  child: Text('${r['nutrient']}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              Expanded(flex: 4,
                  child: Text('${r['table']}', style: const TextStyle(fontSize: 11.5, color: R.muted))),
              Expanded(flex: 4,
                  child: Text('${r['planning']}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: R.violet))),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 9),
              child: Text('${r['why']}',
                  style: const TextStyle(color: R.muted, fontSize: 10.5, height: 1.35)),
            ),
          ],
          Text('Table edition: ${data!['edition'] ?? ''}',
              style: const TextStyle(color: R.muted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _big(String v, String label) => Expanded(
        child: Column(children: [
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: R.muted, fontSize: 9.5)),
        ]),
      );

  Widget _groupCard(Map g, {bool isMatch = false}) {
    final rows = <List<String>>[
      ['Energy', _v(g['kcal']), 'kcal'],
      ['Protein', _v(g['protein_g']), 'g'],
      ['Visible fat', _v(g['visible_fat_g']), 'g'],
      ['Calcium', _v(g['calcium_mg']), 'mg'],
      ['Iron', _v(g['iron_mg']), 'mg'],
      ['Vitamin A', _v(g['vit_a_ug']), 'µg'],
      ['Thiamin (B1)', _v(g['thiamin_mg']), 'mg'],
      ['Riboflavin (B2)', _v(g['riboflavin_mg']), 'mg'],
      ['Niacin (B3)', _v(g['niacin_mg']), 'mg'],
      ['Pyridoxine (B6)', _v(g['pyridoxine_mg']), 'mg'],
      ['Vitamin C', _v(g['vit_c_mg']), 'mg'],
      ['Folate', _v(g['folate_ug']), 'µg'],
      ['Vitamin B12', _v(g['b12_ug']), 'µg'],
      ['Magnesium', _v(g['magnesium_mg']), 'mg'],
      ['Zinc', _v(g['zinc_mg']), 'mg'],
    ].where((r) => r[1] != '—').toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: R.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isMatch ? R.gold.withValues(alpha: .5) : R.line),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text('${g['group']} · ${g['stage']}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text(
              [
                if (g['weight_kg'] != null) '${g['weight_kg']} kg',
                if (g['kcal'] != null) '${g['kcal']} kcal',
                if (g['protein_g'] != null) '${g['protein_g']} g protein',
              ].join(' · '),
              style: const TextStyle(color: R.muted, fontSize: 11),
            ),
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(r[0], style: const TextStyle(fontSize: 12))),
                    Text('${r[1]} ${r[2]}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              if ('${g['note'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${g['note']}',
                    style: const TextStyle(color: R.muted, fontSize: 11, height: 1.35)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _v(Object? o) => o == null ? '—' : '$o';

  // ------------------------------------------------------------ deficiencies ----
  List<Widget> _deficiencies() {
    final list = (data!['deficiencies'] as List?) ?? const [];
    return [
      const Text('What a shortfall causes',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 4),
      const Text('Each nutrient, the disorder its deficiency causes, who is most at risk, '
          'and the foods that supply it.',
          style: TextStyle(color: R.muted, fontSize: 11)),
      const SizedBox(height: 14),
      ...list.map((d) => _deficiencyCard(d as Map)),
    ];
  }

  Widget _deficiencyCard(Map d) {
    final fromGuidelines = d['source'] == 'DGI';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: R.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: R.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${d['nutrient']}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (fromGuidelines ? R.teal : R.violet).withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(fromGuidelines ? 'NIN guidelines' : 'clinical',
                    style: TextStyle(
                        color: fromGuidelines ? R.teal : R.violet,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${d['condition']}',
                style: const TextStyle(color: R.magenta, fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 8),
            Text('${d['effects']}',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 10),
            _line(Icons.people_outline, 'Most at risk', '${d['at_risk']}'),
            const SizedBox(height: 6),
            _line(Icons.restaurant_outlined, 'Food sources', '${d['foods']}'),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String label, String body) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: R.muted),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: R.muted, fontSize: 11.5, height: 1.35),
                children: [
                  TextSpan(text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _sourceNote() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('◆ ', style: TextStyle(color: R.teal, fontSize: 11)),
            Expanded(
              child: Text('${data!['source'] ?? ''}',
                  style: const TextStyle(color: R.muted, fontSize: 11, height: 1.35)),
            ),
          ]),
          if ('${data!['unit_note'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 12, color: R.muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text('${data!['unit_note']}',
                    style: const TextStyle(color: R.muted, fontSize: 10.5, height: 1.35)),
              ),
            ]),
          ],
        ],
      );
}
