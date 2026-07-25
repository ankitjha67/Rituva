"""Seed Knowledge DB — foods, recipes, guideline rules, frequency policy, members.

All per-100 g values are standard food-composition-table figures (IFCT 2017 primary,
USDA where noted) and carry a `source`. In production these rows come from a DB
(Postgres/SQLite); here they are seeded so the engine is runnable offline. NOTHING
here is produced by an LLM.
"""
from __future__ import annotations

from .domain import (
    DietType, FoodComposition, Goal, Member, Recipe, RecipeIngredient, Region, Role, Season, Sex,
)


def _f(*args, **kw) -> FoodComposition:
    return FoodComposition(*args, **kw)


# ---------------------------------------------------------------------------
# FOODS  (per 100 g: kcal, protein, carb, fat, fibre, iron mg, calcium mg, b12 µg)
# ---------------------------------------------------------------------------
_FOOD_LIST = [
    # Cereals & millets
    _f("rice", "Rice (milled, raw)", "Cereals", 356, 7.9, 78, 0.5, 2.8, 0.7, 7.5, 0),
    _f("rice_brown", "Rice (brown)", "Cereals", 356, 7.5, 76.7, 1, 4.4, 1.2, 10, 0),
    _f("atta", "Wheat flour (atta, whole)", "Cereals", 320, 11.4, 64.3, 1.5, 11.4, 3.9, 30, 0),
    _f("jowar", "Jowar (sorghum)", "Cereals", 334, 9.9, 67.7, 1.7, 10.2, 4, 28, 0),
    _f("bajra", "Bajra (pearl millet)", "Cereals", 347, 10.9, 61.8, 5.4, 11.5, 6.4, 27, 0),
    _f("ragi", "Ragi (finger millet)", "Cereals", 321, 7.2, 66.8, 1.9, 11.2, 4.6, 364, 0),
    _f("foxtail", "Foxtail millet", "Cereals", 331, 12.3, 60.9, 4.3, 8, 2.8, 31, 0),
    _f("oats", "Oats (rolled)", "Cereals", 389, 16.9, 66.3, 6.9, 10.6, 4.7, 54, 0),
    _f("suji", "Suji (semolina)", "Cereals", 348, 10.5, 74, 1.1, 3.5, 1.2, 18, 0),
    _f("poha", "Poha (rice flakes)", "Cereals", 346, 6.6, 77.3, 1.2, 1.5, 20, 25, 0),
    _f("daliya", "Daliya (broken wheat)", "Cereals", 340, 12, 70, 1.5, 6.5, 3.5, 25, 0),
    _f("sattu", "Sattu (roasted gram flour)", "Cereals", 405, 22.5, 65, 6, 18, 4.4, 56, 0),
    _f("besan", "Besan (gram flour)", "Cereals", 372, 22, 57, 5, 11, 5, 56, 0),
    # Pulses & legumes
    _f("moong_dal", "Moong dal (split)", "Pulses", 347, 24, 59, 1.2, 8.2, 4.5, 75, 0),
    _f("toor_dal", "Toor/Arhar dal", "Pulses", 335, 22.3, 57.6, 1.7, 9.1, 5.2, 57, 0),
    _f("chana_dal", "Chana dal", "Pulses", 360, 22.5, 60.1, 5.3, 15.1, 4.9, 56, 0),
    _f("masoor_dal", "Masoor dal", "Pulses", 352, 25.4, 60.1, 1.5, 10.7, 7.6, 69, 0),
    _f("urad_dal", "Urad dal", "Pulses", 341, 25.2, 58.1, 1.6, 18.3, 7.6, 138, 0),
    _f("rajma", "Rajma", "Pulses", 333, 24, 58, 1.3, 19.5, 8.2, 110, 0),
    _f("kabuli_chana", "Chickpeas (kabuli)", "Pulses", 329, 19.3, 56.4, 5.7, 16.1, 4.3, 108, 0),
    _f("kala_chana", "Kala chana", "Pulses", 327, 20.5, 54.2, 5, 22.6, 4.5, 196, 0),
    _f("lobia", "Lobia (black-eyed peas)", "Pulses", 323, 23.6, 54.5, 1.3, 10.7, 8.3, 83, 0),
    _f("soya_chunks", "Soya chunks (TVP)", "Pulses", 345, 52, 33, 0.5, 13, 20, 350, 0, source="Brand avg"),
    _f("sprouted_moong", "Sprouted moong", "Pulses", 130, 7.6, 22, 0.5, 7.2, 1.3, 32, 0),
    _f("roasted_chana", "Roasted chana", "Pulses", 369, 22, 58, 5, 18, 5.3, 100, 0),
    # Vegetables
    _f("capsicum", "Capsicum", "Vegetables", 26, 1.3, 5, 0.3, 2, 0.4, 10, 0),
    _f("carrot", "Carrot", "Vegetables", 48, 1, 11, 0.2, 3.6, 0.5, 80, 0),
    _f("mushroom", "Mushroom (button)", "Vegetables", 22, 3.1, 3.3, 0.3, 1, 0.5, 3, 0),
    _f("broccoli", "Broccoli", "Vegetables", 34, 2.8, 6.6, 0.4, 2.6, 0.7, 47, 0, source="USDA"),
    _f("spring_onion", "Spring onion", "Vegetables", 27, 1.8, 6.5, 0.2, 2.6, 1.5, 72, 0),
    _f("beans", "French beans", "Vegetables", 31, 1.8, 7, 0.2, 3.4, 1, 37, 0),
    _f("green_peas", "Green peas (matar)", "Vegetables", 93, 7.2, 14.5, 0.4, 5.1, 1.6, 20, 0),
    _f("potato", "Potato", "Vegetables", 77, 2, 17.5, 0.1, 2.2, 0.8, 12, 0),
    _f("tomato", "Tomato", "Vegetables", 18, 0.9, 3.9, 0.2, 1.2, 0.3, 10, 0),
    _f("bhindi", "Bhindi (okra)", "Vegetables", 35, 1.9, 6.4, 0.2, 3.2, 0.5, 66, 0),
    _f("cauliflower", "Cauliflower (gobhi)", "Vegetables", 34, 2.6, 4.6, 0.3, 2, 0.6, 22, 0),
    _f("onion", "Onion", "Vegetables", 50, 1.2, 11, 0.1, 1.7, 0.3, 23, 0),
    _f("green_leafy", "Green leafy vegetables (grp avg)", "GLV", 45, 3.8, 5, 0.7, 2, 8.07, 279.3, 0, source="DGI 2024 Tbl1.3-1.5"),
    # Dairy / veg protein
    _f("paneer", "Paneer", "Dairy", 265, 18.3, 1.2, 20.8, 0, 0.2, 208, 0.3),
    _f("tofu", "Tofu (firm)", "Dairy", 62, 6.9, 1.5, 3.5, 0.3, 1.2, 350, 0, source="USDA"),
    _f("curd", "Curd (dahi)", "Dairy", 60, 3.1, 4.4, 4, 0, 0.2, 149, 0.2),
    _f("milk", "Milk (cow)", "Dairy", 62, 3.2, 4.4, 4, 0, 0.2, 120, 0.2),
    # Nuts / seeds
    _f("groundnut", "Groundnut (roasted)", "Nuts", 567, 25, 16, 49, 8, 3, 90, 0, source="USDA"),
    _f("almond", "Almond", "Nuts", 600, 20, 20, 50, 12, 4, 230, 0, source="USDA"),
    _f("walnut", "Walnut", "Nuts", 654, 15, 14, 65, 7, 2.9, 98, 0, source="USDA"),
    _f("pumpkin_seed", "Pumpkin seed", "Nuts", 559, 30, 10, 49, 6, 8.8, 46, 0, source="USDA"),
    _f("makhana", "Makhana (foxnut)", "Nuts", 347, 9.7, 76, 0.1, 14.5, 1.4, 60, 0),
    _f("chia", "Chia seeds", "Nuts", 486, 16.5, 42, 30.7, 34.4, 7.7, 631, 0, source="USDA"),
    # Fruits / others
    _f("banana", "Banana", "Fruits", 116, 1.2, 27.2, 0.8, 1.7, 0.3, 8, 0),
    _f("coconut_water", "Tender coconut water", "Beverages", 15, 0.2, 3.7, 0.1, 1.1, 0.1, 24, 0),
    _f("jaggery", "Jaggery", "Sugars", 383, 0.4, 98, 0.1, 0, 11, 80, 0),
    # Oils
    _f("groundnut_oil", "Groundnut oil", "Oils", 900, 0, 0, 100, 0, 0, 0, 0),
    _f("mustard_oil", "Mustard oil", "Oils", 900, 0, 0, 100, 0, 0, 0, 0),
    _f("sesame_oil", "Sesame (gingelly) oil", "Oils", 900, 0, 0, 100, 0, 0, 0, 0),
    _f("sunflower_oil", "Sunflower oil", "Oils", 900, 0, 0, 100, 0, 0, 0, 0),
    _f("coconut_oil", "Coconut oil", "Oils", 900, 0, 0, 100, 0, 0, 0, 0),
    # --- Phase A additions ---
    # Cereals / millets
    _f("quinoa", "Quinoa", "Cereals", 368, 14.1, 64.2, 6.1, 7, 4.6, 47, 0, source="USDA"),
    _f("amaranth_grain", "Amaranth grain", "Cereals", 374, 14.6, 65.2, 5.7, 7.5, 8, 159, 0),
    _f("barley", "Barley", "Cereals", 352, 10.5, 74, 1.2, 17, 3.6, 33, 0),
    _f("vermicelli", "Vermicelli (wheat)", "Cereals", 348, 10.5, 74, 1.1, 3.5, 1.2, 18, 0),
    _f("puffed_rice", "Puffed rice (murmura)", "Cereals", 325, 7.5, 74, 0.5, 0.4, 3, 20, 0),
    # Pulses
    _f("moong_whole", "Green gram (whole)", "Pulses", 334, 24, 56, 1.2, 16, 4.4, 124, 0),
    _f("horse_gram", "Horse gram", "Pulses", 321, 22, 57, 0.5, 5, 6.8, 287, 0),
    _f("dried_peas", "Dried white peas", "Pulses", 315, 16, 56, 1.2, 10, 5, 50, 0),
    # Vegetables
    _f("brinjal", "Brinjal (eggplant)", "Vegetables", 24, 1, 5.7, 0.2, 3.4, 0.4, 18, 0),
    _f("lauki", "Bottle gourd (lauki)", "Vegetables", 12, 0.2, 2.5, 0.1, 0.5, 0.2, 20, 0),
    _f("pumpkin", "Pumpkin", "Vegetables", 26, 1, 6.5, 0.1, 0.5, 0.4, 10, 0),
    _f("ridge_gourd", "Ridge gourd", "Vegetables", 17, 0.5, 3.4, 0.1, 2, 0.4, 18, 0),
    _f("beetroot", "Beetroot", "Vegetables", 43, 1.6, 10, 0.2, 2.8, 0.8, 16, 0),
    _f("cucumber", "Cucumber", "Vegetables", 15, 0.6, 3.6, 0.1, 0.5, 0.3, 16, 0),
    _f("radish", "Radish", "Vegetables", 16, 0.7, 3.4, 0.1, 1.6, 0.4, 25, 0),
    _f("sweet_potato", "Sweet potato", "Vegetables", 86, 1.6, 20, 0.1, 3, 0.6, 30, 0),
    _f("cabbage", "Cabbage", "Vegetables", 25, 1.3, 5.8, 0.1, 2.5, 0.5, 40, 0),
    _f("cluster_beans", "Cluster beans (guar)", "Vegetables", 30, 3.2, 6.3, 0.2, 3.5, 1, 57, 0),
    _f("drumstick", "Drumstick", "Vegetables", 26, 2.5, 3.7, 0.1, 4.8, 0.4, 30, 0),
    # Green leafy
    _f("methi_leaves", "Fenugreek leaves (methi)", "GLV", 49, 4.4, 6, 0.9, 1.1, 1.9, 395, 0),
    _f("mustard_greens", "Mustard greens (sarson)", "GLV", 27, 2.9, 4.7, 0.4, 2, 1.6, 155, 0),
    _f("moringa_leaves", "Drumstick leaves (moringa)", "GLV", 64, 9.4, 8.3, 1.4, 2, 4, 185, 0),
    # Fruits
    _f("apple", "Apple", "Fruits", 52, 0.3, 14, 0.2, 2.4, 0.1, 6, 0),
    _f("orange", "Orange", "Fruits", 47, 0.9, 12, 0.1, 2.4, 0.1, 40, 0),
    _f("papaya", "Papaya", "Fruits", 43, 0.5, 11, 0.3, 1.7, 0.3, 20, 0),
    _f("guava", "Guava", "Fruits", 68, 2.6, 14, 1, 5.4, 0.3, 18, 0),
    _f("pomegranate", "Pomegranate", "Fruits", 83, 1.7, 19, 1.2, 4, 0.3, 10, 0),
    _f("mango", "Mango", "Fruits", 60, 0.8, 15, 0.4, 1.6, 0.2, 11, 0),
    _f("amla", "Amla (Indian gooseberry)", "Fruits", 58, 0.9, 13, 0.6, 3.4, 1.2, 50, 0),
    # Nuts / seeds
    _f("cashew", "Cashew", "Nuts", 553, 18, 30, 44, 3.3, 6.7, 37, 0, source="USDA"),
    _f("pistachio", "Pistachio", "Nuts", 562, 20, 28, 45, 10, 3.9, 105, 0, source="USDA"),
    _f("flaxseed", "Flaxseed (linseed)", "Nuts", 534, 18, 29, 42, 27, 5.7, 255, 0, source="USDA"),
    _f("sesame", "Sesame (til)", "Nuts", 573, 17.7, 23, 49.7, 11.8, 14.6, 975, 0, source="USDA"),
    _f("sunflower_seed", "Sunflower seed", "Nuts", 584, 20.8, 20, 51, 8.6, 5.2, 78, 0, source="USDA"),
    _f("dates", "Dates", "Fruits", 277, 1.8, 75, 0.2, 6.7, 1, 39, 0, source="USDA"),
    # Animal foods (enable omnivore / lacto-ovo / pescatarian profiles)
    _f("egg", "Egg (whole)", "Flesh", 147, 13.3, 1, 10, 0, 1.4, 60, 1.1),
    _f("chicken", "Chicken (lean)", "Flesh", 120, 26, 0, 2, 0, 0.7, 12, 0.3),
    _f("fish_rohu", "Fish (rohu)", "Flesh", 97, 16.6, 0, 2.5, 0, 1, 650, 2, source="IFCT 2017"),
    _f("lemon", "Lemon", "Other", 29, 1.1, 9.3, 0.3, 2.8, 0.6, 26, 0),
]
FOODS = {f.id: f for f in _FOOD_LIST}

# Optional LOCAL IFCT 2017 food data (rituva/ifct_local.py) — ~500+ foods extracted for
# PERSONAL USE per IFCT terms. It is gitignored, so it is absent in the public repo / CI,
# where the KB simply falls back to the curated set above. Curated ids win on collision.
try:
    from .ifct_local import IFCT_FOODS as _IFCT_FOODS
    for _food in _IFCT_FOODS:
        FOODS.setdefault(_food.id, _food)
except ImportError:
    pass


# ---------------------------------------------------------------------------
# RECIPES  (BOM = per-person raw quantities; hero = frequency-tracked ingredient)
# ---------------------------------------------------------------------------
def _r(id, name, role, ings, **kw) -> Recipe:
    return Recipe(id=id, name=name, role=role,
                  ingredients=tuple(RecipeIngredient(fid, q) for fid, q in ings), **kw)


DAIRY = frozenset({"dairy"})
OIL5 = ("groundnut_oil", 5)

_RECIPES = [
    # ---- BREAKFAST ----
    _r("daliya_upma", "Daliya upma + Curd", Role.BREAKFAST, [("daliya", 60), ("curd", 100), ("carrot", 20), OIL5], contains=DAIRY, region=Region.EAST),
    _r("oats_porridge", "Oats porridge + Milk", Role.BREAKFAST, [("oats", 60), ("milk", 200)], contains=DAIRY),
    _r("idli_sambar", "Idli + Sambar", Role.BREAKFAST, [("rice", 40), ("urad_dal", 20), ("toor_dal", 25), ("tomato", 40)], region=Region.SOUTH, tags=frozenset({"low_gi"})),
    _r("masala_dosa", "Masala dosa", Role.BREAKFAST, [("rice", 60), ("urad_dal", 20), ("potato", 60), OIL5], region=Region.SOUTH),
    _r("uttapam", "Uttapam (veg)", Role.BREAKFAST, [("rice", 50), ("urad_dal", 20), ("spring_onion", 30), ("tomato", 30)], region=Region.SOUTH),
    _r("ragi_dosa", "Ragi dosa", Role.BREAKFAST, [("ragi", 50), ("urad_dal", 15), OIL5], region=Region.SOUTH, tags=frozenset({"low_gi"})),
    _r("sattu_paratha", "Sattu paratha + Curd", Role.BREAKFAST, [("atta", 50), ("sattu", 40), ("curd", 100), OIL5], contains=DAIRY, region=Region.EAST, tags=frozenset({"high_protein"})),
    _r("dahi_chura", "Dahi-chura + Banana", Role.BREAKFAST, [("poha", 50), ("curd", 120), ("banana", 50)], contains=DAIRY, region=Region.EAST),
    _r("moong_chilla", "Moong dal chilla", Role.BREAKFAST, [("moong_dal", 50), ("tomato", 20), OIL5], tags=frozenset({"high_protein", "low_gi"})),
    _r("poha_veg", "Vegetable poha + Peanut", Role.BREAKFAST, [("poha", 60), ("green_peas", 20), ("groundnut", 10), OIL5], region=Region.WEST),
    _r("besan_chilla", "Besan chilla", Role.BREAKFAST, [("besan", 50), ("spring_onion", 20), OIL5], tags=frozenset({"high_protein"})),
    _r("aloo_paratha", "Aloo paratha + Curd", Role.BREAKFAST, [("atta", 50), ("potato", 60), ("curd", 100), OIL5], contains=DAIRY, region=Region.NORTH),

    # ---- GRAIN (staples: Tier-0, exempt from strict min-gap) ----
    _r("rice_plain", "Rice", Role.GRAIN, [("rice", 75)], tags=frozenset({"staple"})),
    _r("roti", "Roti (2)", Role.GRAIN, [("atta", 60)], tags=frozenset({"staple"})),

    # ---- MAIN (hero = tracked ingredient) ----
    _r("chana_ghugni", "Chana ghugni", Role.MAIN, [("kabuli_chana", 45), ("onion", 40), ("tomato", 20), OIL5], hero="kabuli_chana", region=Region.EAST, tags=frozenset({"high_protein"})),
    _r("chole", "Chole", Role.MAIN, [("kabuli_chana", 55), ("tomato", 40), OIL5], hero="kabuli_chana", region=Region.NORTH),
    _r("rajma_masala", "Rajma masala", Role.MAIN, [("rajma", 55), ("tomato", 40), OIL5], hero="rajma", region=Region.NORTH),
    _r("dalma", "Dalma-style dal", Role.MAIN, [("toor_dal", 35), ("potato", 40), ("carrot", 30), OIL5], hero="toor_dal", region=Region.EAST),
    _r("moong_tadka", "Moong dal tadka", Role.MAIN, [("moong_dal", 45), ("tomato", 20), OIL5], hero="moong_dal", tags=frozenset({"low_gi"})),
    _r("chana_dal_tadka", "Chana dal", Role.MAIN, [("chana_dal", 45), OIL5], hero="chana_dal"),
    _r("kala_chana_curry", "Kala chana", Role.MAIN, [("kala_chana", 45), ("onion", 30), OIL5], hero="kala_chana", tags=frozenset({"high_protein"})),
    _r("lobia_curry", "Lobia curry", Role.MAIN, [("lobia", 45), ("tomato", 30), OIL5], hero="lobia"),
    _r("sambar_main", "Sambar", Role.MAIN, [("toor_dal", 45), ("carrot", 50), ("beans", 40), OIL5], hero="toor_dal", region=Region.SOUTH),
    _r("kadhi", "Kadhi", Role.MAIN, [("besan", 30), ("curd", 120), OIL5], hero="besan", contains=DAIRY, region=Region.WEST),
    _r("paneer_bhurji", "Paneer bhurji", Role.MAIN, [("paneer", 60), ("tomato", 40), ("capsicum", 30), OIL5], hero="paneer", contains=DAIRY, tags=frozenset({"high_protein"})),
    _r("matar_paneer", "Matar paneer", Role.MAIN, [("paneer", 50), ("green_peas", 60), OIL5], hero="paneer", contains=DAIRY),
    _r("mushroom_paneer", "Mushroom paneer", Role.MAIN, [("mushroom", 50), ("paneer", 60), OIL5], hero="mushroom", contains=DAIRY),
    _r("mushroom_masala", "Mushroom masala", Role.MAIN, [("mushroom", 100), ("tomato", 40), OIL5], hero="mushroom"),
    _r("tofu_bhurji", "Tofu bhurji", Role.MAIN, [("tofu", 100), ("capsicum", 30), OIL5], hero="tofu", tags=frozenset({"high_protein"})),
    _r("soya_curry", "Soya chunk curry", Role.MAIN, [("soya_chunks", 30), ("tomato", 40), OIL5], hero="soya_chunks", tags=frozenset({"high_protein"})),
    _r("palak_paneer", "Palak paneer", Role.MAIN, [("green_leafy", 100), ("paneer", 40), OIL5], hero="paneer", contains=DAIRY),

    # ---- VEG sides ----
    _r("gajar_matar", "Gajar matar", Role.VEG, [("carrot", 100), ("green_peas", 40), OIL5]),
    _r("bhindi_fry", "Bhindi", Role.VEG, [("bhindi", 120), OIL5]),
    _r("aloo_gobhi", "Aloo gobhi", Role.VEG, [("potato", 60), ("cauliflower", 60), OIL5]),
    _r("broccoli_stir", "Broccoli stir-fry", Role.VEG, [("broccoli", 100), OIL5]),
    _r("mixed_veg", "Mixed veg", Role.VEG, [("carrot", 40), ("beans", 40), ("potato", 30), OIL5]),
    _r("spring_onion_stir", "Spring onion stir-fry", Role.VEG, [("spring_onion", 100), OIL5]),
    _r("capsicum_stir", "Capsicum stir-fry", Role.VEG, [("capsicum", 100), OIL5]),
    _r("beans_poriyal", "Beans poriyal", Role.VEG, [("beans", 100), OIL5], region=Region.SOUTH),
    _r("cauliflower_peas", "Gobhi matar", Role.VEG, [("cauliflower", 80), ("green_peas", 30), OIL5]),
    _r("beans_carrot", "Beans & carrot", Role.VEG, [("beans", 60), ("carrot", 40), OIL5]),
    _r("capsicum_onion", "Capsicum masala", Role.VEG, [("capsicum", 80), ("onion", 30), OIL5]),
    _r("potato_beans", "Aloo beans", Role.VEG, [("potato", 50), ("beans", 50), OIL5]),

    # ---- SNACKS ----
    _r("makhana_roast", "Roasted makhana", Role.SNACK, [("makhana", 25)]),
    _r("roasted_chana_snack", "Roasted chana", Role.SNACK, [("roasted_chana", 30)], tags=frozenset({"high_protein"})),
    _r("sprouts_chaat", "Sprouts chaat", Role.SNACK, [("sprouted_moong", 60), ("tomato", 20)], tags=frozenset({"high_protein"})),
    _r("curd_bowl", "Curd bowl + Chia", Role.SNACK, [("curd", 120), ("chia", 10)], contains=DAIRY),
    _r("fruit_banana", "Banana", Role.SNACK, [("banana", 100)]),
    _r("nuts_mix", "Mixed nuts & seeds", Role.SNACK, [("almond", 12), ("walnut", 8), ("pumpkin_seed", 8)], contains=frozenset({"nut"}), tags=frozenset({"high_protein"})),
    _r("buttermilk", "Buttermilk (chaas)", Role.SNACK, [("curd", 100)], contains=DAIRY),
    _r("coconut_water_snack", "Tender coconut water", Role.SNACK, [("coconut_water", 250)]),

    # ===================== Phase A additions =====================
    # ---- BREAKFAST ----
    _r("rava_upma", "Rava upma", Role.BREAKFAST, [("suji", 60), ("carrot", 20), ("green_peas", 15), OIL5], region=Region.SOUTH),
    _r("vermicelli_upma", "Vermicelli upma", Role.BREAKFAST, [("vermicelli", 60), ("carrot", 20), OIL5], region=Region.SOUTH),
    _r("thepla", "Methi thepla", Role.BREAKFAST, [("atta", 50), ("methi_leaves", 20), OIL5], region=Region.WEST),
    _r("dhokla", "Dhokla", Role.BREAKFAST, [("besan", 50), OIL5], region=Region.WEST, tags=frozenset({"high_protein"})),
    _r("pesarattu", "Pesarattu", Role.BREAKFAST, [("moong_whole", 50), OIL5], region=Region.SOUTH, tags=frozenset({"high_protein", "low_gi"})),
    _r("adai", "Adai", Role.BREAKFAST, [("chana_dal", 25), ("urad_dal", 15), ("rice", 20), OIL5], region=Region.SOUTH, tags=frozenset({"high_protein"})),
    _r("methi_paratha", "Methi paratha", Role.BREAKFAST, [("atta", 50), ("methi_leaves", 25), OIL5], region=Region.NORTH),
    _r("chura_matar", "Chura matar", Role.BREAKFAST, [("poha", 50), ("green_peas", 30), OIL5], region=Region.EAST),
    _r("ragi_malt", "Ragi malt", Role.BREAKFAST, [("ragi", 40), ("milk", 200), ("banana", 40)], contains=DAIRY, tags=frozenset({"low_gi"})),
    _r("egg_bhurji_bf", "Egg bhurji", Role.BREAKFAST, [("egg", 100), ("onion", 30), ("tomato", 30), OIL5], contains=frozenset({"egg"}), tags=frozenset({"high_protein"})),

    # ---- GRAIN (millet staples for cereal variety) ----
    _r("jowar_roti", "Jowar roti", Role.GRAIN, [("jowar", 60)], tags=frozenset({"staple", "low_gi"})),
    _r("bajra_roti", "Bajra roti", Role.GRAIN, [("bajra", 60)], tags=frozenset({"staple"})),

    # ---- MAIN ----
    _r("masoor_dal_main", "Masoor dal", Role.MAIN, [("masoor_dal", 45), OIL5], hero="masoor_dal"),
    _r("urad_dal_main", "Urad dal", Role.MAIN, [("urad_dal", 45), OIL5], hero="urad_dal", region=Region.NORTH),
    _r("panchmel_dal", "Panchmel dal", Role.MAIN, [("toor_dal", 15), ("chana_dal", 10), ("moong_dal", 10), ("urad_dal", 10), OIL5], hero="toor_dal", region=Region.WEST),
    _r("rasam", "Rasam", Role.MAIN, [("toor_dal", 20), ("tomato", 40), OIL5], hero="toor_dal", region=Region.SOUTH),
    _r("dal_palak", "Dal palak", Role.MAIN, [("moong_dal", 35), ("green_leafy", 60), OIL5], hero="moong_dal"),
    _r("soya_keema", "Soya keema", Role.MAIN, [("soya_chunks", 30), ("green_peas", 30), ("tomato", 30), OIL5], hero="soya_chunks", tags=frozenset({"high_protein"})),
    _r("paneer_tikka_main", "Paneer tikka", Role.MAIN, [("paneer", 60), ("capsicum", 30), OIL5], hero="paneer", contains=DAIRY, tags=frozenset({"high_protein"})),
    _r("chana_saag", "Chana saag", Role.MAIN, [("kabuli_chana", 40), ("green_leafy", 60), OIL5], hero="kabuli_chana"),
    _r("horsegram_curry", "Horse gram curry", Role.MAIN, [("horse_gram", 40), OIL5], hero="horse_gram", region=Region.SOUTH, tags=frozenset({"high_protein"})),
    _r("matar_mushroom", "Matar mushroom", Role.MAIN, [("mushroom", 60), ("green_peas", 40), OIL5], hero="mushroom"),
    _r("egg_curry", "Egg curry", Role.MAIN, [("egg", 100), ("tomato", 40), ("onion", 30), OIL5], hero="egg", contains=frozenset({"egg"}), tags=frozenset({"high_protein"})),
    _r("fish_curry", "Fish curry (rohu)", Role.MAIN, [("fish_rohu", 100), ("tomato", 40), OIL5], hero="fish_rohu", contains=frozenset({"fish"}), region=Region.EAST, tags=frozenset({"high_protein"})),
    _r("chicken_curry", "Chicken curry", Role.MAIN, [("chicken", 100), ("tomato", 40), ("onion", 30), OIL5], hero="chicken", contains=frozenset({"meat"}), region=Region.NORTH, tags=frozenset({"high_protein"})),

    # ---- VEG ----
    _r("baingan_bharta", "Baingan bharta", Role.VEG, [("brinjal", 120), ("tomato", 30), OIL5], region=Region.NORTH),
    _r("lauki_sabzi", "Lauki sabzi", Role.VEG, [("lauki", 120), OIL5]),
    _r("pumpkin_sabzi", "Pumpkin sabzi", Role.VEG, [("pumpkin", 120), OIL5]),
    _r("methi_aloo", "Methi aloo", Role.VEG, [("potato", 60), ("methi_leaves", 40), OIL5]),
    _r("palak_sabzi", "Palak sabzi", Role.VEG, [("green_leafy", 120), OIL5]),
    _r("beetroot_poriyal", "Beetroot poriyal", Role.VEG, [("beetroot", 100), OIL5], region=Region.SOUTH),
    _r("drumstick_sabzi", "Drumstick sabzi", Role.VEG, [("drumstick", 100), OIL5], region=Region.SOUTH),
    _r("ridge_gourd_sabzi", "Ridge gourd sabzi", Role.VEG, [("ridge_gourd", 120), OIL5]),
    _r("cabbage_thoran", "Cabbage thoran", Role.VEG, [("cabbage", 120), OIL5], region=Region.SOUTH),
    _r("sweet_potato_sabzi", "Sweet potato sabzi", Role.VEG, [("sweet_potato", 100), OIL5]),

    # ---- SNACK ----
    _r("dhokla_snack", "Dhokla (snack)", Role.SNACK, [("besan", 40)], region=Region.WEST, tags=frozenset({"high_protein"})),
    _r("fruit_nut_bowl", "Fruit & nut bowl", Role.SNACK, [("apple", 100), ("almond", 10)], contains=frozenset({"nut"})),
    _r("lassi", "Lassi", Role.SNACK, [("curd", 150)], contains=DAIRY),
    _r("boiled_chana_snack", "Boiled chana", Role.SNACK, [("kabuli_chana", 40)], tags=frozenset({"high_protein"})),
    _r("dates_nuts", "Dates & almonds", Role.SNACK, [("dates", 20), ("almond", 8)], contains=frozenset({"nut"})),
    _r("guava_snack", "Guava", Role.SNACK, [("guava", 100)]),
    _r("murmura_bhel", "Murmura bhel", Role.SNACK, [("puffed_rice", 30), ("onion", 20), ("tomato", 20)]),
    _r("pumpkin_seed_snack", "Pumpkin seeds", Role.SNACK, [("pumpkin_seed", 20)], contains=frozenset({"nut"}), tags=frozenset({"high_protein"})),
]
RECIPES = {r.id: r for r in _RECIPES}

# Optional LOCAL recipe library (rituva/recipes_local.py) — 500+ dishes generated from
# home-cooking templates over the local food DB. Gitignored (many dishes use IFCT-derived
# foods), so absent in the public repo / CI, where RECIPES stays the curated set above.
try:
    from .recipes_local import RECIPES_LOCAL as _RECIPES_LOCAL
    for _recipe in _RECIPES_LOCAL:
        if all(ing.food_id in FOODS for ing in _recipe.ingredients):   # only fully-resolvable dishes
            RECIPES.setdefault(_recipe.id, _recipe)
except ImportError:
    pass


# ---------------------------------------------------------------------------
# GUIDELINE RULES  (cited targets/limits — the KB the TargetEngine draws on)
# ---------------------------------------------------------------------------
GUIDELINE_RULES = [
    {"topic": "salt", "statement": "Restrict salt to <5 g/day (<2000 mg sodium)",
     "value": {"sodium_mg_max": 2000}, "source": "DGI 2024", "page": 91},
    {"topic": "added_sugar", "statement": "Added sugar <5% E, ideally ≤25 g/day",
     "value": {"added_sugar_g_max": 25}, "source": "DGI 2024", "page": 111},
    {"topic": "fat_pct", "statement": "Total fat 20–30% of energy (use 27%)",
     "value": {"fat_pct": 0.27}, "source": "DGI 2024", "page": 54},
    {"topic": "protein_rda", "statement": "Protein RDA 0.83 g/kg; up to 1.6 g/kg for muscle",
     "value": {"rda_g_per_kg": 0.83, "muscle_g_per_kg": 1.6}, "source": "DGI 2024", "page": 58},
    {"topic": "fibre", "statement": "Fibre ~25 g per 1000 kcal",
     "value": {"g_per_1000kcal": 25}, "source": "DGI 2024", "page": 17},
    {"topic": "energy_floor", "statement": "Weight-loss diets not below 1000 kcal/day",
     "value": {"min_kcal": 1000}, "source": "DGI 2024", "page": 64},
    {"topic": "cereal_pulse", "statement": "Cereal:pulse ratio 3:1 for complete protein",
     "value": {"ratio": 3.0}, "source": "DGI 2024", "page": 58},
    {"topic": "who_limits", "statement": "Fat <30%E, sat <10%E, free sugar <10%E, salt <5 g/day",
     "value": {}, "source": "WHO Fact Sheet 394", "page": 1},
]


# ---------------------------------------------------------------------------
# FREQUENCY POLICY & EQUIVALENCE CLASSES  (PRD §8.5)
# ---------------------------------------------------------------------------
FREQUENCY_POLICY = {
    "dish_min_gap_days": 6,          # no composed main/breakfast repeats within 6 days
    "veg_min_gap_days": 3,           # vegetable sides may recur every 3rd day
    "snack_min_gap_days": 3,
    "ingredient_per_week": {          # hero-ingredient caps
        "mushroom": 2, "paneer": 3, "tofu": 2, "soya_chunks": 2,
    },
    "pulse_per_week": 2,              # any single pulse ≤ 2/week
    "region_days_per_week": 3,        # any one region ≤ 3 days/week (unless single-region user)
    "format_per_week": 3,             # any one dish format (chilla/dosa/sabzi…) ≤ 3/week — variety
}

EQUIVALENCE_CLASSES = {
    "veg_protein_anchor": {"paneer", "tofu", "soya_chunks", "kabuli_chana", "rajma", "lobia", "kala_chana"},
    "millet": {"bajra", "jowar", "ragi", "foxtail"},
    "leafy": {"green_leafy"},
}

# food_ids treated as "pulses" for the pulse cap
PULSE_IDS = {"moong_dal", "toor_dal", "chana_dal", "masoor_dal", "urad_dal", "rajma",
             "kabuli_chana", "kala_chana", "lobia", "soya_chunks", "besan",
             "moong_whole", "horse_gram", "dried_peas"}


# ---------------------------------------------------------------------------
# SEED MEMBERS
# ---------------------------------------------------------------------------
# Demo profiles — illustrative only (not real individuals). Real users create their own.
SEED_MEMBERS = {
    "aarav": Member(
        id="aarav", name="Aarav", sex=Sex.M, age=32, weight_kg=72, height_cm=173,
        pal=1.2, goal=Goal.MUSCLE, diet_type=DietType.LACTO_VEG,
        region_prefs=(Region.EAST, Region.NORTH),
        conditions=("diabetes",),
        excludes=frozenset({"cabbage"}),
    ),
    "diya": Member(
        id="diya", name="Diya", sex=Sex.F, age=30, weight_kg=68, height_cm=160,
        pal=1.55, goal=Goal.MAINTAIN, diet_type=DietType.LACTO_VEG,
        region_prefs=(Region.EAST, Region.SOUTH),
        conditions=("hypertension",),
    ),
}
