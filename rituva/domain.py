"""Domain model — plain dataclasses/enums (no third-party dependency).

These types are the vocabulary of the whole system; they mirror the PRD §12.4 data
model. Nutrient numbers live only in `FoodComposition` (sourced) and are *computed*
into recipes/plans — never authored by an LLM.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class Sex(str, Enum):
    M = "M"
    F = "F"


class Goal(str, Enum):
    LOSE = "lose"
    MAINTAIN = "maintain"
    GAIN = "gain"
    MUSCLE = "muscle"


class DietType(str, Enum):
    OMNIVORE = "omnivore"
    LACTO_VEG = "lacto_veg"
    LACTO_OVO = "lacto_ovo"
    VEGAN = "vegan"
    PESCATARIAN = "pescatarian"


class MealSlot(str, Enum):
    BREAKFAST = "breakfast"
    LUNCH = "lunch"
    DINNER = "dinner"
    SNACK1 = "snack1"
    SNACK2 = "snack2"


class Role(str, Enum):
    """A recipe's structural role, used to assemble balanced combos (PRD §9.3)."""
    BREAKFAST = "breakfast"
    GRAIN = "grain"      # staple base (Tier-0, recurs by design)
    MAIN = "main"        # dal / legume / paneer etc. — carries the 'hero' ingredient
    VEG = "veg"          # vegetable side
    SNACK = "snack"


class Region(str, Enum):
    NORTH = "north"
    SOUTH = "south"
    EAST = "east"
    WEST = "west"


class Season(str, Enum):
    WINTER = "winter"
    SPRING = "spring"
    SUMMER = "summer"
    MONSOON = "monsoon"


# Nutrients the engine tracks end-to-end. Extend here + in FoodComposition together.
NUTRIENTS = ("kcal", "protein", "carb", "fat", "fibre", "iron", "calcium", "b12", "sodium")
# Human units for display.
UNITS = {"kcal": "kcal", "protein": "g", "carb": "g", "fat": "g", "fibre": "g",
         "iron": "mg", "calcium": "mg", "b12": "µg", "sodium": "mg"}


@dataclass(frozen=True)
class FoodComposition:
    """Per-100 g composition. `source` is mandatory — the anti-invention anchor."""
    id: str
    name: str
    group: str
    kcal: float
    protein: float
    carb: float
    fat: float
    fibre: float
    iron: float = 0.0
    calcium: float = 0.0
    b12: float = 0.0
    sodium: float = 0.0
    source: str = "IFCT 2017"


@dataclass(frozen=True)
class RecipeIngredient:
    food_id: str
    qty_g: float


@dataclass(frozen=True)
class Recipe:
    id: str
    name: str
    role: Role
    ingredients: tuple
    region: Optional[Region] = None
    seasons: Optional[tuple] = None          # None => all seasons
    added_salt_g: float = 0.0
    hero: Optional[str] = None               # food_id tracked by FrequencyPolicy
    contains: frozenset = frozenset()        # {"dairy","egg","gluten","nut"}
    tags: frozenset = frozenset()            # {"low_gi","high_protein","fried","cheat","staple"}


@dataclass
class Member:
    id: str
    name: str
    sex: Sex
    age: int
    weight_kg: float
    height_cm: float
    pal: float = 1.4
    goal: Goal = Goal.MAINTAIN
    diet_type: DietType = DietType.LACTO_VEG
    region_prefs: tuple = ()                  # tuple[Region, ...]
    conditions: tuple = ()                    # tuple[str, ...]
    excludes: frozenset = frozenset()         # food_ids / hero names / tags to hard-remove
    known_targets: Optional[dict] = None      # user/dietitian-provided; overrides computed
    doctor_diet: Optional[dict] = None        # authoritative; overrides everything (PRD §6.5)


@dataclass
class NutrientTargets:
    kcal: float
    protein_g: float
    fat_g: float
    carb_g: float
    fibre_g: float
    sodium_mg_max: float
    added_sugar_g_max: float
    source: str = "computed"                  # computed | user_provided | doctor_prescription
    citations: tuple = ()


@dataclass
class IngredientBreakdown:
    """The 'Arhar dal 200 g -> P/C/Fibre' row shown in the UI (PRD §11.6)."""
    food_id: str
    name: str
    qty_g: float
    nutrients: dict
    source: str = "IFCT 2017"


@dataclass
class Component:
    recipe_id: str
    name: str
    role: Role
    region: Optional[str]
    scale: float
    nutrients: dict
    ingredients: list                          # list[IngredientBreakdown]


@dataclass
class MealEntry:
    slot: MealSlot
    components: list                           # list[Component]
    nutrients: dict


@dataclass
class DayPlan:
    date: str
    member_id: str
    season: str
    entries: list                              # list[MealEntry]
    totals: dict
    notes: str = ""


@dataclass
class ValidationReport:
    in_tolerance: bool
    checks: dict                               # name -> (value, target, ok)
    hard_violations: list
    warnings: list
    dqs: int
