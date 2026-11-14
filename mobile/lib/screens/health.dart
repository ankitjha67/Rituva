import 'package:flutter/material.dart';
import '../api.dart';
import '../engine/activity.dart';
import '../theme.dart';
import 'reference.dart';

class HealthScreen extends StatefulWidget {
  final Map<String, dynamic> member, targets, anthro;
  final RituvaApi api;
  final String memberId;
  final Future<void> Function() onChanged;
  const HealthScreen({
    super.key,
    required this.member,
    required this.targets,
    required this.anthro,
    required this.api,
    required this.memberId,
    required this.onChanged,
  });

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final ctrl = TextEditingController();
  Map<String, dynamic>? mem;

  @override
  void initState() {
    super.initState();
    _loadMem();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadMem() async {
    mem = await widget.api.memory(widget.memberId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.targets;
    final a = widget.anthro;
    final conds = (widget.member['conditions'] as List?) ?? const [];
    final never = [
      ...(((mem?['memory']?['never']) as List?) ?? const []),
      ...(((mem?['memory']?['dislike']) as List?) ?? const []),
    ];
    return ListView(
      padding: kScreenPad,
      children: [
        // Reference tables: what every age/sex actually needs per day, and what a
        // shortfall of each nutrient causes.
        Card(
          color: R.surface,
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined, color: R.gold),
            title: const Text('Daily requirements & deficiencies',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: const Text('ICMR-NIN allowances for men, women and children — and '
                'what each deficiency causes',
                style: TextStyle(color: R.muted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: R.muted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReferenceScreen(
                  api: widget.api,
                  memberId: widget.memberId,
                  memberName: '${widget.member['name'] ?? ''}',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _MeasuredActivityCard(
          api: widget.api,
          member: widget.member,
          memberId: widget.memberId,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 10),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DAILY TARGETS · ${humanize(t['source'] as String?)}',
                    style: const TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                // IntrinsicHeight + stretch so all three boxes are the same height even when
                // one label (e.g. "BMI · Overweight") wraps to two lines.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stat('${a['bmi']}', 'BMI · ${a['bmi_category']}'),
                      _stat('${t['kcal']}', 'kcal'),
                      _stat('${t['protein_g']}', 'protein g'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sodium ≤${(t['sodium_mg_max'] as num).round()} mg · added sugar ≤${(t['added_sugar_g_max'] as num).round()} g\n'
                  '${(t['citations'] as List).join(', ')}',
                  style: const TextStyle(color: R.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONDITIONS', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: conds.isEmpty
                      ? const [Text('none', style: TextStyle(color: R.muted))]
                      : conds.map<Widget>((c) => Chip(label: Text(humanize('$c')))).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NEVER / DISLIKED — shapes every plan',
                    style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: never.isEmpty
                      ? const [Text('nothing excluded yet', style: TextStyle(color: R.muted, fontSize: 12))]
                      : never
                          .map<Widget>((v) => InputChip(
                                label: Text('$v'),
                                onDeleted: () async {
                                  try {
                                    await widget.api.removeMemory(widget.memberId, 'never', '$v');
                                    await widget.api.removeMemory(widget.memberId, 'dislike', '$v');
                                    await _loadMem();
                                    await widget.onChanged();
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(content: Text('$e')));
                                    }
                                  }
                                },
                              ))
                          .toList(),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(hintText: 'e.g. mushroom, paneer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final v = ctrl.text.trim().toLowerCase();
                      if (v.isEmpty) return;
                      try {
                        await widget.api.addMemory(widget.memberId, 'never', v);
                        ctrl.clear();
                        await _loadMem();
                        await widget.onChanged();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: const Text('Never'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String big, String label) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: R.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: R.line),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(big, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: R.muted, fontSize: 9.5)),
          ]),
        ),
      );
}

/// Reads today's steps / active-energy from Health Connect on demand and offers to
/// set the profile's activity level to the measured one (which recomputes targets
/// and the plan). Optional by design: if Health Connect isn't set up the card just
/// explains how, and nothing in the standalone app depends on it.
class _MeasuredActivityCard extends StatefulWidget {
  final RituvaApi api;
  final Map<String, dynamic> member;
  final String memberId;
  final Future<void> Function() onChanged;
  const _MeasuredActivityCard(
      {required this.api,
      required this.member,
      required this.memberId,
      required this.onChanged});
  @override
  State<_MeasuredActivityCard> createState() => _MeasuredActivityCardState();
}

class _MeasuredActivityCardState extends State<_MeasuredActivityCard> {
  bool _loading = false, _read = false, _applying = false;
  MeasuredActivity? _data;

  Future<void> _readToday() async {
    setState(() => _loading = true);
    final d = await HealthConnect.today();
    if (mounted) {
      setState(() {
        _loading = false;
        _read = true;
        _data = d;
      });
    }
  }

  Future<void> _apply(MeasuredActivity m) async {
    setState(() => _applying = true);
    try {
      await widget.api.saveMember({...widget.member, 'pal': m.pal});
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Activity set to ${m.label} (${m.steps} steps) — targets updated.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')));
      }
    }
    if (mounted) setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Card(
      color: R.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.directions_walk, size: 16, color: R.teal),
            SizedBox(width: 8),
            Expanded(
              child: Text('MEASURED ACTIVITY · HEALTH CONNECT',
                  style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.1)),
            ),
          ]),
          const SizedBox(height: 8),
          if (d != null) ...[
            Text(
              '${d.steps} steps today'
              '${d.activeKcal > 0 ? ' · ${d.activeKcal.round()} kcal active' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text('That maps to ${d.label} activity.',
                style: const TextStyle(color: R.muted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _applying ? null : () => _apply(d),
                icon: _applying
                    ? const SizedBox(
                        width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.tune, size: 18),
                label: Text('Set activity to ${d.label}'),
              ),
            ),
          ] else ...[
            Text(
              _read
                  ? 'No Health Connect data yet. Open your fitness app so it syncs today\'s steps, then try again.'
                  : 'Use your phone or wearable steps (via Health Connect) to set a measured activity level — it updates your energy target.',
              style: const TextStyle(color: R.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _readToday,
                style: OutlinedButton.styleFrom(
                    foregroundColor: R.teal, side: const BorderSide(color: R.line)),
                icon: _loading
                    ? const SizedBox(
                        width: 15, height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: R.teal))
                    : const Icon(Icons.sync, size: 18),
                label: Text(_loading ? 'Reading…' : "Read today's activity"),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
