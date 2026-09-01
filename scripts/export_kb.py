"""Export the Knowledge DB to JSON for the offline (on-device) engine.

The Flutter app carries a Dart port of the deterministic planner, so it can build real
menus with no server. That engine needs the KB as data — this writes it.

Two modes, and the difference is a licensing one, not a technical one:

    python scripts/export_kb.py --public
        Curated foods/recipes only (RITUVA_NO_LOCAL_KB=1). This is the file committed to
        the repo and baked into every APK, so it must never contain IFCT 2017 rows —
        IFCT is licensed for personal use and may not be redistributed.

    python scripts/export_kb.py
        Everything the local machine has, including the IFCT-derived library. Write it
        somewhere the user can pull to their own phone (`GET /kb/export` serves exactly
        this); never commit it.

The app prefers a downloaded KB when present and falls back to the bundled one.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--public", action="store_true",
                    help="curated KB only — safe to commit and redistribute")
    ap.add_argument("--out", default="", help="output path")
    args = ap.parse_args()

    if args.public:
        os.environ["RITUVA_NO_LOCAL_KB"] = "1"

    from rituva.kb_export import build_kb   # imported after the env flag is set
    kb = build_kb(include_llm_recipes=not args.public)
    out = args.out or ("mobile/assets/kb.json" if args.public else "kb_full.json")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(kb, fh, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

    size = os.path.getsize(out) / 1024
    print(f"{out}: {len(kb['foods'])} foods, {len(kb['recipes'])} recipes, {size:.0f} KB")

    if args.public:
        # Provenance check, not a string check. The curated rows in knowledge.py cite
        # "IFCT 2017" as the source of their numbers — as any nutrition app must — and are
        # already public. What may not be redistributed is the bulk extraction in
        # ifct_local.py / recipes_local.py, so assert that none of *those* ids got in.
        leaked_f, leaked_r = set(), set()
        try:
            from rituva.ifct_local import IFCT_FOODS
            local_ids = {f.id for f in IFCT_FOODS}
            curated = _curated_ids()
            leaked_f = {f["id"] for f in kb["foods"]} & (local_ids - curated)
        except ImportError:
            pass
        try:
            from rituva.recipes_local import RECIPES_LOCAL
            leaked_r = {r["id"] for r in kb["recipes"]} & {r.id for r in RECIPES_LOCAL}
        except ImportError:
            pass
        if leaked_f or leaked_r:
            raise SystemExit(f"REFUSING: bulk-extracted rows in a redistributable export — "
                             f"{len(leaked_f)} foods, {len(leaked_r)} recipes.")
        print("  provenance OK: curated rows only, no bulk IFCT extraction present")


def _curated_ids() -> set:
    """Food ids defined in knowledge.py itself (public), independent of the local modules."""
    env = os.environ.get("RITUVA_NO_LOCAL_KB")
    os.environ["RITUVA_NO_LOCAL_KB"] = "1"
    try:
        import importlib
        from rituva import knowledge
        importlib.reload(knowledge)
        return set(knowledge.FOODS)
    finally:
        if env is None:
            os.environ.pop("RITUVA_NO_LOCAL_KB", None)
        else:
            os.environ["RITUVA_NO_LOCAL_KB"] = env


if __name__ == "__main__":
    main()
