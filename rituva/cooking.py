"""Cooking layer — how to actually make each dish, and where to watch it made.

Two anti-hallucination rules govern this module, mirroring `nutrition.py`:

  1. **No invented quantities.** Every gram figure in a method step is read back from
     the recipe's Knowledge-DB ingredient list. Aromatics the KB does not carry
     (spices, salt, herbs) are written as "to taste" — never given a fabricated
     amount, because their quantity is not in the DB and the nutrition math does not
     account for them.
  2. **No invented video IDs.** A `youtube.com/watch?v=<id>` link cannot be derived —
     guessing one yields a dead or wrong video. So the links built here are YouTube
     *search* endpoints (channel-scoped where the channel handle has been verified),
     which always resolve and always land on that chef's take on the dish. Real video
     IDs only ever enter via `scripts/resolve_youtube.py`, which asks the YouTube Data
     API and caches the answer (see `VIDEO_CACHE`).
"""
from __future__ import annotations

import json
import os
from typing import Dict, List, Optional
from urllib.parse import quote_plus

from .domain import Recipe, Role
from .knowledge import FOODS

# ---------------------------------------------------------------------------
# Chef registry
# ---------------------------------------------------------------------------
# Every handle below was verified by HTTP-fetching https://www.youtube.com/@<handle>
# on 2026-07-27 (200 + matching page <title>). Handles that 404'd were dropped rather
# than guessed at. `tags` drive which chefs are surfaced for a given dish.
CHEFS: tuple = (
    {"id": "sanjeev_kapoor", "name": "Sanjeev Kapoor", "channel": "Sanjeev Kapoor Khazana",
     "handle": "SanjeevKapoorKhazana", "lang": "Hindi/English",
     "tags": {"all", "north", "west", "classic"}},
    {"id": "tarla_dalal", "name": "Tarla Dalal", "channel": "Tarla Dalal",
     "handle": "TarlaDalalsKitchen", "lang": "English",
     "tags": {"all", "veg", "west", "gujarati", "healthy"}},
    {"id": "nisha_madhulika", "name": "Nisha Madhulika", "channel": "NishaMadhulika",
     "handle": "NishaMadhulika", "lang": "Hindi",
     "tags": {"all", "veg", "north", "jain", "homestyle"}},
    {"id": "chatori_rajni", "name": "Chatori Rajni", "channel": "Chatori rajni",
     "handle": "ChatoriRajni", "lang": "Hindi",
     "tags": {"snack", "street", "chaat", "north"}},
    {"id": "ranveer_brar", "name": "Ranveer Brar", "channel": "Chef Ranveer Brar",
     "handle": "RanveerBrar", "lang": "Hindi/English",
     "tags": {"all", "north", "restaurant", "nonveg"}},
    {"id": "kunal_kapur", "name": "Kunal Kapur", "channel": "Kunal Kapur",
     "handle": "KunalKapur", "lang": "Hindi/English",
     "tags": {"all", "north", "technique", "nonveg"}},
    {"id": "hebbars_kitchen", "name": "Hebbar's Kitchen", "channel": "Hebbars Kitchen",
     "handle": "HebbarsKitchen", "lang": "English/Hindi",
     "tags": {"all", "veg", "south", "breakfast"}},
    {"id": "home_cooking_show", "name": "Home Cooking Show", "channel": "HomeCookingShow",
     "handle": "HomeCookingShow", "lang": "English/Tamil",
     "tags": {"south", "veg", "homestyle"}},
    {"id": "sanjyot_keer", "name": "Sanjyot Keer", "channel": "Your Food Lab",
     "handle": "YourFoodLab", "lang": "Hindi/English",
     "tags": {"all", "modern", "west", "nonveg"}},
    {"id": "bharatzkitchen", "name": "Bharat Sethi", "channel": "bharatzkitchen",
     "handle": "bharatzkitchen", "lang": "Hindi",
     "tags": {"north", "nonveg", "street", "modern"}},
    {"id": "manjula_jain", "name": "Manjula Jain", "channel": "Manjula's Kitchen",
     "handle": "ManjulasKitchen", "lang": "English (US)",
     "tags": {"veg", "jain", "abroad", "homestyle"}},
    {"id": "get_curried", "name": "Get Curried", "channel": "Get Curried",
     "handle": "GetCurried", "lang": "English/Hindi",
     "tags": {"all", "north", "south", "nonveg"}},
)

CHEF_BY_ID = {c["id"]: c for c in CHEFS}

# Optional cache of *real* video IDs, produced by scripts/resolve_youtube.py using the
# YouTube Data API. Shape: {"<recipe_id>": [{"chef_id","video_id","title","channel"}]}.
# Absent by default — the app then uses search links, which never break.
VIDEO_CACHE: Dict[str, list] = {}
_CACHE_PATH = os.path.join(os.path.dirname(__file__), "youtube_cache.json")
if os.path.exists(_CACHE_PATH):
    try:
        with open(_CACHE_PATH, "r", encoding="utf-8") as fh:
            VIDEO_CACHE = json.load(fh)
    except Exception:
        VIDEO_CACHE = {}


def _dish_query(recipe: Recipe) -> str:
    """Search text for a dish — the dish itself, minus portion notes like '(2)' and
    minus any accompaniment ('Sattu paratha + Curd' searches for the paratha)."""
    name = recipe.name.split("(")[0].split("+")[0].strip()
    return f"{name} recipe"


def video_links(recipe: Recipe, limit: int = 4) -> List[dict]:
    """Chef videos for a dish, most relevant chef first.

    Returns direct watch links when `scripts/resolve_youtube.py` has cached a real,
    API-resolved video ID; otherwise channel-scoped *search* links. Both forms always
    resolve — no video ID is ever guessed. `kind` tells the UI which it got.
    """
    cached = {c.get("chef_id"): c for c in VIDEO_CACHE.get(recipe.id, [])}
    q = quote_plus(_dish_query(recipe))
    out: List[dict] = []
    for chef in _rank_chefs(recipe)[:limit]:
        hit = cached.get(chef["id"])
        if hit and hit.get("video_id"):
            out.append({
                "chef": chef["name"], "channel": chef["channel"], "lang": chef["lang"],
                "kind": "video", "title": hit.get("title", ""),
                "url": f"https://www.youtube.com/watch?v={hit['video_id']}",
            })
        else:
            out.append({
                "chef": chef["name"], "channel": chef["channel"], "lang": chef["lang"],
                "kind": "search", "title": "",
                "url": f"https://www.youtube.com/@{chef['handle']}/search?query={q}",
            })
    # A catch-all search across all of YouTube, in case none of the chefs covered it.
    out.append({
        "chef": "All chefs", "channel": "YouTube search", "lang": "",
        "kind": "search", "title": "",
        "url": f"https://www.youtube.com/results?search_query={q}",
    })
    return out


def _rank_chefs(recipe: Recipe) -> List[dict]:
    """Order chefs by fit: region match, then dish type, then general-purpose reach."""
    from .diet import info as diet_info
    labels = diet_info(recipe)["labels"]
    region = recipe.region.value if recipe.region else None
    fmt = dish_format(recipe)
    wants = set()
    if region:
        wants.add(region)
    if recipe.role == Role.SNACK:
        wants |= {"snack", "street"}
    if recipe.role == Role.BREAKFAST:
        wants.add("breakfast")
    if fmt in {"chaat", "ghugni", "tikka", "pakora"}:
        wants.add("street")
    if "nonveg" in labels:
        wants.add("nonveg")
    else:
        wants.add("veg")
    if "jain" in labels:
        wants.add("jain")

    def score(c: dict) -> tuple:
        overlap = len(c["tags"] & wants)
        general = 1 if "all" in c["tags"] else 0
        return (-overlap, -general, c["name"])

    return sorted(CHEFS, key=score)


# ---------------------------------------------------------------------------
# Method generation
# ---------------------------------------------------------------------------
# Coarse dish formats we know how to describe. Kept in sync with planner._FORMATS.
_FORMAT_WORDS = {
    "paratha", "thepla", "roti", "puri", "chilla", "cheela", "chila", "dosa", "idli",
    "uttapam", "pesarattu", "adai", "upma", "poha", "porridge", "pongal", "dhokla",
    "sabzi", "bhaji", "masala", "curry", "poriyal", "thoran", "bhaja", "fry", "kadhi",
    "kofta", "bharta", "tadka", "khichdi", "pulao", "biryani", "raita", "sambar",
    "rasam", "stew", "roast", "roasted", "bhurji", "tikka", "salad", "soup", "ghugni",
    "chaat", "stir-fry", "chutney", "paneer", "dal", "chana", "rajma", "chole",
}


def dish_format(recipe: Recipe) -> str:
    """The dish's cooking format (chilla / dal / sabzi …) — drives the method template."""
    words = recipe.name.lower().replace("(", " ").replace(")", " ").replace("-", " ").split()
    for w in reversed(words):
        w = w.strip(".,")
        if w in _FORMAT_WORDS:
            return w
    return words[-1] if words else recipe.id


_VEG_GROUPS = {"Vegetables", "GLV", "Roots & Tubers", "Mushrooms"}
_FLESH_GROUPS = {"Meat", "Fish", "Poultry", "Shellfish", "Flesh", "Eggs"}

# Formats `method()` has a hand-written template for. Anything outside this set is
# resolved by role + ingredient groups instead — a dish named "Apple" must never fall
# into a tempering-pan template just because its name carries no format word.
_TEMPLATED = {
    "paratha", "thepla", "roti", "puri", "chilla", "cheela", "chila", "dosa", "idli",
    "uttapam", "adai", "pesarattu", "dal", "tadka", "sambar", "chana", "rajma", "chole",
    "ghugni", "kadhi", "curry", "masala", "kofta", "paneer", "stew", "rasam", "sabzi",
    "bhaji", "poriyal", "thoran", "fry", "bhaja", "stir-fry", "bharta", "roast",
    "khichdi", "pulao", "biryani", "pongal", "raita", "salad", "chaat", "chutney",
    "roasted", "upma", "poha", "porridge", "bhurji", "tikka", "dhokla", "soup", "fruit",
    "drink",
}

# Dish words that mean an existing template under a different name.
_SYNONYMS = {
    "bhel": "chaat", "chaas": "drink", "lassi": "drink", "buttermilk": "drink",
    "water": "drink", "sharbat": "drink", "smoothie": "drink",
    "egg": "bhurji", "omelette": "bhurji", "mushroom": "sabzi", "rice": "pulao",
}


def effective_format(recipe: Recipe) -> str:
    """The template to cook by: the dish's own format word when we have a template for
    it, else one inferred from the recipe's role and ingredient groups."""
    fmt = dish_format(recipe)
    if fmt in _TEMPLATED:
        return fmt
    fmt = _SYNONYMS.get(fmt, fmt)
    if fmt in _TEMPLATED:
        return fmt
    p = _parts(recipe)
    if p["fruit"] and not (p["fat"] or p["cereal"] or p["pulse"] or p["flesh"]):
        return "fruit"                                   # whole fruit / fruit bowl
    if p["nut"] and not (p["veg"] or p["cereal"] or p["flesh"]):
        return "roasted"                                 # nut & seed snacks
    if recipe.role == Role.VEG and p["veg"]:
        return "sabzi"
    if recipe.role == Role.MAIN and (p["pulse"] or p["dairy"] or p["flesh"]):
        return "curry"
    if recipe.role == Role.BREAKFAST and p["cereal"]:
        return "upma"
    return fmt


def _parts(recipe: Recipe) -> Dict[str, list]:
    """Bucket a recipe's DB ingredients by role in the pan."""
    b: Dict[str, list] = {k: [] for k in
                          ("fat", "pulse", "cereal", "dairy", "veg", "flesh", "nut", "fruit",
                           "spice", "sugar", "other")}
    for ing in recipe.ingredients:
        f = FOODS.get(ing.food_id)
        if f is None:
            continue
        item = (f.name, ing.qty_g)
        g = f.group
        if g == "Fruits":
            b["fruit"].append(item)
        elif g == "Oils":
            b["fat"].append(item)
        elif g == "Pulses":
            b["pulse"].append(item)
        elif g == "Cereals":
            b["cereal"].append(item)
        elif g == "Dairy":
            b["dairy"].append(item)
        elif g in _VEG_GROUPS:
            b["veg"].append(item)
        elif g in _FLESH_GROUPS:
            b["flesh"].append(item)
        elif g == "Nuts":
            b["nut"].append(item)
        elif g == "Spices":
            b["spice"].append(item)
        elif g == "Sugars":
            b["sugar"].append(item)
        else:
            b["other"].append(item)
    return b


def _fmt_items(items: list) -> str:
    return ", ".join(f"{n.lower()} {round(q)} g" for n, q in items)


# Typical hands-on/total minutes per format — a transparent heuristic for planning the
# evening, not a measured figure (labelled "typical" in the payload).
_TIMES = {
    "dal": (10, 30), "tadka": (10, 30), "sambar": (15, 35), "rasam": (10, 25),
    "chana": (10, 40), "rajma": (10, 45), "chole": (10, 45), "ghugni": (10, 35),
    "curry": (15, 35), "masala": (15, 35), "kofta": (25, 45), "bharta": (15, 35),
    "paratha": (20, 30), "thepla": (20, 30), "roti": (15, 20), "puri": (20, 30),
    "chilla": (10, 20), "cheela": (10, 20), "dosa": (10, 20), "idli": (10, 25),
    "uttapam": (10, 20), "adai": (10, 25), "pesarattu": (10, 20),
    "sabzi": (10, 25), "bhaji": (10, 25), "poriyal": (10, 20), "thoran": (10, 20),
    "fry": (10, 20), "bhaja": (10, 20), "stir-fry": (10, 20),
    "khichdi": (10, 30), "pulao": (15, 30), "biryani": (30, 60),
    "raita": (5, 5), "salad": (10, 10), "chaat": (10, 15), "chutney": (10, 10),
    "roasted": (5, 10), "roast": (5, 10), "upma": (10, 20), "poha": (10, 20),
    "porridge": (5, 15), "pongal": (10, 30), "dhokla": (15, 35), "bhurji": (10, 15),
    "tikka": (20, 30), "soup": (10, 25), "stew": (15, 35), "kadhi": (15, 30),
    "paneer": (15, 30),
}


def method(recipe: Recipe) -> dict:
    """Cooking steps for a dish, generated from its Knowledge-DB ingredient list.

    Grounding contract: every gram figure below is the recipe's own DB quantity — the
    same numbers the nutrition totals are computed from. Spices/salt/aromatics are said
    "to taste" because the KB does not carry their quantities and inventing them would
    both mislead the cook and desync the nutrition math.
    """
    p = _parts(recipe)
    fmt = effective_format(recipe)
    steps: List[str] = []

    # ---- plain staple grain (Tier-0 rice/millet base — no tempering, no masala) ----
    if "staple" in recipe.tags and p["cereal"] and not (p["veg"] or p["pulse"] or p["flesh"]) \
            and fmt not in {"roti", "paratha", "puri", "thepla"}:
        steps.append(f"Rinse {_fmt_items(p['cereal'])} in 2–3 changes of water until it runs clear — "
                     f"this washes off loose surface starch so the grains stay separate.")
        steps.append("Soak 15–20 minutes and drain (optional, but it cooks more evenly).")
        steps.append("Boil in plenty of water until just tender and drain, or cook covered with about "
                     "2 parts water to 1 part grain until every drop is absorbed.")
        steps.append("Rest 5 minutes off the heat, then fluff with a fork and serve.")

    # ---- flatbreads & batters -------------------------------------------------
    elif fmt in {"paratha", "thepla", "roti", "puri"}:
        if p["cereal"]:
            steps.append(f"Take {_fmt_items(p['cereal'])} in a wide bowl with a pinch of salt.")
        if p["veg"]:
            steps.append(f"Grate or finely chop {_fmt_items(p['veg'])} and mix it into the flour "
                         f"with your spices to taste (ajwain, chilli, coriander).")
        elif p["pulse"]:
            steps.append(f"Mix {_fmt_items(p['pulse'])} into the flour with spices to taste — "
                         f"this is the stuffing/binder.")
        steps.append("Add water a little at a time and knead a soft, pliable dough. Rest it 15 minutes "
                     "under a damp cloth.")
        steps.append("Divide into equal balls and roll out on a lightly floured board.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "a little oil or ghee"
        steps.append(f"Cook on a hot tawa, turning once, then brush with {oil} and press the edges until "
                     f"golden brown spots appear on both sides.")
        if p["dairy"]:
            steps.append(f"Serve hot with {_fmt_items(p['dairy'])}.")

    elif fmt in {"chilla", "cheela", "chila", "dosa", "uttapam", "adai", "pesarattu"}:
        base = p["pulse"] or p["cereal"]
        if base:
            steps.append(f"Blend {_fmt_items(base)} with water into a smooth, pourable batter "
                         f"(soak first if using whole grain or dal).")
        if fmt in {"dosa", "adai", "uttapam"}:
            steps.append("Let the batter ferment 6–8 hours in a warm place until it smells pleasantly sour "
                         "and has risen.")
        else:
            steps.append("Rest the batter 15–20 minutes. Season with salt and spices to taste.")
        stuffed = fmt in {"dosa", "uttapam"} and p["veg"]
        if stuffed:
            steps.append(f"For the filling, boil and lightly mash {_fmt_items(p['veg'])}, then toss it in a "
                         f"tempering of mustard seeds, curry leaves, onion and turmeric to taste.")
        elif p["veg"]:
            steps.append(f"Finely chop {_fmt_items(p['veg'])} and stir through the batter.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "a few drops of oil"
        steps.append(f"Heat a tawa, pour a ladle of batter and spread it thin. Drizzle {oil} around the edge.")
        if stuffed:
            steps.append("Cook until the base is crisp and golden, spoon the filling along the centre, "
                         "fold over and serve hot with chutney and sambar.")
        else:
            steps.append("Cook until the base is golden and lifts cleanly, flip, and cook the other side "
                         "briefly. Serve immediately.")

    # ---- dals, legumes, gravies ----------------------------------------------
    elif fmt in {"dal", "tadka", "sambar", "chana", "rajma", "chole", "ghugni", "kadhi", "curry",
                 "masala", "kofta", "paneer", "stew", "rasam"}:
        if p["pulse"]:
            steps.append(f"Rinse {_fmt_items(p['pulse'])} and soak — 30 minutes for split dal, "
                         f"6–8 hours for whole legumes like rajma or chana.")
            steps.append("Pressure-cook with fresh water, a little salt and turmeric until soft "
                         "(3–4 whistles for dal, 5–6 for whole legumes).")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil or ghee"
        steps.append(f"For the tadka, heat {oil} in a pan. Crackle cumin/mustard seeds, then add "
                     f"ginger, garlic and green chilli to taste and fry until fragrant.")
        if p["veg"]:
            steps.append(f"Add {_fmt_items(p['veg'])} and sauté until softened and the raw smell goes.")
        steps.append("Add your ground spices to taste (turmeric, chilli, coriander, garam masala) and "
                     "cook 30 seconds so they don't stay raw.")
        if p["flesh"]:
            steps.append(f"Add {_fmt_items(p['flesh'])}, sear well, then cook through on a low flame.")
        if p["dairy"]:
            steps.append(f"Add {_fmt_items(p['dairy'])} — if it's paneer, add it late so it stays soft; "
                         f"if it's curd, whisk and lower the flame so it doesn't split.")
        if p["pulse"]:
            steps.append("Pour the tadka into the cooked dal (or the dal into the pan), add hot water to "
                         "the consistency you like, and simmer 5 minutes so the flavours marry.")
        steps.append("Check salt, finish with coriander and a squeeze of lemon, and serve hot.")

    # ---- dry vegetable sides --------------------------------------------------
    elif fmt in {"sabzi", "bhaji", "poriyal", "thoran", "fry", "bhaja", "stir-fry", "bharta", "roast"}:
        if p["veg"]:
            steps.append(f"Wash and cut {_fmt_items(p['veg'])} into even pieces so they cook at the same rate.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil"
        steps.append(f"Heat {oil}, splutter mustard/cumin seeds, and add curry leaves, garlic or dried "
                     f"chilli to taste.")
        if fmt == "bharta":
            steps.append("Roast the vegetable directly on the flame until the skin chars and the inside is "
                         "soft, then peel and mash it.")
        steps.append("Add the vegetables with a pinch of salt and turmeric. Toss to coat.")
        steps.append("Cover and cook on a low flame, stirring occasionally, until just tender — stop while "
                     "there's still a little bite so the nutrients and colour hold.")
        if fmt in {"poriyal", "thoran"}:
            steps.append("Finish with grated fresh coconut and toss once more.")
        steps.append("Adjust salt and serve as a side with roti or rice.")

    # ---- one-pot rice ---------------------------------------------------------
    elif fmt in {"khichdi", "pulao", "biryani", "pongal"}:
        if p["cereal"]:
            steps.append(f"Rinse {_fmt_items(p['cereal'])} until the water runs clear, then soak 20 minutes "
                         f"and drain.")
        if p["pulse"]:
            steps.append(f"Rinse {_fmt_items(p['pulse'])} and keep aside.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp ghee or oil"
        steps.append(f"Heat {oil} in a pressure cooker or heavy pot and temper whole spices "
                     f"(cumin, bay leaf, clove, cinnamon) to taste.")
        if p["veg"]:
            steps.append(f"Add {_fmt_items(p['veg'])} and sauté 2–3 minutes.")
        if p["flesh"]:
            steps.append(f"Add {_fmt_items(p['flesh'])} and sear until browned on all sides.")
        steps.append("Add the drained grain and stir 1 minute to coat every grain in fat.")
        steps.append("Add hot water (about 2 parts water to 1 part rice; more for a softer khichdi), "
                     "season with salt, and cook until done — 2 whistles, or covered on low till the "
                     "water is absorbed.")
        steps.append("Rest 5 minutes off the heat, then fluff gently with a fork and serve.")

    # ---- cold drinks (chaas / lassi) ------------------------------------------
    elif fmt == "drink":
        if p["dairy"]:
            steps.append(f"Whisk {_fmt_items(p['dairy'])} until completely smooth.")
            steps.append("Add chilled water to the thickness you like — thin for chaas, thicker for lassi.")
        if p["fruit"]:
            steps.append(f"Blend in {_fmt_items(p['fruit'])}.")
        steps.append("Season to taste — roasted cumin powder, black salt and a few mint or coriander "
                     "leaves for chaas; a little sugar or honey for a sweet lassi.")
        steps.append("Serve cold. Don't heat it — the curd will split and the live cultures won't survive.")

    # ---- whole fruit / fruit bowl (nothing to cook) ---------------------------
    elif fmt == "fruit":
        if p["fruit"]:
            steps.append(f"Wash {_fmt_items(p['fruit'])} well under running water.")
            steps.append("Eat whole with the skin on where it's edible — that's where most of the fibre is — "
                         "or cut into pieces just before eating so it doesn't oxidise.")
        if p["nut"]:
            steps.append(f"Serve alongside {_fmt_items(p['nut'])} for a little protein and fat, "
                         f"which slows the sugar release.")
        if p["dairy"]:
            steps.append(f"Optionally top with {_fmt_items(p['dairy'])}.")
        steps.append("No cooking needed — best eaten fresh.")

    # ---- no-cook --------------------------------------------------------------
    elif fmt in {"raita", "salad", "chaat", "chutney"}:
        if p["dairy"]:
            steps.append(f"Whisk {_fmt_items(p['dairy'])} until smooth and lump-free.")
        if p["veg"]:
            steps.append(f"Finely chop {_fmt_items(p['veg'])}.")
        if p["pulse"]:
            steps.append(f"Use {_fmt_items(p['pulse'])} boiled or sprouted, well drained and cooled.")
        if p["nut"]:
            steps.append(f"Roughly crush {_fmt_items(p['nut'])}.")
        steps.append("Combine everything and season to taste — roasted cumin powder, black salt, "
                     "chilli, lemon juice and fresh coriander.")
        steps.append("Chill briefly and serve fresh; it loses crunch if it sits too long.")

    # ---- roasted nuts / seeds -------------------------------------------------
    elif fmt in {"roasted"} or (recipe.role == Role.SNACK and p["nut"] and not p["veg"]):
        target = p["nut"] or p["pulse"] or p["other"]
        if target:
            steps.append(f"Spread {_fmt_items(target)} in a single layer in a dry, heavy pan.")
        steps.append("Dry-roast on a low-medium flame, stirring constantly, 5–8 minutes until they colour "
                     "lightly and smell nutty — they burn fast, so don't walk away.")
        steps.append("Cool completely (they crisp as they cool), season with a little salt or chaat masala "
                     "to taste, and store airtight.")

    # ---- quick breakfast bowls ------------------------------------------------
    elif fmt in {"upma", "poha", "porridge"}:
        if p["cereal"]:
            steps.append(f"Prepare {_fmt_items(p['cereal'])}: rinse and drain poha, or dry-roast semolina "
                         f"until it smells nutty.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil"
        steps.append(f"Heat {oil} and temper mustard seeds, curry leaves and green chilli to taste.")
        if p["veg"]:
            steps.append(f"Add {_fmt_items(p['veg'])} and sauté until tender.")
        if p["nut"]:
            steps.append(f"Add {_fmt_items(p['nut'])} and fry until golden.")
        steps.append("Add the grain with salt (and hot water for upma/porridge), stir well, cover and cook "
                     "on low 3–5 minutes until fluffy.")
        steps.append("Finish with lemon juice and coriander, and serve warm.")

    elif fmt == "bhurji":
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil"
        steps.append(f"Heat {oil} and fry finely chopped onion, ginger, garlic and green chilli to taste "
                     f"until soft.")
        if p["veg"]:
            steps.append(f"Add {_fmt_items(p['veg'])} and cook until the moisture dries off.")
        main = p["dairy"] or p["flesh"] or p["pulse"]
        if main:
            steps.append(f"Crumble in {_fmt_items(main)} and toss on a high flame for 2–3 minutes — "
                         f"keep it moving so it stays soft and doesn't rubberise.")
        steps.append("Season with turmeric, chilli and salt to taste, finish with coriander, and serve hot "
                     "with roti or pav.")

    elif fmt in {"tikka"}:
        main = p["dairy"] or p["flesh"] or p["pulse"]
        if main:
            steps.append(f"Cut {_fmt_items(main)} into even cubes.")
        steps.append("Marinate in thick curd with ginger-garlic paste, chilli, turmeric, garam masala and "
                     "salt to taste. Rest at least 30 minutes (overnight is better for meat).")
        if p["veg"]:
            steps.append(f"Thread onto skewers alternating with {_fmt_items(p['veg'])}.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "a little oil"
        steps.append(f"Grill, air-fry or pan-sear on high heat, basting with {oil}, turning until charred "
                     f"at the edges and cooked through.")
        steps.append("Finish with lemon juice and chaat masala, and serve hot.")

    elif fmt in {"dhokla"}:
        base = p["pulse"] or p["cereal"]
        if base:
            steps.append(f"Blend {_fmt_items(base)} into a smooth batter and let it ferment 6–8 hours "
                         f"(or use fruit salt just before steaming for the quick version).")
        steps.append("Season the batter with salt, sugar, ginger-chilli paste and lemon juice to taste, "
                     "then whisk in fruit salt/eno and pour immediately into a greased tin.")
        steps.append("Steam 15–20 minutes until a toothpick comes out clean. Cool slightly and cut into squares.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil"
        steps.append(f"Temper {oil} with mustard seeds, sesame, curry leaves and slit green chilli; pour "
                     f"over the dhokla and garnish with coriander and coconut.")

    elif fmt in {"soup"}:
        if p["veg"]:
            steps.append(f"Roughly chop {_fmt_items(p['veg'])}.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil"
        steps.append(f"Heat {oil}, sweat the aromatics, then add the vegetables and cook 3–4 minutes.")
        if p["pulse"]:
            steps.append(f"Add {_fmt_items(p['pulse'])} (pre-soaked) for body and protein.")
        steps.append("Add hot water or stock, season, and simmer until everything is tender.")
        steps.append("Blend smooth if you like, adjust seasoning with pepper and lemon, and serve hot.")

    # ---- generic fallback -----------------------------------------------------
    else:
        if p["pulse"]:
            steps.append(f"Rinse and soak {_fmt_items(p['pulse'])}, then boil until tender.")
        if p["cereal"]:
            steps.append(f"Rinse {_fmt_items(p['cereal'])} and cook until soft.")
        oil = _fmt_items(p["fat"]) if p["fat"] else "1 tsp oil"
        steps.append(f"Heat {oil} and temper cumin or mustard seeds with ginger, garlic and chilli to taste.")
        if p["veg"]:
            steps.append(f"Add {_fmt_items(p['veg'])} and sauté until tender.")
        if p["flesh"]:
            steps.append(f"Add {_fmt_items(p['flesh'])} and cook through.")
        if p["dairy"]:
            steps.append(f"Stir in {_fmt_items(p['dairy'])} towards the end on a low flame.")
        if p["nut"]:
            steps.append(f"Add {_fmt_items(p['nut'])}.")
        steps.append("Season with salt and your spices to taste, simmer briefly, and serve hot.")

    hands_on, total = _TIMES.get(fmt, (15, 30))
    return {
        "format": fmt,
        "steps": steps,
        "serves": 1,
        "hands_on_min": hands_on,
        "total_min": total,
        "time_note": "typical timing, not measured",
        "grounding": ("Quantities are this dish's Knowledge-DB amounts — the same ones the nutrition "
                      "totals are computed from. Spices, salt and aromatics are 'to taste': the DB does "
                      "not carry their quantities, so Rituva will not invent them."),
    }


def recipe_card(recipe: Recipe, nutrients: Optional[dict] = None,
                ingredients: Optional[list] = None) -> dict:
    """Everything the UI needs to cook a dish: method, chef videos, and DB provenance."""
    from .diet import info as diet_info
    labels = sorted(diet_info(recipe)["labels"])
    return {
        "id": recipe.id,
        "name": recipe.name,
        "role": recipe.role.value,
        "region": recipe.region.value if recipe.region else None,
        "diet": labels,
        "tags": sorted(recipe.tags),
        "method": method(recipe),
        "videos": video_links(recipe),
        "nutrients": nutrients or {},
        "ingredients": ingredients or [],
    }
