"""Nutrition math — the anti-hallucination core.

Every nutrient number in Rituva flows through here: it is COMPUTED as
`sum(ingredient.qty_g / 100 * FoodComposition.field)`. There is no code path in which
an LLM supplies a nutrient value. An ingredient missing from the Knowledge DB raises
`UnknownFoodError` (it is flagged, never invented) — PRD §9.2 rule 1 & 2.
"""
from __future__ import annotations

from typing import Dict, List, Tuple

from .domain import Component, IngredientBreakdown, NUTRIENTS, Recipe
from .knowledge import FOODS

SODIUM_MG_PER_G_SALT = 393.0  # 1 g common salt ≈ 393 mg sodium


class UnknownFoodError(KeyError):
    """Raised when a recipe references a food absent from the Knowledge DB."""


def zero() -> Dict[str, float]:
    return {n: 0.0 for n in NUTRIENTS}


def add(a: Dict[str, float], b: Dict[str, float]) -> Dict[str, float]:
    return {n: a.get(n, 0.0) + b.get(n, 0.0) for n in NUTRIENTS}


def food_nutrients(food_id: str, qty_g: float) -> Dict[str, float]:
    """Nutrients for `qty_g` of a food — pure DB lookup × scale."""
    food = FOODS.get(food_id)
    if food is None:
        raise UnknownFoodError(f"'{food_id}' not in Knowledge DB — cannot invent its nutrients")
    factor = qty_g / 100.0
    return {
        "kcal": food.kcal * factor, "protein": food.protein * factor,
        "carb": food.carb * factor, "fat": food.fat * factor, "fibre": food.fibre * factor,
        "iron": food.iron * factor, "calcium": food.calcium * factor,
        "b12": food.b12 * factor, "sodium": food.sodium * factor,
    }


def recipe_breakdown(recipe: Recipe, scale: float = 1.0
                     ) -> Tuple[Dict[str, float], List[IngredientBreakdown]]:
    """Return (total_nutrients, per-ingredient breakdown) for a recipe at `scale`.

    The per-ingredient list is exactly what the UI shows ("Arhar dal 200 g -> P/C/Fib").
    """
    total = zero()
    rows: List[IngredientBreakdown] = []
    for ing in recipe.ingredients:
        qty = ing.qty_g * scale
        nut = food_nutrients(ing.food_id, qty)
        food = FOODS[ing.food_id]
        rows.append(IngredientBreakdown(ing.food_id, food.name, round(qty, 1), nut, food.source))
        total = add(total, nut)
    if recipe.added_salt_g:
        total["sodium"] += recipe.added_salt_g * scale * SODIUM_MG_PER_G_SALT
    return total, rows


def make_component(recipe: Recipe, scale: float = 1.0) -> Component:
    total, rows = recipe_breakdown(recipe, scale)
    return Component(
        recipe_id=recipe.id, name=recipe.name, role=recipe.role,
        region=recipe.region.value if recipe.region else None,
        scale=scale, nutrients=total, ingredients=rows,
    )


# --- iso-nutrient distance (for the swap/alternatives engine, PRD §11.6) ---
_VECTOR_KEYS = ("kcal", "protein", "carb", "fat", "fibre")
_SCALE = {"kcal": 400.0, "protein": 25.0, "carb": 50.0, "fat": 20.0, "fibre": 12.0}


def iso_distance(a: Dict[str, float], b: Dict[str, float]) -> float:
    """Normalised Euclidean distance on the macro vector — lower = more equivalent."""
    return sum(((a.get(k, 0.0) - b.get(k, 0.0)) / _SCALE[k]) ** 2 for k in _VECTOR_KEYS) ** 0.5


def delta_label(alt: Dict[str, float], orig: Dict[str, float]) -> str:
    """Human 'why this is equivalent' label, e.g. '-12 kcal · +2 g protein'."""
    dk = round(alt["kcal"] - orig["kcal"])
    dp = round(alt["protein"] - orig["protein"], 1)
    parts = [f"{'+' if dk >= 0 else ''}{dk} kcal"]
    if abs(dp) >= 0.5:
        parts.append(f"{'+' if dp >= 0 else ''}{dp:g} g protein")
    return " · ".join(parts)
