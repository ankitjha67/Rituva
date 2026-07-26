import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// A chat sheet to ask the LLM about today's meals (trivia / Q&A). The model is
/// grounded in the day's DB-computed nutrients server-side; it never invents numbers.
class MealChatSheet extends StatefulWidget {
  final RituvaApi api;
  final String memberId;
  final String planId;
  final String date;
  const MealChatSheet(
      {super.key, required this.api, required this.memberId, required this.planId, required this.date});
  @override
  State<MealChatSheet> createState() => _MealChatSheetState();
}

class _MealChatSheetState extends State<MealChatSheet> {
  final ctrl = TextEditingController();
  final List<Map<String, String>> msgs = []; // {role: you|ai, text}
  bool sending = false;

  static const _suggestions = [
    "Which meal has the most protein?",
    "Tell me a fun fact about today's dishes",
    "Is this good for muscle gain?",
    "A tip to make lunch healthier?",
  ];

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _send(String q) async {
    q = q.trim();
    if (q.isEmpty || sending) return;
    setState(() {
      msgs.add({'role': 'you', 'text': q});
      sending = true;
      ctrl.clear();
    });
    try {
      final a = await widget.api.ask(widget.memberId, q, planId: widget.planId, date: widget.date);
      setState(() => msgs.add({'role': 'ai', 'text': a}));
    } catch (e) {
      setState(() => msgs.add({'role': 'ai', 'text': '$e'}));
    } finally {
      if (mounted) setState(() => sending = false);
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
        builder: (c, sc) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(children: [
                Icon(Icons.forum_outlined, color: R.gold, size: 20),
                SizedBox(width: 8),
                Text("Ask about today's meals",
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
        ),
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
          color: you ? R.gold.withOpacity(.18) : R.surface,
          borderRadius: BorderRadius.circular(14),
          border: you ? null : Border.all(color: R.line),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
      ),
    );
  }
}
