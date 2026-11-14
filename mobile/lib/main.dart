import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'api.dart';
import 'theme.dart';
import 'screens/today.dart';
import 'screens/plan.dart';
import 'screens/discover.dart';
import 'screens/insights.dart';
import 'screens/health.dart';
import 'screens/profile_edit.dart';
import 'screens/meal_chat.dart';
import 'screens/scan_screen.dart';
import 'engine/llm.dart';

void main() {
  // Hold the native splash until the first loaded frame paints, so the Today
  // screen's entrance animations are seen from the start instead of running
  // (and finishing) behind the splash during engine warm-up.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  runApp(const RituvaApp());
}

class RituvaApp extends StatelessWidget {
  const RituvaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Rituva',
        debugShowCheckedModeBanner: false,
        theme: R.theme(),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  RituvaApi? api;
  int index = 0;
  int _insVisit = 0; // bumps when Analytics is opened, so its charts re-animate each visit
  int _homeVisit = 0; // bumps when Today is opened, so its hero card re-animates each visit
  bool _splashGone = false; // native splash removed once, after the first loaded frame
  bool loading = true;   // full-screen: first load & member switch
  bool busy = false;     // inline: regenerate — keeps the UI mounted
  String? error;
  String memberId = 'aarav';
  int variant = 0;
  Map<String, dynamic>? ctx, member, targets, anthro, plan, day;
  List members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      api ??= await RituvaApi.create();
      final a = api!;
      ctx = await a.context();
      members = await a.members();
      member = await a.member(memberId);
      final t = await a.targets(memberId);
      targets = t['targets'] as Map<String, dynamic>;
      anthro = t['anthropometry'] as Map<String, dynamic>;
      plan = await a.createPlan(memberId, days: 7, start: ctx!['today'] as String, variant: variant);
      // .cast is load-bearing: the on-device engine returns a typed List<Map>, and a loose
      // `orElse: () => days.first` (dynamic) then fails firstWhere's runtime type check.
      final days = (plan!['days'] as List).cast<Map<String, dynamic>>();
      if (days.isEmpty) throw StateError('plan returned no days');
      day = days.firstWhere((d) => d['date'] == ctx!['today'], orElse: () => days.first);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _switchMember(String id) async {
    memberId = id;
    await _load();
    if (mounted) setState(() => index = 0);
  }

  Future<void> _regenerate() async {
    final a = api;
    if (a == null || ctx == null || loading || busy) return;
    setState(() => busy = true);   // inline — the screen stays mounted, a thin bar shows progress
    variant++;
    try {
      final fresh = await a.createPlan(memberId, days: 7, start: ctx!['today'] as String, variant: variant);
      final days = (fresh['days'] as List).cast<Map<String, dynamic>>();
      plan = fresh;
      day = days.firstWhere((d) => d['date'] == ctx!['today'], orElse: () => days.first);
      if (mounted) _snack('Fresh menu ready — a new mix of dishes for the week.');
    } catch (e) {
      if (mounted) _snack('Could not regenerate: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating));

  /// Apply an iso-nutrient swap to today's menu: replace the declined dish in its meal
  /// with the chosen alternative, then recompute the meal's and the day's totals from the
  /// DB numbers the engine already attached. `day` is the same object the plan holds, so
  /// Plan / Analytics / Grocery all reflect the swap too.
  void _applySwap(String slot, String declinedId, Map<String, dynamic> alt) {
    final d = day;
    if (d == null) return;
    const keys = ['kcal', 'protein', 'carb', 'fat', 'fibre', 'iron', 'calcium', 'b12', 'sodium'];
    Map<String, dynamic> sum(Iterable<Map> maps) {
      final out = <String, dynamic>{for (final k in keys) k: 0.0};
      for (final n in maps) {
        for (final k in keys) {
          out[k] = (out[k] as double) + ((n[k] as num?)?.toDouble() ?? 0);
        }
      }
      return out;
    }

    var applied = false;
    for (final e in (d['entries'] as List)) {
      if (e['slot'] != slot) continue;
      final comps = e['components'] as List;
      for (var i = 0; i < comps.length; i++) {
        if ('${comps[i]['recipe_id']}' == declinedId) {
          comps[i] = {
            'recipe_id': alt['recipe_id'],
            'name': alt['name'],
            'region': alt['region'],
            'nutrients': alt['nutrients'],
            'ingredients': alt['ingredients'] ?? const [],
          };
          applied = true;
          break;
        }
      }
      if (applied) {
        e['nutrients'] = sum((comps).map((c) => (c['nutrients'] as Map?) ?? const {}));
        break;
      }
    }
    if (!applied) return;
    d['totals'] = sum((d['entries'] as List).map((e) => (e['nutrients'] as Map?) ?? const {}));
    setState(() {});
    _snack('Swapped in ${alt['name']} for today.');
  }

  void _openChat() {
    final a = api;
    if (a == null || plan == null || member == null || targets == null) return;
    if (!a.hasLLM) {
      _snack('Choose an LLM provider and add your key in Profile → Assistant to chat.');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MealChatSheet(
        api: a,
        memberId: memberId,
        member: member!,
        targets: targets!,
        plan: plan!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: R.gold)));
    }
    // Lift the native splash one frame after the first non-loading UI paints
    // (success or error), so the Today entrance animation is visible from its
    // start instead of running behind the splash — and we never get stuck on it.
    if (!_splashGone) {
      _splashGone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => FlutterNativeSplash.remove());
    }
    if (error != null) {
      return _ErrorScreen(error: error!, onRetry: _load);
    }
    final a = api!;
    final screens = [
      TodayScreen(
          key: ValueKey('today-$_homeVisit'),
          ctx: ctx!,
          targets: targets!,
          day: day!,
          plan: plan!,
          api: a,
          memberId: memberId,
          onRegenerate: _regenerate,
          regenerating: busy,
          onApplySwap: _applySwap),
      PlanScreen(plan: plan!, ctx: ctx!, member: member!, api: a, onRegenerate: _regenerate, regenerating: busy),
      DiscoverScreen(api: a, plan: plan!),
      InsightsScreen(
          key: ValueKey('insights-$_insVisit'),
          plan: plan!,
          targets: targets!,
          anthro: anthro!,
          ctx: ctx!),
      HealthScreen(member: member!, targets: targets!, anthro: anthro!, api: a, memberId: memberId, onChanged: _load),
      ProfileScreen(
        api: a,
        members: members,
        memberId: memberId,
        member: member!,
        plan: plan!,
        onSwitch: _switchMember,
        onSaved: _load,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: R.bg,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${ctx?['greeting'] ?? 'Rituva'}, ${member?['name'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text('${prettyDate(ctx?['today'])} · ${humanize('${ctx?['season'] ?? ''}')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: R.muted, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Scan a barcode',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => BarcodeScan.open(context, targets: targets)),
          IconButton(
              tooltip: 'Ask about meals',
              icon: const Icon(Icons.forum_outlined),
              onPressed: _openChat),
          IconButton(
            tooltip: 'Regenerate menu',
            onPressed: busy ? null : _regenerate,
            icon: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: R.gold))
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2, color: R.gold, backgroundColor: R.line),
          Expanded(child: IndexedStack(index: index, children: screens)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: R.bg2,
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => setState(() {
          if (i == 3 && index != 3) _insVisit++; // re-mount Analytics so its charts animate in
          if (i == 0 && index != 0) _homeVisit++; // re-mount Today so its hero card re-animates
          index = i;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analytics'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Shown only if the on-device engine can't produce a plan (rare — e.g. corrupt
/// stored data). It offers a retry; the app is standalone, so there is no server
/// to fall back to or configure.
class _ErrorScreen extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _ErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: R.gold, size: 40),
                  const SizedBox(height: 12),
                  const Text("Couldn't load", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(error, textAlign: TextAlign.center, style: const TextStyle(color: R.muted, fontSize: 12)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Profile: member switch, the on-device library, the assistant key, and provenance.
class ProfileScreen extends StatefulWidget {
  final RituvaApi api;
  final List members;
  final String memberId;
  final Map<String, dynamic> member;
  final Map<String, dynamic> plan;
  final Future<void> Function(String) onSwitch;
  final Future<void> Function() onSaved;
  const ProfileScreen({
    super.key,
    required this.api,
    required this.members,
    required this.memberId,
    required this.member,
    required this.plan,
    required this.onSwitch,
    required this.onSaved,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late String _provId = widget.api.providerId;
  late final TextEditingController keyCtrl = TextEditingController(text: widget.api.llmKey(_provId));
  late final TextEditingController baseCtrl = TextEditingController(text: widget.api.llmBase(_provId));
  late final TextEditingController modelCtrl = TextEditingController(text: widget.api.llmModel(_provId));
  bool _showKey = false;
  Map<String, dynamic>? lib;

  @override
  void initState() {
    super.initState();
    _loadLib();
  }

  Future<void> _loadLib() async {
    try {
      final v = await widget.api.libraryInfo();
      if (mounted) setState(() => lib = v);
    } catch (_) {/* engine unavailable — card just shows nothing */}
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    baseCtrl.dispose();
    modelCtrl.dispose();
    super.dispose();
  }

  // Switch provider: repopulate the fields with that provider's saved settings.
  void _onProvider(String id) => setState(() {
        _provId = id;
        keyCtrl.text = widget.api.llmKey(id);
        baseCtrl.text = widget.api.llmBase(id);
        modelCtrl.text = widget.api.llmModel(id);
      });

  Future<void> _saveAssistant() async {
    await widget.api.setLlmProvider(_provId);
    await widget.api.setLlmSettings(_provId,
        key: keyCtrl.text, base: baseCtrl.text, model: modelCtrl.text);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(widget.api.hasLLM ? 'Assistant saved.' : 'Assistant settings cleared.'),
      ));
    }
  }

  String _assistantHint(LlmProvider p) {
    switch (p.id) {
      case 'nvidia':
        return 'Free key at build.nvidia.com. Stored only on this phone.';
      case 'openai':
        return 'Key from platform.openai.com. Stored only on this phone.';
      case 'anthropic':
        return 'Key from console.anthropic.com. Stored only on this phone.';
      case 'gemini':
        return 'Key from aistudio.google.com. Stored only on this phone.';
      case 'ollama':
        return "Run Ollama locally; set its URL (on Android use your PC's LAN IP). No key needed.";
      case 'nim':
        return 'Point at your self-hosted NVIDIA NIM endpoint (…/v1). Key optional.';
      case 'custom':
        return 'Any OpenAI-compatible endpoint (Groq, LM Studio, vLLM, …): set base URL + model.';
      default:
        return 'Key stored only on this phone. Leave blank to turn the assistant off.';
    }
  }

  void _editProfile(BuildContext context, Map<String, dynamic>? m) {
    // Profiles save to the device when there's no server, so this works either way.
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ProfileEditScreen(api: widget.api, member: m, onSaved: widget.onSaved)),
    );
  }

  /// Delete the current profile (any profile, including the built-in defaults),
  /// after a confirm. Switches to a remaining profile so the app never lands on
  /// an empty household.
  Future<void> _deleteProfile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (widget.members.length <= 1) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Add another profile before deleting this one.'),
      ));
      return;
    }
    final name = '${widget.member['name']}';
    final deletedId = widget.memberId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: R.bg2,
        title: const Text('Delete profile?'),
        content: Text(
            "$name's profile and saved details will be removed from this phone. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: R.magenta, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteMember(deletedId);
      // Hand off to a remaining profile; the parent reloads the whole app for it.
      final remaining = widget.members.firstWhere((m) => m['id'] != deletedId);
      await widget.onSwitch(remaining['id'] as String);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text("Deleted $name's profile."),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = (widget.plan['provenance'] as Map?) ?? {};
    return ListView(
      padding: kScreenPad,
      children: [
        const Text('HOUSEHOLD', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: widget.members
              .map<Widget>((m) => ChoiceChip(
                    label: Text('${m['name']}'),
                    selected: m['id'] == widget.memberId,
                    selectedColor: R.gold.withValues(alpha: .25),
                    onSelected: (_) => widget.onSwitch(m['id'] as String),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.member['name']} · ${humanize('${widget.member['diet_type']}')} · ${humanize('${widget.member['goal']}')}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  'Age ${widget.member['age']} · ${widget.member['weight_kg']}kg · ${widget.member['height_cm']}cm'
                  '${(widget.member['conditions'] as List?)?.isNotEmpty == true ? ' · ${(widget.member['conditions'] as List).map((c) => humanize('$c')).join(', ')}' : ''}',
                  style: const TextStyle(color: R.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _editProfile(context, widget.member),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit profile'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _editProfile(context, null),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('New profile'),
            ),
          ),
        ]),
        // Delete the current profile (defaults included). Hidden when it's the
        // only one left, since the app must keep at least one member.
        if (widget.members.length > 1) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _deleteProfile(context),
              style: TextButton.styleFrom(foregroundColor: R.magenta),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text("Delete ${widget.member['name']}'s profile"),
            ),
          ),
        ],
        const SizedBox(height: 18),
        // ---- On-device library ----
        const Text('LIBRARY',
            style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.offline_bolt, size: 16, color: R.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lib == null
                          ? 'Checking…'
                          : '${lib!['recipes']} dishes · ${lib!['foods']} foods on this phone',
                      style: const TextStyle(color: R.teal, fontSize: 12),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'The whole library ships inside the app — menus, swaps, recipes, groceries '
                  'and analytics are all computed on this phone. No server or internet needed.',
                  style: TextStyle(color: R.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // ---- Assistant (any LLM provider; standalone, no server) ----
        const Text('ASSISTANT', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final prov = providerById(_provId);
          return Card(
            color: R.surface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(widget.api.hasLLM ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                        size: 16, color: widget.api.hasLLM ? R.green : R.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.api.hasLLM
                            ? 'Assistant ready — runs directly on ${prov.name}, no server.'
                            : 'Pick a provider and add your key to enable the assistant.',
                        style: TextStyle(color: widget.api.hasLLM ? R.green : R.muted, fontSize: 12),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Provider', isDense: true),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _provId,
                        dropdownColor: R.bg2,
                        items: [
                          for (final p in kLlmProviders)
                            DropdownMenuItem(value: p.id, child: Text(p.name))
                        ],
                        onChanged: (v) => v == null ? null : _onProvider(v),
                      ),
                    ),
                  ),
                  if (prov.needsKey || prov.id == 'nim' || prov.id == 'custom') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyCtrl,
                      obscureText: !_showKey,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: prov.needsKey ? 'API key' : 'API key (optional)',
                        hintText: prov.keyHint,
                        suffixIcon: IconButton(
                          icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setState(() => _showKey = !_showKey),
                        ),
                      ),
                    ),
                  ],
                  if (prov.userBase) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: baseCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Base URL',
                        hintText: prov.id == 'ollama' ? 'http://10.0.2.2:11434/v1' : 'https://host/v1',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: modelCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Model (optional)',
                      hintText: prov.model.isEmpty ? 'e.g. llama3.2' : prov.model,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_assistantHint(prov), style: const TextStyle(color: R.muted, fontSize: 11)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saveAssistant,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save assistant'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
        Card(
          color: R.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Menu engine: ${prov['llm_provider'] ?? 'none'} — deterministic core; '
              'numbers always from the DB. KB: ${prov['kb'] ?? ''}.',
              style: const TextStyle(color: R.muted, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text('Rituva · guideline-grounded · not medical advice',
              style: TextStyle(color: R.muted, fontSize: 11)),
        ),
      ],
    );
  }
}
