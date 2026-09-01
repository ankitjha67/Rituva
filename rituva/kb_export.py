"""Serialise the Knowledge DB to plain JSON for the app's on-device engine.

Lives in the package (not in scripts/) because the API serves the same payload at
`GET /kb/export`, and `scripts/export_kb.py` writes it to a file.
"""
from __future__ import annotations

from . import KB_VERSION
from .knowledge import FOODS, FREQUENCY_POLICY, PULSE_IDS, RECIPES, SEED_MEMBERS
from . import store


def build_kb(include_llm_recipes: bool = True) -> dict:
    """The whole KB as JSON-safe primitives: foods, dishes, the frequency policy the
    planner enforces, and the seed household."""
    foods = [{
        "id": f.id, "name": f.name, "group": f.group, "kcal": f.kcal, "protein": f.protein,
        "carb": f.carb, "fat": f.fat, "fibre": f.fibre, "iron": f.iron,
        "calcium": f.calcium, "b12": f.b12, "sodium": f.sodium, "source": f.source,
    } for f in FOODS.values()]

    recipes = [{
        "id": r.id, "name": r.name, "role": r.role.value,
        "region": r.region.value if r.region else None,
        "seasons": [s.value for s in r.seasons] if r.seasons else None,
        "ingredients": [{"food_id": i.food_id, "qty_g": i.qty_g} for i in r.ingredients],
        "added_salt_g": r.added_salt_g, "hero": r.hero,
        "contains": sorted(r.contains), "tags": sorted(r.tags),
    } for r in RECIPES.values()]

    from .rda import to_dict as rda_dict

    kb = {
        "kb_version": KB_VERSION,
        "foods": foods,
        "recipes": recipes,
        "policy": {"frequency": dict(FREQUENCY_POLICY), "pulse_ids": sorted(PULSE_IDS)},
        "members": [store.member_to_dict(m) for m in SEED_MEMBERS.values()],
        # RDA tables + deficiency disorders travel with the KB so the reference screen
        # works with no server, like everything else.
        "rda": rda_dict(),
    }

    # Model-written recipe prose travels with the full export only: it is generated on
    # the user's own key and usually describes IFCT-derived dishes.
    if include_llm_recipes:
        try:
            from .cooking import _LLM_CACHE
            if _LLM_CACHE:
                kb["llm_recipes"] = _LLM_CACHE
        except Exception:
            pass
    return kb
