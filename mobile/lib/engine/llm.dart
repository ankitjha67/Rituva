import 'dart:convert';
import 'package:http/http.dart' as http;

/// Minimal OpenAI-compatible client for NVIDIA build.nvidia.com (NIM), so the app can
/// talk to the LLM **directly** with no backend server — the standalone path.
///
/// The anti-hallucination contract is unchanged: this only ever produces *text*
/// (explanations, suggestions, chat). Every nutrient number and every candidate dish
/// the model is allowed to mention is supplied to it, pre-computed, by the on-device
/// Knowledge-DB engine. The model reasons over that grounded context; it never invents
/// a calorie value or a dish that isn't in the library.
///
/// Hosted models get retired without warning (HTTP 410) and the free tier rate-limits
/// (429), so a fixed model list goes stale and fails. This client therefore (a) prefers
/// the model that last answered, (b) falls back through a curated list, and (c) discovers
/// the provider's live model list once and tries those too — self-healing like the
/// backend gateway's discover_order + FallbackRouter.
class NvidiaLLM {
  final String apiKey;
  const NvidiaLLM(this.apiKey);

  static const _base = 'https://integrate.api.nvidia.com/v1';

  // Measured winners (scripts/probe_models.py), fastest verified first.
  static const _curated = [
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'meta/llama-3.1-8b-instruct',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'minimaxai/minimax-m3',
    'meta/llama-3.3-70b-instruct',
    'qwen/qwen2.5-7b-instruct',
  ];

  // Models that aren't chat models (so discovery doesn't waste an attempt on them).
  static final _nonChat = RegExp(
    r'embed|rerank|vision|guard|safety|ocr|diffusion|coder|retriev|parse|'
    r'reward|audio|speech|tts|asr|riva|clip|video|image|sql',
    caseSensitive: false,
  );

  // Process-lifetime caches, shared across instances.
  static String? _winner; // the model that last answered — tried first
  static List<String>? _discovered; // live chat-model ids from /models
  static final Set<String> _dead = {}; // 410/404 this session — skip

  bool get configured => apiKey.trim().isNotEmpty;

  Map<String, String> get _headers =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer ${apiKey.trim()}'};

  /// One grounded turn. Walks winner → curated → discovered until a model answers.
  Future<String> chat(
    String system,
    String user, {
    double temperature = 0.4,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!configured) throw Exception('No NVIDIA API key set.');

    // Cap the walk so a bad run can't spin for minutes: the model that last answered,
    // the curated winners, and a few discovered ones. The winner cache makes the common
    // case a single fast attempt.
    final discovered = await _discover(timeout: const Duration(seconds: 6));
    final seen = <String>{};
    final candidates = <String>[
      if (_winner != null) _winner!,
      ..._curated,
      ...discovered.take(4),
    ].where((m) => seen.add(m) && !_dead.contains(m)).take(5).toList();

    Object? lastErr = 'no model answered';
    for (final model in candidates) {
      try {
        final r = await http
            .post(
              Uri.parse('$_base/chat/completions'),
              headers: _headers,
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'system', 'content': system},
                  {'role': 'user', 'content': user},
                ],
                'temperature': temperature,
              }),
            )
            .timeout(timeout);
        if (r.statusCode == 410 || r.statusCode == 404) {
          _dead.add(model); // retired — never try again this session
          lastErr = 'HTTP ${r.statusCode}';
          continue;
        }
        if (r.statusCode >= 400) {
          lastErr = 'HTTP ${r.statusCode}'; // 429/5xx — try the next model
          continue;
        }
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final txt = (((d['choices'] as List?)?.first
                as Map<String, dynamic>?)?['message'] as Map<String, dynamic>?)?['content'];
        if (txt is String && txt.trim().isNotEmpty) {
          _winner = model;
          return txt.trim();
        }
        lastErr = 'empty response';
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('Assistant unavailable ($lastErr).');
  }

  /// Live chat-model ids from the provider, fetched once per process and cached.
  Future<List<String>> _discover({required Duration timeout}) async {
    if (_discovered != null) return _discovered!;
    try {
      final r = await http.get(Uri.parse('$_base/models'), headers: _headers).timeout(timeout);
      if (r.statusCode >= 400) return _discovered = const [];
      final data = (jsonDecode(r.body) as Map<String, dynamic>)['data'] as List? ?? const [];
      final ids = data
          .map((m) => '${(m as Map)['id']}')
          .where((id) => id.isNotEmpty && !_nonChat.hasMatch(id))
          .toList();
      return _discovered = ids;
    } catch (_) {
      return _discovered = const []; // discovery is best-effort; curated list still runs
    }
  }
}
