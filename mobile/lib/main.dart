import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'screens/today.dart';
import 'screens/plan.dart';
import 'screens/health.dart';

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
  final api = const RituvaApi();
  int index = 0;
  bool loading = true;
  String? error;
  String memberId = 'aarav';
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
      ctx = await api.context();
      members = await api.members();
      member = await api.member(memberId);
      final t = await api.targets(memberId);
      targets = t['targets'] as Map<String, dynamic>;
      anthro = t['anthropometry'] as Map<String, dynamic>;
      plan = await api.createPlan(memberId, days: 7, start: ctx!['today'] as String);
      final days = plan!['days'] as List;
      day = days.firstWhere((d) => d['date'] == ctx!['today'], orElse: () => days.first)
          as Map<String, dynamic>;
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

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: R.gold)));
    }
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Cannot reach the Rituva API.\n\n$error\n\n'
              'Start it with:\n  uvicorn rituva.api:app --host 0.0.0.0 --port 8000\n'
              '(emulator uses http://10.0.2.2:8000)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: R.muted),
            ),
          ),
        ),
      );
    }
    final screens = [
      TodayScreen(ctx: ctx!, targets: targets!, day: day!, plan: plan!, api: api, memberId: memberId),
      PlanScreen(plan: plan!, ctx: ctx!, api: api),
      HealthScreen(member: member!, targets: targets!, anthro: anthro!, api: api, memberId: memberId, onChanged: _load),
      ProfileScreen(members: members, memberId: memberId, plan: plan!, onSwitch: _switchMember),
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
      ),
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: R.bg2,
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Small inline Profile screen (member switch + provenance).
class ProfileScreen extends StatelessWidget {
  final List members;
  final String memberId;
  final Map<String, dynamic> plan;
  final Future<void> Function(String) onSwitch;
  const ProfileScreen({
    super.key,
    required this.members,
    required this.memberId,
    required this.plan,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final prov = (plan['provenance'] as Map?) ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('HOUSEHOLD', style: TextStyle(color: R.muted, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: members
              .map<Widget>((m) => ChoiceChip(
                    label: Text('${m['name']}'),
                    selected: m['id'] == memberId,
                    selectedColor: R.gold.withOpacity(.25),
                    onSelected: (_) => onSwitch(m['id'] as String),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
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
