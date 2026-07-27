"""Warm the LLM recipe cache ahead of time, so tapping a dish is instant.

Writing a recipe takes 15-25 s. That's fine once, but nobody should watch a spinner for
it — so generate them in the background and let the app serve cached text.

    python scripts/pregenerate_recipes.py              # dishes in every member's next week
    python scripts/pregenerate_recipes.py --all        # the whole library (hours; resumable)
    python scripts/pregenerate_recipes.py --limit 50

Resumable: already-cached dishes are skipped, and the cache is written after each dish,
so stopping it (or losing power) costs at most one recipe. Rejected recipes are simply
left uncached — the app falls back to the deterministic method for those.
"""
from __future__ import annotations

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from rituva import cooking as C            # noqa: E402
from rituva import store                   # noqa: E402
from rituva.context import detect          # noqa: E402
from rituva.knowledge import RECIPES       # noqa: E402
from rituva.planner import DeterministicPlanner  # noqa: E402
from rituva.targets import effective_targets     # noqa: E402


def dishes_in_plans(days: int = 7, variants: int = 3) -> list:
    """Recipe ids that actually show up on the household's plates — including a few
    regenerate variants, since that's what a user flicking Regenerate will land on."""
    conn = store.connect()
    try:
        members = store.list_members(conn)
    finally:
        conn.close()
    planner, start, out = DeterministicPlanner(), detect().today, []
    for m in members:
        t = effective_targets(m)
        for v in range(variants):
            for dp, _ in planner.plan(m, t, start, days, variant=v):
                for entry in dp.entries:
                    for comp in entry.components:
                        out.append(comp.recipe_id)
    seen, ordered = set(), []
    for rid in out:                        # dedupe, keep first-seen order (most common first)
        if rid not in seen:
            seen.add(rid)
            ordered.append(rid)
    return ordered


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="every recipe, not just planned ones")
    ap.add_argument("--limit", type=int, default=0, help="stop after N generations")
    args = ap.parse_args()

    provider = os.environ.get("RITUVA_LLM_PROVIDER", "none")
    key = (os.environ.get("NVIDIA_API_KEY") or os.environ.get("OPENAI_API_KEY")
           or os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY", ""))
    if provider == "none" or not key:
        raise SystemExit("No LLM configured. Set RITUVA_LLM_PROVIDER and the matching key "
                         "in .env — without them the app uses deterministic methods.")

    ids = list(RECIPES.keys()) if args.all else dishes_in_plans()
    todo = [i for i in ids
            if i in RECIPES and "staple" not in RECIPES[i].tags and i not in C._LLM_CACHE]
    if args.limit:
        todo = todo[:args.limit]

    print(f"{len(C._LLM_CACHE)} cached already · {len(todo)} to generate "
          f"(~{len(todo) * 20 // 60} min at ~20 s each)\n")

    ok = t0 = 0
    t0 = time.time()
    for n, rid in enumerate(todo, 1):
        r = RECIPES[rid]
        started = time.time()
        got = C.llm_recipe(r, provider, key)
        ok += bool(got)
        print(f"[{n}/{len(todo)}] {r.name[:38]:38} "
              f"{'cached' if got else 'rejected -> template'}  {time.time() - started:.0f}s")

    mins = (time.time() - t0) / 60
    print(f"\n{ok}/{len(todo)} generated in {mins:.0f} min · cache now {len(C._LLM_CACHE)} recipes")
    if C.REJECTIONS:
        print("rejections:", dict(C.REJECTIONS))
    print("Restart the API server (or just open a dish) to serve them.")


if __name__ == "__main__":
    main()
