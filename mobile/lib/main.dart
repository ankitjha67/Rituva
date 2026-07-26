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
  bool loading = true;
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
      final days = plan!['days'] as List;
      day = days.firstWhere((d) => d['date'] == ctx!['today'], orElse: () => days.first)
          as Map<String, dynamic>;
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
    if (a == null || ctx == null || loading) return;
    setState(() => loading = true);
    variant++;
    try {
      plan = await a.createPlan(memberId, days: 7, start: ctx!['today'] as String, variant: variant);
      final days = plan!['days'] as List;
      day = days.firstWhere((d) => d['date'] == ctx!['today'], orElse: () => days.first) as Map<String, dynamic>;
      offline = a.offline;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void _openChat() {
    if (offline || plan == null || day == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connect a server (Profile → Server) to chat about your meals.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      builder: (_) => MealChatSheet(
        api: api!,
        memberId: memberId,
        planId: plan!['plan_id'] as String,
        date: day!['date'] as String,
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
      TodayScreen(ctx: ctx!, targets: targets!, day: day!, plan: plan!, api: a, memberId: memberId),
      PlanScreen(plan: plan!, ctx: ctx!, api: a),
      DiscoverScreen(api: a, plan: plan!),
      InsightsScreen(plan: plan!, targets: targets!),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${ctx?['greeting'] ?? 'Rituva'}, ${member?['name'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text('${ctx?['today'] ?? ''} · ${ctx?['season'] ?? ''}',
                style: const TextStyle(color: R.muted, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Ask about meals',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: _openChat),
          IconButton(tooltip: 'Regenerate meals', icon: const Icon(Icons.refresh), onPressed: _regenerate),
        ],
      ),
      body: Column(
        children: [
          if (offline) const _OfflineBanner(),
          Expanded(child: IndexedStack(index: index, children: screens)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: R.bg2,
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Thin strip shown when the app is running on the bundled demo (no server).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: R.gold.withOpacity(.14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: const [
            Icon(Icons.cloud_off, size: 15, color: R.gold),
            SizedBox(width: 8),
            Expanded(
              child: Text('Offline demo — bundled sample plan. Connect your server in Profile → Server.',
                  style: TextStyle(color: R.gold, fontSize: 11.5)),
            ),
          ],
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
                  const Text('Server error', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(widget.error, textAlign: TextAlign.center, style: const TextStyle(color: R.muted, fontSize: 12)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(labelText: 'Server URL', hintText: 'http://192.168.1.5:8000'),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(onPressed: widget.onRetry, child: const Text('Retry')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => widget.onSaveServer(ctrl.text),
                        child: const Text('Save & reconnect'),
                      ),
                    ),
                  ]),
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

  @override
  void dispose() {
    urlCtrl.dispose();
    super.dispose();
  }

  void _editProfile(BuildContext context, Map<String, dynamic>? m) {
    if (widget.offline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connect a server (Server card below) to create or edit profiles.')));
      return;
    }
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
      padding: const EdgeInsets.all(16),
      children: [
        const Text('HOUSEHOLD', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: widget.members
              .map<Widget>((m) => ChoiceChip(
                    label: Text('${m['name']}'),
                    selected: m['id'] == widget.memberId,
                    selectedColor: R.gold.withOpacity(.25),
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
        // ---- Server URL ----
        const Text('SERVER', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
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
                          ? 'Offline — showing the bundled demo plan.'
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
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        urlCtrl.text = '';
                        widget.onSaveServer('');
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.onSaveServer(urlCtrl.text),
                      child: const Text('Save & reconnect'),
                    ),
                  ),
                ]),
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
