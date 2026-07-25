"""Adherence engine — actual intake vs planned menu vs targets (PRD §19.2 P0).

Every actual number is computed from the Knowledge DB (food_nutrients), never from an
LLM. The loop is: user logs food/recipe → store stores rows per food_id → this module
sums rows to actual totals, compares them to the planned day from a generated plan
and to the member's effective targets, and emits a per-nutrient report.
"""
from __future__ import annotations

from typing import Dict, List, Optional

from .domain import NUTRIENTS, UNITS
from .knowledge import RECIPES
from .nutrition import add, food_nutrients, recipe_breakdown, zero
from .targets import effective_targets
from . import store

# Nutrients we currently compare against targets (NutrientTargets only has these).
# Iron/calcium/B12 are computed for actuals, but targets are not yet encoded.
_COMPARE = ("kcal", "protein", "carb", "fat", "fibre", "sodium")


def _sum_rows(rows) -> Dict[str, float]:
    total = zero()
    for r in rows:
        n = food_nutrients(r["food_id"], r["qty_g"])
        total = add(total, n)
    return total


def actuals_for_day(conn, member_id: str, day: str) -> Dict[str, float]:
    return _sum_rows(store.get_intake(conn, member_id, day))


def planned_for_day(conn, plan_id: str, day: str) -> Optional[Dict[str, float]]:
    pl = store.get_plan(conn, plan_id)
    if not pl:
        return None
    for d in pl.get("days", []):
        if d.get("date") == day:
            return d.get("totals")
    return None


def _align_targets(t) -> Dict[str, float]:
    return {
        "kcal": t.kcal,
        "protein": t.protein_g,
        "fat": t.fat_g,
        "carb": t.carb_g,
        "fibre": t.fibre_g,
        "sodium": t.sodium_mg_max,
    }


def adherence(conn, member_id: str, day: str, plan_id: Optional[str] = None) -> dict:
    """Return actuals vs targets and (optionally) vs a planned day."""
    m = store.get_member(conn, member_id)
    if m is None:
        raise KeyError(f"member {member_id} not found")
    actual = _sum_rows(store.get_intake(conn, member_id, day))
    targets = _align_targets(effective_targets(m))
    planned = planned_for_day(conn, plan_id, day) if plan_id else None

    def _pct(num, den):
        return round((num / den) * 100, 1) if den else None

    per_nutrient: List[dict] = []
    for nut in _COMPARE:
        a = round(actual.get(nut, 0.0), 1)
        row = {
            "nutrient": nut, "unit": UNITS.get(nut, ""),
            "actual": a, "target": round(targets[nut], 1),
            "pct_of_target": _pct(a, targets[nut]),
        }
        if planned is not None:
            p = planned.get(nut, 0.0)
            row["planned"] = round(p, 1)
            row["vs_plan_pct"] = _pct(a, p) if p else None
            row["delta"] = round(a - p, 1)
        per_nutrient.append(row)

    # Surface simple macronutrient adherence score (mean % of target, capped at 150%)
    pcts = [r["pct_of_target"] for r in per_nutrient if r["pct_of_target"] is not None]
    score = round(sum(min(p, 150) for p in pcts) / len(pcts), 1) if pcts else 0.0

    return {
        "member_id": member_id,
        "date": day,
        "plan_id": plan_id,
        "score": score,
        "actuals": {n: round(actual.get(n, 0.0), 1) for n in NUTRIENTS},
        "targets": {n: round(targets[n], 1) for n in _COMPARE},
        "planned": planned,
        "per_nutrient": per_nutrient,
    }


def expand_recipe_items(recipe_id: str, scale: float = 1.0) -> List[Dict[str, float]]:
    """Expand a logged recipe into its ingredient rows at `scale` (1.0 = per-person BOM)."""
    recipe = RECIPES[recipe_id]
    total, rows = recipe_breakdown(recipe, scale)
    return [{"food_id": ib.food_id, "name": ib.name, "qty_g": ib.qty_g} for ib in rows]
