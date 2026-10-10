import 'package:flutter/material.dart';
import '../api.dart';
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
