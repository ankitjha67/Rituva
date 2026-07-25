"""Grocery aggregation — roll a plan's ingredient BOM into a categorized, household-
scaled shopping list (PRD §11.4).

Quantities are summed from the same DB-sourced per-ingredient rows shown in each dish
(`food_id` + grams), so the list is exact and nothing is invented. Aggregating by
`food_id` means the same food used across many dishes is combined into one line.
"""
from __future__ import annotations

from collections import OrderedDict

from .knowledge import FOODS

_KG = 1000  # at/above this many grams, display in kg
# Human-friendly category order (matches the Excel grocery layout).
_ORDER = ["Cereals", "Pulses", "Vegetables", "GLV", "Dairy", "Nuts",
          "Fruits", "Flesh", "Oils", "Sugars", "Beverages", "Other"]


def aggregate(plan: dict, people: int = 1) -> dict:
    totals: dict = {}  # food_id -> grams
    for d in plan.get("days", []):
        for e in d.get("entries", []):
            for c in e.get("components", []):
                for ing in c.get("ingredients", []):
                    fid = ing.get("food_id")
                    if not fid:            # older plans without food_id — skip safely
                        continue
                    totals[fid] = totals.get(fid, 0.0) + ing.get("qty_g", 0.0) * people

    items = []
    for fid, g in totals.items():
        f = FOODS.get(fid)
        qty, unit = (round(g / 1000, 2), "kg") if g >= _KG else (round(g), "g")
        items.append({
            "food_id": fid, "item": f.name if f else fid,
            "category": f.group if f else "Other",
            "grams": round(g), "quantity": qty, "unit": unit,
        })

    def _catkey(cat):
        return (_ORDER.index(cat) if cat in _ORDER else len(_ORDER), cat)

    items.sort(key=lambda x: (_catkey(x["category"]), x["item"]))
    grouped: "OrderedDict[str, list]" = OrderedDict()
    for it in items:
        grouped.setdefault(it["category"], []).append(it)

    return {
        "people": people, "days": len(plan.get("days", [])), "total_items": len(items),
        "categories": [{"category": k, "items": v} for k, v in grouped.items()],
    }
