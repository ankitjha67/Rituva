"""Probe the configured LLM endpoint and rank the models that actually work.

Written because a hardcoded model list went stale without warning: on 2026-09-01 all
three NVIDIA defaults returned HTTP 410 Gone (one had reached end of life six days
earlier), which silently disabled recipe generation. A provider's /models listing is not
enough on its own either — many ids it returns 404 on inference.

So this asks the endpoint directly:

    python scripts/probe_models.py                 # probe + ranked report
    python scripts/probe_models.py --apply         # also rewrite gateway defaults
    python scripts/probe_models.py --quick         # liveness only, skip the timed pass

Two phases:
  1. liveness — a tiny prompt at every plausible chat model, to separate deployed from
     merely-listed;
  2. workload — the survivors get a real recipe-shaped prompt with the JSON schema the
     app actually uses, timed. A model that is alive but can't do structured output is
     no use to us, and one that takes two minutes is a poor default.

Results are written to `scripts/model_probe.json` so the ranking is auditable rather
than a claim.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from rituva.gateway import _NON_CHAT, make_provider  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model_probe.json")

# The workload prompt mirrors cooking.llm_recipe: same shape, same schema, so a model
# that passes here is one that can actually write a recipe for the app.
SCHEMA = {
    "type": "object",
    "properties": {
        "intro": {"type": "string"},
        "steps": {"type": "array", "items": {"type": "string"}},
        "tips": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["intro", "steps", "tips"],
}
WORKLOAD = (
    'You are an experienced Indian home cook. Write a recipe for "Moong dal chilla" for '
    "one serving. The only measured ingredients are moong dal 50 g, tomato 20 g and "
    "groundnut oil 5 g, and those amounts are fixed. The only numbers allowed anywhere "
    "are those gram amounts, cooking times and temperatures; every other ingredient is "
    'described without a number ("a small onion", "a thumb of ginger"). '
    "Return JSON: intro, steps (5-9), tips (2-3)."
)

# Families that tend to be current/frontier on this endpoint. Used only to break ties
# among models that already passed the workload — never to pick an unverified model.
_RECENT = re.compile(r"kimi-k3|kimi-k2|deepseek-v4|nemotron-3\.5|nemotron-3-|gpt-oss|"
                     r"gemma-4|minimax-m3|mistral-large-2", re.I)


def _post(base, key, body, timeout):
    req = urllib.request.Request(
        f"{base}/chat/completions", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def alive(base, key, model, timeout=25):
    """Is this model actually deployed for inference?"""
    body = {"model": model, "messages": [{"role": "user", "content": "Say OK."}],
            "temperature": 0.1, "max_tokens": 8}
    t0 = time.time()
    try:
        _post(base, key, body, timeout)
        return {"model": model, "alive": True, "ping_s": round(time.time() - t0, 1), "error": ""}
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = json.loads(e.read().decode()).get("detail", "")[:90]
        except Exception:
            pass
        return {"model": model, "alive": False, "ping_s": None, "error": f"HTTP {e.code} {detail}"}
    except Exception as e:
        return {"model": model, "alive": False, "ping_s": None,
                "error": f"{type(e).__name__} after {time.time() - t0:.0f}s"}


def workload(base, key, model, timeout=150):
    """Can it produce the app's structured recipe, and how fast?"""
    body = {"model": model, "messages": [{"role": "user", "content": WORKLOAD}],
            "temperature": 0.4,
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "out", "schema": SCHEMA}}}
    t0 = time.time()
    try:
        d = _post(base, key, body, timeout)
        txt = d["choices"][0]["message"]["content"]
        obj = json.loads(txt)
        steps = obj.get("steps") or []
        ok = isinstance(steps, list) and 3 <= len(steps) <= 12 and bool(obj.get("intro"))
        return {"schema_ok": ok, "work_s": round(time.time() - t0, 1), "steps": len(steps),
                "err": "" if ok else "malformed"}
    except Exception as e:
        return {"schema_ok": False, "work_s": None, "steps": 0,
                "err": f"{type(e).__name__} after {time.time() - t0:.0f}s"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="rewrite NVIDIA_DEFAULTS in gateway.py")
    ap.add_argument("--quick", action="store_true", help="liveness only")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    provider = os.environ.get("RITUVA_LLM_PROVIDER", "nvidia")
    key = (os.environ.get("NVIDIA_API_KEY") or os.environ.get("OPENAI_API_KEY")
           or os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY", ""))
    if not key:
        raise SystemExit("No API key in the environment/.env.")
    prov = make_provider(provider, key)
    base = prov.base_url

    ids = [m.id for m in prov.list_models()]
    cands = [i for i in ids if not _NON_CHAT.search(i)]
    print(f"{provider}: {len(ids)} models listed, {len(cands)} plausible chat models\n")
    print("phase 1 — liveness (a listed model is often not a deployed one)")

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        pings = list(ex.map(lambda m: alive(base, key, m), cands))
    live = [p for p in pings if p["alive"]]
    dead = [p for p in pings if not p["alive"]]
    for p in sorted(live, key=lambda x: x["ping_s"]):
        print(f"  alive  {p['model']:46} {p['ping_s']:5.1f}s")
    print(f"  ...and {len(dead)} not deployed "
          f"({sum(1 for d in dead if '404' in d['error'])} x 404, "
          f"{sum(1 for d in dead if '410' in d['error'])} x 410 retired)\n")

    results = {p["model"]: dict(p) for p in pings}

    if not args.quick and live:
        print(f"phase 2 — workload: real recipe + JSON schema, {len(live)} models")
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            works = list(ex.map(lambda p: (p["model"], workload(base, key, p["model"])), live))
        for m, w in works:
            results[m].update(w)
            status = "ok  " if w["schema_ok"] else "fail"
            secs = f"{w['work_s']:6.1f}s" if w["work_s"] else "     -"
            print(f"  {status} {m:46} {secs}  {w['err']}")
        print()

    usable = [r for r in results.values() if r.get("schema_ok")]
    usable.sort(key=lambda r: (r["work_s"] if r["work_s"] else 9e9))
    # Rank: fastest verified first (that is what the app waits on), then prefer a recent
    # family among the rest so the fallbacks are current rather than merely alive.
    ranked = [r["model"] for r in usable]
    if not ranked:
        ranked = [r["model"] for r in sorted(live, key=lambda x: x["ping_s"])]
        print("! no model completed the structured workload — falling back to liveness order")

    recent = [m for m in ranked if _RECENT.search(m)]
    order = recent + [m for m in ranked if m not in recent]

    # A --quick run must not clobber timings from a previous full run: liveness-only
    # results have no work_s, and --apply reading those would rank by nothing at all.
    if args.quick and os.path.exists(OUT):
        print(f"(--quick: leaving {os.path.basename(OUT)} untouched so timings survive)")
    else:
        with open(OUT, "w", encoding="utf-8") as fh:
            json.dump({"provider": provider, "ranked": order,
                       "results": list(results.values())}, fh, indent=1, sort_keys=True)

    print("RANKED (fastest verified first; recent families preferred among equals):")
    for i, m in enumerate(order[:8], 1):
        r = results[m]
        print(f"  {i}. {m:46} work={r.get('work_s')}s ping={r.get('ping_s')}s")
    print(f"\nwritten to {OUT}")

    if args.apply and order:
        _apply(order[:4])


def _apply(top: list) -> None:
    """Rewrite the curated fallback list in gateway.py with what actually works today."""
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "rituva", "gateway.py")
    src = open(path, encoding="utf-8").read()
    block = "NVIDIA_DEFAULTS = [\n" + "".join(f'    "{m}",\n' for m in top) + "]"
    new = re.sub(r"NVIDIA_DEFAULTS = \[[^\]]*\]", block, src, count=1)
    if new == src:
        print("! could not locate NVIDIA_DEFAULTS — left gateway.py untouched")
        return
    open(path, "w", encoding="utf-8").write(new)
    print(f"gateway.py NVIDIA_DEFAULTS updated -> {top}")


if __name__ == "__main__":
    main()
