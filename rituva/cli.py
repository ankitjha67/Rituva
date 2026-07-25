"""Rituva CLI — generate and print a validated plan from the seed Knowledge DB.

Examples:
    python -m rituva.cli --member aarav --days 7
    python -m rituva.cli --member diya --days 7 --regions south,east --alt
    python -m rituva.cli --member aarav --provider nvidia --api-key $NVIDIA_API_KEY

The plan is produced by the deterministic engine; an LLM (if configured) only adds a
one-line note. Every nutrient shown is computed from the DB — run with no key to prove it.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import replace
from datetime import date

from .context import detect
from .domain import Region
from .graph import run
from .knowledge import SEED_MEMBERS
from .nutrition import food_nutrients, make_component, recipe_breakdown
from .planner import DeterministicPlanner, Ledger, season_for_month
from .knowledge import RECIPES

BAR = "─" * 66


def _slot_line(entry) -> str:
    names = " + ".join(c.name for c in entry.components)
    return f"{entry.slot.value:<10} {names}"


def _regions_from_arg(arg: str):
    m = {"north": Region.NORTH, "south": Region.SOUTH, "east": Region.EAST, "west": Region.WEST}
    return tuple(m[x.strip().lower()] for x in arg.split(",") if x.strip().lower() in m)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="rituva", description="Guideline-grounded menu planner")
    ap.add_argument("--member", default="aarav", choices=list(SEED_MEMBERS))
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--start", default=date.today().isoformat())
    ap.add_argument("--regions", default="", help="override e.g. south,east")
    ap.add_argument("--provider", default="none", help="none|nvidia|openai|ollama")
    ap.add_argument("--api-key", default="")
    ap.add_argument("--alt", action="store_true", help="show iso-nutrient alternatives demo")
    a = ap.parse_args(argv)
    try:  # ensure box-drawing / ✓ render on Windows cp1252 consoles
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    member = SEED_MEMBERS[a.member]
    if a.regions:
        member = replace(member, region_prefs=_regions_from_arg(a.regions))
    start = date.fromisoformat(a.start)

    state = run(member, start, a.days, provider=a.provider, api_key=a.api_key)
    t, info = state.targets, state.info

    # ---- header ----
    print(BAR)
    print(f" Rituva · {member.name}  ({member.sex.value}, {member.age}y, "
          f"{member.weight_kg:g}kg/{member.height_cm:g}cm, PAL {member.pal:g}, goal {member.goal.value})")
    prefs = ", ".join(r.value for r in member.region_prefs) or "any"
    print(f" Region taste: {prefs}   Conditions: {', '.join(member.conditions) or 'none'}")
    print(BAR)
    print(f" BMI {info['bmi']} ({info['bmi_category']})   BMR {info['bmr']}   TDEE {info['tdee']} kcal")
    print(f" DAILY TARGET [{t.source}]  {t.kcal} kcal · protein {t.protein_g} g · "
          f"fat {t.fat_g} g · carb {t.carb_g} g · fibre {t.fibre_g} g")
    print(f"   limits: sodium ≤{round(t.sodium_mg_max)} mg · added sugar ≤{round(t.added_sugar_g_max)} g"
          f"   ({', '.join(t.citations)})")
    ctx = detect()
    print(f" Detected from system clock: {ctx.greeting.lower()} · {ctx.today.isoformat()} · "
          f"season {ctx.season.value} · next meal → {ctx.current_slot.value}")

    # ---- Knowledge-DB proof: numbers are looked up, not invented ----
    ad = food_nutrients("toor_dal", 200)
    print(BAR)
    print(" Knowledge-DB check (never from the LLM):")
    print(f"   200 g Arhar/Toor dal → protein {ad['protein']:.1f} g · carb {ad['carb']:.1f} g · "
          f"fibre {ad['fibre']:.1f} g · iron {ad['iron']:.1f} mg   [IFCT 2017]")

    # ---- per-day plan ----
    heroes, regions = {}, {}
    for dp, rep in state.plan:
        print(BAR)
        flag = "✓ on target" if rep.in_tolerance else "! review"
        print(f" {dp.date}  ({dp.season})   {round(dp.totals['kcal'])} kcal   "
              f"P {dp.totals['protein']:.0f} · C {dp.totals['carb']:.0f} · F {dp.totals['fat']:.0f} · "
              f"Fib {dp.totals['fibre']:.0f}   DQS {rep.dqs}  {flag}")
        for e in dp.entries:
            print("   " + _slot_line(e) + f"   ({round(e.nutrients['kcal'])} kcal)")
        if rep.hard_violations:
            print("   ⚠ " + "; ".join(rep.hard_violations))
        if rep.warnings:
            print("   · " + "; ".join(rep.warnings))
        # tally frequency for the summary
        for e in dp.entries:
            for c in e.components:
                r = RECIPES[c.recipe_id]
                if r.hero:
                    heroes[r.hero] = heroes.get(r.hero, 0) + 1
                if r.region:
                    regions[r.region.value] = regions.get(r.region.value, 0) + 1

    # ---- frequency-regulation summary (PRD §8.5) ----
    print(BAR)
    print(" Frequency over the plan (auto-regulated):")
    tracked = {k: v for k, v in heroes.items() if k in ("mushroom", "paneer", "tofu", "soya_chunks")}
    print("   hero ingredients: " + (", ".join(f"{k} ×{v}" for k, v in sorted(tracked.items())) or "—"))
    print("   regional days:    " + (", ".join(f"{k} ×{v}" for k, v in sorted(regions.items())) or "—"))

    # ---- alternatives demo (PRD §11.6) ----
    if a.alt:
        season = season_for_month(start.month)
        # pick the dinner main of day 1
        target_id = None
        for e in state.plan[0][0].entries:
            if e.slot.value == "dinner":
                target_id = e.components[1].recipe_id
        target_id = target_id or "mushroom_paneer"
        print(BAR)
        orig = make_component(RECIPES[target_id]).nutrients
        print(f" Don't want '{RECIPES[target_id].name}'? Equivalent options "
              f"(matched on kcal & macros, from the DB):")
        alts = DeterministicPlanner().alternatives(member, target_id, season, Ledger(), 0, n=3)
        for al in alts:
            r, n = al["recipe"], al["nutrients"]
            print(f"   • {r.name:<22} {round(n['kcal'])} kcal · P {n['protein']:.0f} · C {n['carb']:.0f} · "
                  f"Fib {n['fibre']:.0f}   ({al['delta']})")
        if alts:
            _, rows = recipe_breakdown(alts[0]["recipe"])
            print(f"   ↳ '{alts[0]['recipe'].name}' ingredients (Knowledge DB):")
            for ib in rows:
                print(f"       {ib.name:<26} {ib.qty_g:>5g} g → P {ib.nutrients['protein']:.1f} · "
                      f"C {ib.nutrients['carb']:.1f} · Fib {ib.nutrients['fibre']:.1f}  [{ib.source}]")

    # ---- provenance ----
    print(BAR)
    print(f" {state.explanation}")
    print(f" provenance: kb={state.provenance.get('kb_version')} · "
          f"llm={state.provenance.get('llm_provider')}"
          + (f"/{state.provenance.get('llm_model')}" if state.provenance.get('llm_model') else ""))
    print(BAR)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
