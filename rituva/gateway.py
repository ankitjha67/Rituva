"""LLM gateway — key-only config, model auto-discovery, graceful fallback (PRD §10.5).

Design guarantees:
  * `provider=none` (default) needs no network and no keys — the deterministic core
    runs the whole product. The LLM is only ever used for *optional* text (dish
    variation, explanations); it NEVER supplies a nutrient number.
  * One OpenAI-compatible adapter serves NVIDIA build.nvidia.com (NIM), OpenAI,
    Ollama, Groq… A user pastes ONE api key; models are auto-discovered and
    best/fast defaults are auto-selected.
  * `FallbackRouter` tries an ordered list of models for the key; on 429/5xx/timeout/
    decommission it switches to the next available model, then the next provider,
    then the no-LLM path — so generation never hard-fails.
"""
from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Dict, List, Optional

# Curated defaults used when live discovery is unavailable (offline / no key).
#
# These go stale: hosted models are retired. On 2026-09-01 all three previous defaults
# (llama-3.3-70b, qwen2.5-7b, llama-3.1-8b) returned HTTP 410 Gone — llama-3.1-8b had
# reached end of life on 2026-08-26 — which silently killed recipe generation, because a
# fixed list has no way to notice. Live discovery (cached, below) is the real defence;
# this list is only the fallback, verified working on 2026-09-01.
NVIDIA_BASE = "https://integrate.api.nvidia.com/v1"
# Measured by scripts/probe_models.py on 2026-09-02: of 49 plausible chat models only 7
# were deployed, and only these 4 completed a real recipe with the app's JSON schema.
# Ordered by that measurement, not by size or name — the 120B answers in a tenth of the
# time of the 20B, which no heuristic would have guessed.
NVIDIA_DEFAULTS = [
    "openai/gpt-oss-120b",                # recipe 10.2 s
    "nvidia/nemotron-3-ultra-550b-a55b",  # recipe 71.5 s
    "minimaxai/minimax-m3",               # recipe 79.9 s
    "openai/gpt-oss-20b",                 # recipe 116.0 s
]

# Listed-but-not-deployed models answer /models yet 404 on inference, and plenty of
# entries aren't chat models at all. Both get filtered out of a discovered order.
_NON_CHAT = re.compile(
    r"embed|rerank|vision|guard|safety|ocr|diffusion|coder?\b|retriev|parse|fuyu|dplm|esm|"
    r"evo2|protein|molmo|audio|speech|tts|asr|riva|clip|video|image|paraphrase|sql|reward|"
    r"deplot|kosmos|neva|vila|calibration",
    re.I,
)
OPENAI_BASE = "https://api.openai.com/v1"
OLLAMA_BASE = "http://localhost:11434/v1"
# Google Gemini exposes an OpenAI-compatible endpoint — no vendor SDK needed.
GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/openai"
GEMINI_DEFAULTS = ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]


@dataclass
class ModelInfo:
    id: str
    provider: str
    fast: bool = False


@dataclass
class GenResult:
    text: str
    provider: str
    model: str
    ok: bool = True
    error: Optional[str] = None


class LLMProvider:
    name = "base"

    def list_models(self) -> List[ModelInfo]:
        return []

    def generate(self, prompt: str, *, model: str, schema: Optional[dict] = None,
                 temperature: float = 0.4, timeout: float = 30.0) -> GenResult:
        raise NotImplementedError


class NoLLM(LLMProvider):
    """Final fallback: returns empty text so callers use deterministic output."""
    name = "none"

    def generate(self, prompt, *, model="none", schema=None, temperature=0.4, timeout=30.0):
        return GenResult(text="", provider="none", model="none", ok=True)


class OpenAICompatible(LLMProvider):
    """Works for any OpenAI-compatible endpoint (NVIDIA NIM, OpenAI, Ollama, Groq…)."""

    def __init__(self, name: str, base_url: str, api_key: str = "", defaults: Optional[List[str]] = None):
        self.name = name
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.defaults = defaults or []

    def _headers(self):
        h = {"Content-Type": "application/json"}
        if self.api_key:
            h["Authorization"] = f"Bearer {self.api_key}"
        return h

    def list_models(self) -> List[ModelInfo]:
        """Auto-discovery. Falls back to curated defaults if the call fails."""
        try:
            req = urllib.request.Request(f"{self.base_url}/models", headers=self._headers())
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode())
            ids = [m["id"] for m in data.get("data", [])]
            return [ModelInfo(i, self.name, fast=_is_fast(i)) for i in ids] or self._default_infos()
        except Exception:
            return self._default_infos()

    def _default_infos(self):
        return [ModelInfo(i, self.name, fast=_is_fast(i)) for i in self.defaults]

    def generate(self, prompt, *, model, schema=None, temperature=0.4, timeout=30.0) -> GenResult:
        body = {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": temperature,
        }
        if schema:  # OpenAI-style structured output
            body["response_format"] = {"type": "json_schema",
                                       "json_schema": {"name": "out", "schema": schema}}
        data = json.dumps(body).encode()
        req = urllib.request.Request(f"{self.base_url}/chat/completions", data=data,
                                     headers=self._headers(), method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                out = json.loads(resp.read().decode())
            text = out["choices"][0]["message"]["content"]
            return GenResult(text=text, provider=self.name, model=model, ok=True)
        except urllib.error.HTTPError as e:                 # 429 / 5xx / 404-decommissioned
            return GenResult("", self.name, model, ok=False, error=f"HTTP {e.code}")
        except Exception as e:                              # timeout / network / parse
            return GenResult("", self.name, model, ok=False, error=str(e))


def _is_fast(model_id: str) -> bool:
    m = model_id.lower()
    return any(t in m for t in ("8b", "7b", "mini", "small", "flash", "fast", "3b", "1b"))


def make_provider(provider: str, api_key: str = "") -> LLMProvider:
    if provider in ("none", "", None):
        return NoLLM()
    if provider == "nvidia":
        return OpenAICompatible("nvidia", NVIDIA_BASE, api_key, NVIDIA_DEFAULTS)
    if provider == "openai":
        return OpenAICompatible("openai", OPENAI_BASE, api_key, ["gpt-4o-mini", "gpt-4o"])
    if provider == "ollama":
        return OpenAICompatible("ollama", OLLAMA_BASE, api_key, ["qwen2.5:7b-instruct"])
    if provider in ("gemini", "google", "vertex"):
        return OpenAICompatible("gemini", GEMINI_BASE, api_key, GEMINI_DEFAULTS)
    # treat unknown as an OpenAI-compatible custom endpoint given as base_url
    return OpenAICompatible(provider, provider, api_key)


def auto_configure(provider: LLMProvider) -> dict:
    """Key-only setup: discover models, pick a best + a fast default, build a fallback
    order. No user model-picking required (PRD §10.5)."""
    models = provider.list_models()
    if not models:
        return {"best": None, "fast": None, "order": []}
    fast = next((m.id for m in models if m.fast), models[-1].id)
    best = next((m.id for m in models if not m.fast), models[0].id)
    # fallback order: best, then fast, then everything else, de-duplicated
    order, seen = [], set()
    for mid in [best, fast] + [m.id for m in models]:
        if mid not in seen:
            order.append(mid)
            seen.add(mid)
    return {"best": best, "fast": fast, "order": order}


@dataclass
class FallbackRouter:
    """Ordered failover across models of one provider, ending in the no-LLM path."""
    provider: LLMProvider
    order: List[str] = field(default_factory=list)
    # How many leading entries of `order` are curated/measured. Those keep their order —
    # `prefer_fast` only reshuffles the discovered tail, since its name heuristic
    # ("8b", "mini", "flash") can't see that e.g. gpt-oss-20b is the fastest one here.
    pinned: int = 0
    _demoted: set = field(default_factory=set)

    _winner: Optional[str] = None      # the model that last answered — tried first

    def generate(self, prompt: str, *, prefer_fast: bool = False, schema=None,
                 temperature=0.4, timeout: float = 8.0) -> GenResult:
        """Try each model in order until one answers.

        `timeout` is per model attempt. The default suits the short text on the hot path
        (a plan's one-line explanation), where the user is waiting on a screen. Longer
        jobs must raise it — a full recipe takes 15-30 s, and leaving it at 8 s silently
        timed out every model and fell through to the no-LLM path, which reads exactly
        like "the LLM produced nothing" rather than "we never waited long enough".

        Dead models are demoted as they're found, and the first model that succeeds is
        remembered so later calls don't re-walk the graveyard.
        """
        if isinstance(self.provider, NoLLM) or not self.order:
            return NoLLM().generate(prompt)
        candidates = [m for m in self.order if m not in self._demoted] or self.order
        if prefer_fast:
            keep = [m for m in self.order[:self.pinned] if m in candidates]
            tail = [m for m in candidates if m not in keep]
            candidates = keep + sorted(tail, key=lambda m: 0 if _is_fast(m) else 1)
        if self._winner and self._winner in candidates:
            candidates = [self._winner] + [m for m in candidates if m != self._winner]
        for model in candidates:
            res = self.provider.generate(prompt, model=model, schema=schema,
                                         temperature=temperature, timeout=timeout)
            if res.ok and res.text is not None:
                self._winner = model
                return res
            self._demoted.add(model)  # cool-down: stop hammering a failing model
        return NoLLM().generate(prompt)  # graceful final fallback


# Discovered model orders, cached per provider for the life of the process. Discovery is
# one HTTP call; doing it per request is what once added 10-20 s to every plan, and never
# doing it is what let a retired model kill generation silently. Once, then reuse.
_DISCOVERY_CACHE: Dict[str, List[str]] = {}


def discover_order(prov: LLMProvider) -> List[str]:
    """Live model list for a provider, filtered to plausible chat models and ordered
    curated-first. Falls back to the curated defaults if discovery fails."""
    defaults = list(getattr(prov, "defaults", []) or [])
    key = f"{prov.name}:{getattr(prov, 'base_url', '')}"
    if key in _DISCOVERY_CACHE:
        return _DISCOVERY_CACHE[key]
    try:
        live = [m.id for m in prov.list_models() if not _NON_CHAT.search(m.id)]
    except Exception:
        live = []
    if not live:
        return defaults
    # Curated picks first (they're verified), then everything else fast-first. The router
    # demotes anything that 404s, so listed-but-undeployed models cost one attempt each.
    rest = sorted((m for m in live if m not in defaults), key=lambda m: 0 if _is_fast(m) else 1)
    order = [m for m in defaults if m in live] + rest
    _DISCOVERY_CACHE[key] = order or defaults
    return _DISCOVERY_CACHE[key]


def build_gateway(provider_name: str = "none", api_key: str = "") -> FallbackRouter:
    prov = make_provider(provider_name, api_key)
    if isinstance(prov, NoLLM):
        return FallbackRouter(provider=prov, order=[])
    order = discover_order(prov)
    defaults = list(getattr(prov, "defaults", []) or [])
    pinned = len([m for m in order[:len(defaults)] if m in defaults])
    return FallbackRouter(provider=prov, order=order, pinned=pinned)
