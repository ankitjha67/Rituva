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
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import List, Optional

# Curated defaults used when live discovery is unavailable (offline / no key).
NVIDIA_BASE = "https://integrate.api.nvidia.com/v1"
NVIDIA_DEFAULTS = [
    "meta/llama-3.3-70b-instruct",     # best (quality)
    "qwen/qwen2.5-7b-instruct",        # fast
    "meta/llama-3.1-8b-instruct",      # fast fallback
]
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
    _demoted: set = field(default_factory=set)

    def generate(self, prompt: str, *, prefer_fast: bool = False, schema=None,
                 temperature=0.4) -> GenResult:
        if isinstance(self.provider, NoLLM) or not self.order:
            return NoLLM().generate(prompt)
        candidates = [m for m in self.order if m not in self._demoted] or self.order
        if prefer_fast:
            candidates = sorted(candidates, key=lambda m: 0 if _is_fast(m) else 1)
        for model in candidates:
            res = self.provider.generate(prompt, model=model, schema=schema, temperature=temperature)
            if res.ok and res.text is not None:
                return res
            self._demoted.add(model)  # cool-down: stop hammering a failing model
        return NoLLM().generate(prompt)  # graceful final fallback


def build_gateway(provider_name: str = "none", api_key: str = "") -> FallbackRouter:
    prov = make_provider(provider_name, api_key)
    cfg = auto_configure(prov)
    return FallbackRouter(provider=prov, order=cfg["order"])
