import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// Create or edit a full member profile: demographics + activity + goal + diet +
/// region prefs + conditions/diseases + foods to avoid + optional custom targets.
class ProfileEditScreen extends StatefulWidget {
  final RituvaApi api;
  final Map<String, dynamic>? member; // null = new profile
  final Future<void> Function() onSaved;
  const ProfileEditScreen({super.key, required this.api, required this.member, required this.onSaved});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController name, age, weight, height, kcal, protein, condCtrl, exclCtrl;
  String sex = 'M', goal = 'maintain', diet = 'lacto_veg';
  double pal = 1.55;
  final Set<String> regions = {};
  final List<String> conditions = [], excludes = [];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member ?? {};
    name = TextEditingController(text: '${m['name'] ?? ''}');
    age = TextEditingController(text: m['age'] != null ? '${m['age']}' : '');
    weight = TextEditingController(text: m['weight_kg'] != null ? '${m['weight_kg']}' : '');
    height = TextEditingController(text: m['height_cm'] != null ? '${m['height_cm']}' : '');
    final kt = (m['known_targets'] as Map?) ?? {};
    kcal = TextEditingController(text: kt['kcal'] != null ? '${kt['kcal']}' : '');
    protein = TextEditingController(text: kt['protein_g'] != null ? '${kt['protein_g']}' : '');
    condCtrl = TextEditingController();
    exclCtrl = TextEditingController();
    sex = '${m['sex'] ?? 'M'}';
    goal = '${m['goal'] ?? 'maintain'}';
    diet = '${m['diet_type'] ?? 'lacto_veg'}';
    pal = (m['pal'] as num?)?.toDouble() ?? 1.55;
    regions.addAll(((m['region_prefs'] as List?) ?? const []).map((e) => '$e'));
    conditions.addAll(((m['conditions'] as List?) ?? const []).map((e) => '$e'));
    excludes.addAll(((m['excludes'] as List?) ?? const []).map((e) => '$e'));
  }

  @override
  void dispose() {
    for (final c in [name, age, weight, height, kcal, protein, condCtrl, exclCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final nm = name.text.trim();
    if (nm.isEmpty) {
      _snack('Please enter a name');
      return;
    }
    final id = (widget.member?['id'] ??
            nm.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'(^_+|_+$)'), ''))
        .toString();
    final kt = <String, dynamic>{};
    if (int.tryParse(kcal.text.trim()) != null) kt['kcal'] = int.parse(kcal.text.trim());
    if (double.tryParse(protein.text.trim()) != null) kt['protein_g'] = double.parse(protein.text.trim());
    final body = <String, dynamic>{
      'id': id.isEmpty ? 'user' : id,
      'name': nm,
      'sex': sex,
      'age': int.tryParse(age.text.trim()) ?? 30,
      'weight_kg': double.tryParse(weight.text.trim()) ?? 65,
      'height_cm': double.tryParse(height.text.trim()) ?? 165,
      'pal': pal,
      'goal': goal,
      'diet_type': diet,
      'region_prefs': regions.toList(),
      'conditions': conditions,
      'excludes': excludes,
      'known_targets': kt.isEmpty ? null : kt,
    };
    setState(() => saving = true);
    try {
      await widget.api.saveMember(body);
      await widget.onSaved();
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        _snack('$e');
      }
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: R.bg,
        title: Text(widget.member == null ? 'New profile' : 'Edit profile'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(name, 'Name'),
          const SizedBox(height: 12),
          _label('Sex'),
          _chips(['M', 'F'], sex, (v) => setState(() => sex = v), (v) => v == 'M' ? 'Male' : 'Female'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _tf(age, 'Age', num: true)),
            const SizedBox(width: 8),
            Expanded(child: _tf(weight, 'Weight kg', num: true)),
            const SizedBox(width: 8),
            Expanded(child: _tf(height, 'Height cm', num: true)),
          ]),
          const SizedBox(height: 14),
          _label('Activity level'),
          _chips(['1.2', '1.375', '1.55', '1.725'], pal.toString(), (v) => setState(() => pal = double.parse(v)),
              (v) => const {'1.2': 'Sedentary', '1.375': 'Light', '1.55': 'Moderate', '1.725': 'Active'}[v]!),
          const SizedBox(height: 14),
          _label('Goal'),
          _chips(['lose', 'maintain', 'gain', 'muscle'], goal, (v) => setState(() => goal = v), humanize),
          const SizedBox(height: 14),
          _label('Diet'),
          _chips(const ['lacto_veg', 'lacto_ovo', 'vegan', 'jain', 'pescatarian', 'nonveg'], diet,
              (v) => setState(() => diet = v),
              (v) => const {'lacto_veg': 'Lacto-veg', 'lacto_ovo': 'Ovo-veg', 'vegan': 'Vegan',
                    'jain': 'Jain', 'pescatarian': 'Pescatarian', 'nonveg': 'Non-veg'}[v] ?? v),
          const SizedBox(height: 14),
          _label('Region preferences (pick any)'),
          Wrap(
            spacing: 8,
            children: ['north', 'south', 'east', 'west']
                .map((r) => FilterChip(
                      label: Text(humanize(r)),
                      selected: regions.contains(r),
                      selectedColor: R.gold.withOpacity(.25),
                      onSelected: (s) => setState(() => s ? regions.add(r) : regions.remove(r)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          _label('Conditions / diseases'),
          _editChips(conditions, condCtrl, 'e.g. diabetes, hypertension, thyroid'),
          const SizedBox(height: 14),
          _label('Foods to avoid'),
          _editChips(excludes, exclCtrl, 'e.g. mushroom, brinjal'),
          const SizedBox(height: 14),
          _label('Custom daily targets (optional — overrides computed)'),
          Row(children: [
            Expanded(child: _tf(kcal, 'kcal', num: true)),
            const SizedBox(width: 8),
            Expanded(child: _tf(protein, 'protein g', num: true)),
          ]),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving…' : 'Save profile'),
          ),
          const SizedBox(height: 30),
        ],
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s.toUpperCase(), style: const TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.1)),
      );

  Widget _tf(TextEditingController c, String label, {bool num = false}) => TextField(
        controller: c,
        keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  Widget _chips(List<String> opts, String sel, void Function(String) onSel, String Function(String) lbl) =>
      Wrap(
        spacing: 8,
        children: opts
            .map((o) => ChoiceChip(
                  label: Text(lbl(o)),
                  selected: sel == o,
                  selectedColor: R.gold.withOpacity(.25),
                  onSelected: (_) => onSel(o),
                ))
            .toList(),
      );

  Widget _editChips(List<String> items, TextEditingController ctrl, String hint) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                children: items
                    .map((v) => InputChip(
                          label: Text(humanize(v)),
                          onDeleted: () => setState(() => items.remove(v)),
                        ))
                    .toList(),
              ),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: InputDecoration(hintText: hint, isDense: true),
                onSubmitted: (_) => _add(items, ctrl),
              ),
            ),
            IconButton(icon: const Icon(Icons.add, color: R.gold), onPressed: () => _add(items, ctrl)),
          ]),
        ],
      );

  void _add(List<String> items, TextEditingController ctrl) {
    final v = ctrl.text.trim().toLowerCase();
    if (v.isNotEmpty && !items.contains(v)) setState(() => items.add(v));
    ctrl.clear();
  }
}
