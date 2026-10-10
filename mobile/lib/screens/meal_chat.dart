import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// The Rituva assistant. It reasons over the member's profile, health conditions,
/// daily targets, the whole week's menu and engine-computed equal-nutrient swap options
/// (all assembled in [RituvaApi.assistant]), and suggests concrete, grounded changes —
/// a different dish for a meal, how to cut calories, etc. Numbers and candidate dishes
/// come from the deterministic engine; the model never invents them. Runs standalone.
class MealChatSheet extends StatefulWidget {
  final RituvaApi api;
  final String memberId;
  final Map<String, dynamic> member;
  final Map<String, dynamic> targets;
  final Map<String, dynamic> plan;
  const MealChatSheet({
    super.key,
    required this.api,
    required this.memberId,
    required this.member,
    required this.targets,
    required this.plan,
  });
  @override
  State<MealChatSheet> createState() => _MealChatSheetState();
}

class _MealChatSheetState extends State<MealChatSheet> {
  final ctrl = TextEditingController();
  final List<Map<String, String>> msgs = []; // {role: you|ai, text}
  bool sending = false;

  static const _suggestions = [
    "I want something different for breakfast on Sunday",
    "Help me cut about 300 calories this week",
    "Which day has the most protein?",
    "A lower-sodium swap for dinner?",
  ];

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  ScrollController? _sc;

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sc = _sc;
      if (sc != null && sc.hasClients) {
        sc.animateTo(sc.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String q) async {
    q = q.trim();
    if (q.isEmpty || sending) return;
    final history = List<Map<String, String>>.from(msgs); // prior turns, before this one
    setState(() {
      msgs.add({'role': 'you', 'text': q});
      sending = true;
      ctrl.clear();
    });
    _scrollToEnd();
    try {
      final a = await widget.api.assistant(
        q,
        member: widget.member,
        targets: widget.targets,
        plan: widget.plan,
        history: history,
      );
      setState(() => msgs.add({'role': 'ai', 'text': a}));
    } catch (e) {
      final msg = e is OfflineException
          ? 'Add your NVIDIA key in Profile → Assistant to use the assistant.'
          : 'The assistant is busy right now — please try again in a moment.';
      setState(() => msgs.add({'role': 'ai', 'text': msg}));
    } finally {
      if (mounted) setState(() => sending = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: .78,
        maxChildSize: .95,
        minChildSize: .5,
        expand: false,
        builder: (c, sc) {
          _sc = sc;
          return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(children: [
                Icon(Icons.forum_outlined, color: R.gold, size: 20),
                SizedBox(width: 8),
                Text("Ask Rituva",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  if (msgs.isEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _suggestions
                          .map((s) => ActionChip(label: Text(s), onPressed: () => _send(s)))
                          .toList(),
                    ),
                  ...msgs.map((m) => _bubble(m['role']!, m['text']!)),
                  if (sending)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: R.gold)),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(hintText: 'Ask anything…'),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: sending ? null : () => _send(ctrl.text), child: const Text('Send')),
                ]),
              ),
            ),
          ],
          );
        },
      ),
    );
  }

  Widget _bubble(String role, String text) {
    final you = role == 'you';
    return Align(
      alignment: you ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(11),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        decoration: BoxDecoration(
          color: you ? R.gold.withValues(alpha: .18) : R.surface,
          borderRadius: BorderRadius.circular(14),
          border: you ? null : Border.all(color: R.line),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
      ),
    );
  }
}
