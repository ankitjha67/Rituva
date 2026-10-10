import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'screens/today.dart';
import 'screens/plan.dart';
import 'screens/discover.dart';
import 'screens/insights.dart';
import 'screens/health.dart';
import 'screens/profile_edit.dart';
import 'screens/meal_chat.dart';

void main() => runApp(const RituvaApp());

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
  bool loading = true;   // full-screen: first load & member switch
  bool busy = false;     // inline: regenerate — keeps the UI mounted
  bool offline = false;
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
      a.offline = false;      // re-probe the server on every (re)load
      await a.reachable();    // fast-fail to the offline demo if unreachable (~2s, not ~20s of retries)
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
      offline = a.offline;
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

  Future<void> _saveServer(String url) async {
    await api?.setBaseUrl(url);
    await _load();
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
      offline = a.offline;
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
      _snack('Add your NVIDIA key in Profile → Assistant to chat.');
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
    if (error != null) {
      return _ErrorScreen(
        error: error!,
        serverUrl: api?.baseUrl ?? RituvaApi.defaultUrl,
        onRetry: _load,
        onSaveServer: _saveServer,
      );
    }
    final a = api!;
    final screens = [
      TodayScreen(
          ctx: ctx!,
          targets: targets!,
          day: day!,
          plan: plan!,
          api: a,
          memberId: memberId,
          onRegenerate: _regenerate,
          regenerating: busy,
          onApplySwap: _applySwap),
      PlanScreen(plan: plan!, ctx: ctx!, api: a, onRegenerate: _regenerate, regenerating: busy),
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
        serverUrl: a.baseUrl,
        offline: offline,
        onSaveServer: _saveServer,
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
          // Only nudge about a server when one is actually configured but unreachable.
          // With no server (standalone) the on-device engine is the whole app, not a fallback.
          if (offline && a.hasServer) _OfflineBanner(onTap: () => setState(() => index = 5)),
          Expanded(child: IndexedStack(index: index, children: screens)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: R.bg2,
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => setState(() {
          if (i == 3 && index != 3) _insVisit++; // re-mount Analytics so its charts animate in
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

/// Thin strip shown when the app is running on the bundled demo (no server).
/// Tapping it jumps straight to the Server settings so the fix is one tap away.
class _OfflineBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _OfflineBanner({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: R.gold.withValues(alpha: .14),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: const [
                Icon(Icons.cloud_off, size: 15, color: R.gold),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Offline — menus planned on this phone. Tap for server settings.',
                      style: TextStyle(color: R.gold, fontSize: 11.5)),
                ),
                Icon(Icons.chevron_right, size: 16, color: R.gold),
              ],
            ),
          ),
        ),
      );
}

/// Friendly connection screen (only shown for real server errors — network
/// failures fall back to the offline demo instead of erroring).
class _ErrorScreen extends StatefulWidget {
  final String error;
  final String serverUrl;
  final Future<void> Function() onRetry;
  final Future<void> Function(String) onSaveServer;
  const _ErrorScreen({
    required this.error,
    required this.serverUrl,
    required this.onRetry,
    required this.onSaveServer,
  });
  @override
  State<_ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<_ErrorScreen> {
  late final TextEditingController ctrl = TextEditingController(text: widget.serverUrl);
  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

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
                  Text(widget.error, textAlign: TextAlign.center, style: const TextStyle(color: R.muted, fontSize: 12)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: R.line),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Using a Rituva server? (optional)',
                        style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: .5)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(labelText: 'Server URL', hintText: 'http://192.168.1.5:8000'),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onSaveServer(ctrl.text),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Save & connect'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Profile: member switch, provenance, and the backend Server URL setting.
class ProfileScreen extends StatefulWidget {
  final RituvaApi api;
  final List members;
  final String memberId;
  final Map<String, dynamic> member;
  final Map<String, dynamic> plan;
  final Future<void> Function(String) onSwitch;
  final Future<void> Function() onSaved;
  final String serverUrl;
  final bool offline;
  final Future<void> Function(String) onSaveServer;
  const ProfileScreen({
    super.key,
    required this.api,
    required this.members,
    required this.memberId,
    required this.member,
    required this.plan,
    required this.onSwitch,
    required this.onSaved,
    required this.serverUrl,
    required this.offline,
    required this.onSaveServer,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController urlCtrl = TextEditingController(text: widget.serverUrl);
  late final TextEditingController keyCtrl = TextEditingController(text: widget.api.nvidiaKey);
  bool _showKey = false;
  Map<String, dynamic>? lib;
  bool syncing = false;

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
    urlCtrl.dispose();
    keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await widget.api.setNvidiaKey(keyCtrl.text);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(widget.api.hasLLM ? 'Assistant key saved.' : 'Assistant key cleared.'),
      ));
    }
  }

  Future<void> _download() async {
    setState(() => syncing = true);
    try {
      final r = await widget.api.downloadLibrary();
      await _loadLib();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Saved ${r['recipes']} dishes and ${r['foods']} foods for offline use.'),
        ));
      }
      await widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not download: $e'),
        ));
      }
    }
    if (mounted) setState(() => syncing = false);
  }

  void _editProfile(BuildContext context, Map<String, dynamic>? m) {
    // Profiles save to the device when there's no server, so this works either way.
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ProfileEditScreen(api: widget.api, member: m, onSaved: widget.onSaved)),
    );
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
        const SizedBox(height: 18),
        // ---- Offline library ----
        const Text('OFFLINE LIBRARY',
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
                  Icon(lib?['full'] == true ? Icons.offline_pin : Icons.offline_bolt,
                      size: 16, color: lib?['full'] == true ? R.green : R.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lib == null
                          ? 'Checking…'
                          : '${lib!['recipes']} dishes · ${lib!['foods']} foods on this phone'
                              '${lib!['full'] == true ? ' (downloaded)' : ' (built in)'}',
                      style: TextStyle(
                          color: lib?['full'] == true ? R.green : R.teal, fontSize: 12),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'The whole library ships inside the app — menus, swaps, recipes, groceries '
                  'and analytics are all computed on this phone, with no server. Re-sync only '
                  'if you add dishes or pre-write more recipes on the server.',
                  style: TextStyle(color: R.muted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: syncing ? null : _download,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: R.teal, side: const BorderSide(color: R.line)),
                    icon: syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: R.teal))
                        : const Icon(Icons.sync, size: 18),
                    label: Text(syncing ? 'Syncing…' : 'Re-sync from server'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // ---- Assistant (NVIDIA key, standalone LLM) ----
        const Text('ASSISTANT', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Card(
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
                          ? 'Assistant ready — it runs directly on NVIDIA, no server needed.'
                          : 'Add your NVIDIA API key to enable the in-app assistant.',
                      style: TextStyle(
                          color: widget.api.hasLLM ? R.green : R.muted, fontSize: 12),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: keyCtrl,
                  obscureText: !_showKey,
                  decoration: InputDecoration(
                    labelText: 'NVIDIA API key',
                    hintText: 'nvapi-…',
                    suffixIcon: IconButton(
                      icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Get a free key at build.nvidia.com. Stored only on this phone — it powers the '
                  'chat assistant. Leave blank to turn the assistant off.',
                  style: TextStyle(color: R.muted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saveKey,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save key'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // ---- Server URL (optional — the app is standalone by default) ----
        const Text('SERVER (OPTIONAL)',
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
                  Icon(widget.offline ? Icons.cloud_off : Icons.cloud_done,
                      size: 16, color: widget.offline ? R.gold : R.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.offline
                          ? 'No server — everything is computed on this phone.'
                          : 'Connected to ${widget.serverUrl}',
                      style: TextStyle(color: widget.offline ? R.gold : R.green, fontSize: 12),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'http://192.168.1.5:8000',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Run the Rituva backend, then enter its address. On the same Wi-Fi, '
                  'use your PC\'s LAN IP (e.g. http://192.168.1.5:8000). Leave blank to reset.',
                  style: TextStyle(color: R.muted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => widget.onSaveServer(urlCtrl.text),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Save & reconnect'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      urlCtrl.text = '';
                      widget.onSaveServer('');
                    },
                    child: const Text('Reset to default'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
