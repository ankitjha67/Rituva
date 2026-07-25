"""Diet classification derived from a recipe's actual ingredients (DB-grounded —
never hand-tagged): veg / non-veg, vegan, Jain, gluten-free, plus component flags
(dairy / egg / gluten / nut / meat / fish). Used by the planner's diet filter, the
/recipes endpoint, and Discover.
"""
from __future__ import annotations

from .domain import DietType, Recipe
from .knowledge import FOODS

NONVEG_GROUPS = {"Eggs", "Poultry", "Meat", "Fish", "Shellfish"}
# Gluten-bearing (wheat/barley family). Besan (gram), sattu (roasted gram), poha
# (rice), oats are gluten-free and deliberately excluded.
GLUTEN_KEYS = ("atta", "wheat", "suji", "semolina", "rava", "maida", "daliya",
               "dalia", "vermicelli", "seviyan", "bread", "pasta", "noodle", "barley")
# Jain excludes onion/garlic and all underground / root vegetables.
JAIN_BAD_IDS = {"onion", "garlic", "spring_onion", "ginger", "shallot"}
ROOT_KEYS = ("potato", "onion", "garlic", "carrot", "radish", "beet", "beetroot",
             "sweet potato", "colocasia", "arbi", "yam", "tapioca", "turnip",
             "mooli", "lotus root", "ginger", "shallot", "elephant foot")


def _grp(fid):
    return FOODS[fid].group if fid in FOODS else ""


def _nm(fid):
    return FOODS[fid].name.lower() if fid in FOODS else fid.replace("_", " ")


def classify(recipe: Recipe) -> dict:
    ids = [i.food_id for i in recipe.ingredients]
    groups = [_grp(f) for f in ids]
    contains = set(recipe.contains)
    if any(g == "Eggs" for g in groups):
        contains.add("egg")
    if any(g in ("Poultry", "Meat") for g in groups):
        contains.add("meat")
    if any(g in ("Fish", "Shellfish") for g in groups):
        contains.add("fish")
    if any(g == "Dairy" for g in groups):
        contains.add("dairy")
    if any(g == "Nuts" for g in groups):
        contains.add("nut")
    if any(any(k in _nm(f) or k in f for k in GLUTEN_KEYS) for f in ids):
        contains.add("gluten")

    nonveg = bool(contains & {"egg", "meat", "fish"})
    root = any(f in JAIN_BAD_IDS for f in ids) or \
        any(any(k in _nm(f) for k in ROOT_KEYS) for f in ids)

    labels = {"nonveg"} if nonveg else {"veg"}
    if not nonveg and "dairy" not in contains:
        labels.add("vegan")
    if not nonveg and not root:
        labels.add("jain")
    if "gluten" not in contains:
        labels.add("gluten_free")
    for tag in ("egg", "meat", "fish", "dairy"):
        if tag in contains:
            labels.add(tag)
    return {"contains": frozenset(contains), "labels": frozenset(labels)}


_CACHE: dict = {}


def info(recipe: Recipe) -> dict:
    c = _CACHE.get(recipe.id)
    if c is None:
        c = _CACHE[recipe.id] = classify(recipe)
    return c


def labels(recipe: Recipe) -> frozenset:
    return info(recipe)["labels"]


def diet_ok(recipe: Recipe, member) -> bool:
    """Whether a recipe suits the member's diet_type + restrictions."""
    lab = labels(recipe)
    dt = member.diet_type
    if dt == DietType.VEGAN:
        return "vegan" in lab and _gf(lab, member)
    if dt == DietType.LACTO_VEG:
        return "veg" in lab and _gf(lab, member)
    if dt == DietType.JAIN:
        return "jain" in lab and _gf(lab, member)
    if dt == DietType.LACTO_OVO:
        return "meat" not in lab and "fish" not in lab and _gf(lab, member)
    if dt == DietType.PESCATARIAN:
        return "meat" not in lab and _gf(lab, member)
    return _gf(lab, member)   # NONVEG / omnivore — everything, subject to gluten-free


def _gf(lab: frozenset, member) -> bool:
    # gluten-free is a restriction layered on any diet: member excludes the "gluten" tag.
    return "gluten" not in member.excludes or "gluten_free" in lab
