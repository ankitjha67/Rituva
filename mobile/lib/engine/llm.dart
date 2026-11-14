import 'dart:convert';
import 'package:http/http.dart' as http;

/// Direct, server-less chat LLM access for the standalone app — any provider, not
/// just NVIDIA. Most providers speak the OpenAI `/chat/completions` API, so a single
/// client covers them (OpenAI, NVIDIA + NIM, Groq, OpenRouter, Mistral, DeepSeek,
/// Together, Ollama, LM Studio, vLLM, …); Anthropic and Gemini get their own shape.
///
/// The anti-hallucination contract is unchanged: the model only ever produces *text*
/// (explanations, suggestions, chat) grounded in context the on-device Knowledge-DB
/// engine supplies. It never invents a nutrient number or a dish not in the library.

class LlmProvider {
  final String id, name, kind; // kind: openai | anthropic | gemini
  final String base;           // fixed base URL ('' when the user must supply one)
  final String model;          // default model
  final bool needsKey;         // false for local/self-hosted (Ollama, NIM, custom)
  final bool userBase;         // user must enter the base URL (local/self-hosted/custom)
  final bool discover;         // OpenAI-kind: self-heal via GET /models when a model 404s
  final String keyHint;
  const LlmProvider(this.id, this.name, this.kind, this.base, this.model,
      {this.needsKey = true, this.userBase = false, this.discover = false, this.keyHint = ''});
}

/// The providers offered in Profile → Assistant. "Frontier", hosted-OSS, and local.
const List<LlmProvider> kLlmProviders = [
  LlmProvider('nvidia', 'NVIDIA', 'openai', 'https://integrate.api.nvidia.com/v1',
      'openai/gpt-oss-20b', discover: true, keyHint: 'nvapi-…'),
  LlmProvider('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', 'gpt-4o-mini',
      discover: true, keyHint: 'sk-…'),
  LlmProvider('anthropic', 'Anthropic · Claude', 'anthropic', 'https://api.anthropic.com',
      'claude-3-5-haiku-latest', keyHint: 'sk-ant-…'),
  LlmProvider('gemini', 'Google · Gemini', 'gemini', 'https://generativelanguage.googleapis.com',
      'gemini-2.0-flash', keyHint: 'AIza…'),
  LlmProvider('groq', 'Groq', 'openai', 'https://api.groq.com/openai/v1',
      'llama-3.3-70b-versatile', discover: true, keyHint: 'gsk_…'),
  LlmProvider('openrouter', 'OpenRouter', 'openai', 'https://openrouter.ai/api/v1',
      'openai/gpt-4o-mini', discover: true, keyHint: 'sk-or-…'),
  LlmProvider('mistral', 'Mistral', 'openai', 'https://api.mistral.ai/v1',
      'mistral-small-latest', keyHint: '…'),
  LlmProvider('deepseek', 'DeepSeek', 'openai', 'https://api.deepseek.com/v1',
      'deepseek-chat', keyHint: 'sk-…'),
  LlmProvider('together', 'Together AI', 'openai', 'https://api.together.xyz/v1',
      'meta-llama/Llama-3.3-70B-Instruct-Turbo', keyHint: '…'),
  LlmProvider('ollama', 'Ollama · local', 'openai', 'http://localhost:11434/v1', 'llama3.2',
      needsKey: false, userBase: true, discover: true, keyHint: 'no key needed'),
  LlmProvider('nim', 'NVIDIA NIM · self-hosted', 'openai', '', 'meta/llama-3.1-8b-instruct',
      needsKey: false, userBase: true, keyHint: 'optional'),
  LlmProvider('custom', 'Custom · OpenAI-compatible', 'openai', '', '',
      needsKey: false, userBase: true, keyHint: 'optional'),
];

LlmProvider providerById(String? id) =>
    kLlmProviders.firstWhere((p) => p.id == id, orElse: () => kLlmProviders.first);

/// A resolved provider + key + base + model for one chat turn.
class LlmConfig {
  final LlmProvider provider;
  final String apiKey, baseUrl, model;
  const LlmConfig(this.provider, this.apiKey, this.baseUrl, this.model);

  /// Enough to try a call: a base URL, and a key when the provider requires one.
  bool get ready =>
      baseUrl.trim().isNotEmpty && (!provider.needsKey || apiKey.trim().isNotEmpty);
}

/// One grounded chat turn, dispatched to the provider's API shape.
Future<String> llmChat(
  LlmConfig cfg,
  String system,
  String user, {
  double temperature = 0.4,
  Duration timeout = const Duration(seconds: 60),
}) {
  switch (cfg.provider.kind) {
    case 'anthropic':
      return _anthropic(cfg, system, user, temperature, timeout);
    case 'gemini':
      return _gemini(cfg, system, user, temperature, timeout);
    default:
      return _openaiCompat(cfg, system, user, temperature, timeout);
  }
}

// --------------------------------------------------------- OpenAI-compatible ----
// Hosted models get retired (404/410) and free tiers rate-limit (429), so for
// providers that support model discovery we self-heal: prefer the model that last
// answered, then the configured model, then a few discovered live ids.
String? _winnerFor; // "base|model" that last answered
String? _winnerBase;
final Map<String, List<String>> _discovered = {}; // base -> live chat ids
final Set<String> _dead = {}; // "base|model" seen dead this session

final RegExp _nonChat = RegExp(
  r'embed|rerank|vision|guard|safety|ocr|diffusion|retriev|parse|reward|audio|'
  r'speech|tts|asr|riva|clip|video|image',
  caseSensitive: false,
);

Future<String> _openaiCompat(
    LlmConfig cfg, String system, String user, double temp, Duration timeout) async {
  final base = cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) throw Exception('Set the ${cfg.provider.name} base URL in Profile.');
  final headers = {
    'Content-Type': 'application/json',
    if (cfg.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${cfg.apiKey.trim()}',
  };

  String key(String m) => '$base|$m';
  final seen = <String>{};
  final candidates = <String>[
    if (_winnerBase == base && _winnerFor != null) _winnerFor!.split('|').last,
    if (cfg.model.trim().isNotEmpty) cfg.model.trim(),
    if (cfg.provider.discover) ...(await _models(base, headers, timeout)).take(4),
  ].where((m) => m.isNotEmpty && seen.add(m) && !_dead.contains(key(m))).take(5).toList();
  if (candidates.isEmpty) throw Exception('No model configured for ${cfg.provider.name}.');

  Object? lastErr = 'no model answered';
  for (final model in candidates) {
    try {
      final r = await http
          .post(Uri.parse('$base/chat/completions'),
              headers: headers,
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'system', 'content': system},
                  {'role': 'user', 'content': user},
                ],
                'temperature': temp,
              }))
          .timeout(timeout);
      if (r.statusCode == 404 || r.statusCode == 410) {
        _dead.add(key(model));
        lastErr = 'HTTP ${r.statusCode}';
        continue;
      }
      if (r.statusCode >= 400) {
        lastErr = 'HTTP ${r.statusCode}: ${_err(r.body)}';
        continue;
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final txt = (((d['choices'] as List?)?.first as Map?)?['message'] as Map?)?['content'];
      if (txt is String && txt.trim().isNotEmpty) {
        _winnerFor = key(model);
        _winnerBase = base;
        return txt.trim();
      }
      lastErr = 'empty response';
    } catch (e) {
      lastErr = e;
    }
  }
  throw Exception('Assistant unavailable ($lastErr).');
}

Future<List<String>> _models(String base, Map<String, String> headers, Duration timeout) async {
  if (_discovered.containsKey(base)) return _discovered[base]!;
  try {
    final r = await http.get(Uri.parse('$base/models'), headers: headers)
        .timeout(const Duration(seconds: 6));
    if (r.statusCode >= 400) return _discovered[base] = const [];
    final data = (jsonDecode(r.body) as Map<String, dynamic>)['data'] as List? ?? const [];
    return _discovered[base] = data
        .map((m) => '${(m as Map)['id']}')
        .where((id) => id.isNotEmpty && !_nonChat.hasMatch(id))
        .toList();
  } catch (_) {
    return _discovered[base] = const [];
  }
}

// ------------------------------------------------------------------ Anthropic ----
Future<String> _anthropic(
    LlmConfig cfg, String system, String user, double temp, Duration timeout) async {
  final base = cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final r = await http
      .post(Uri.parse('$base/v1/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': cfg.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': cfg.model,
            'max_tokens': 1024,
            'temperature': temp,
            'system': system,
            'messages': [
              {'role': 'user', 'content': user}
            ],
          }))
      .timeout(timeout);
  if (r.statusCode >= 400) throw Exception('Anthropic HTTP ${r.statusCode}: ${_err(r.body)}');
  final d = jsonDecode(r.body) as Map<String, dynamic>;
  final txt = ((d['content'] as List?)?.first as Map?)?['text'];
  if (txt is String && txt.trim().isNotEmpty) return txt.trim();
  throw Exception('Anthropic returned no text.');
}

// --------------------------------------------------------------------- Gemini ----
Future<String> _gemini(
    LlmConfig cfg, String system, String user, double temp, Duration timeout) async {
  final base = cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse(
      '$base/v1beta/models/${cfg.model}:generateContent?key=${cfg.apiKey.trim()}');
  final r = await http
      .post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'system_instruction': {
              'parts': [
                {'text': system}
              ]
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': user}
                ]
              }
            ],
            'generationConfig': {'temperature': temp},
          }))
      .timeout(timeout);
  if (r.statusCode >= 400) throw Exception('Gemini HTTP ${r.statusCode}: ${_err(r.body)}');
  final d = jsonDecode(r.body) as Map<String, dynamic>;
  final parts = (((d['candidates'] as List?)?.first as Map?)?['content'] as Map?)?['parts'];
  final txt = (parts is List && parts.isNotEmpty) ? (parts.first as Map)['text'] : null;
  if (txt is String && txt.trim().isNotEmpty) return txt.trim();
  throw Exception('Gemini returned no text.');
}

/// Pull a short error message out of a provider's JSON error body, if present.
String _err(String body) {
  try {
    final d = jsonDecode(body);
    if (d is Map) {
      final e = d['error'];
      if (e is Map && e['message'] is String) return '${e['message']}';
      if (e is String) return e;
      if (d['message'] is String) return '${d['message']}';
    }
  } catch (_) {}
  return body.length > 120 ? '${body.substring(0, 120)}…' : body;
}
