"""DeterministicPlanner — assembles balanced, unique, frequency-regulated day plans
with zero LLM involvement (PRD §9.3). It:

  * builds each day from Role pools (breakfast + [grain+main+veg]×2 + 2 snacks),
  * enforces dish non-repetition (min-gap) and per-ingredient/pulse/region frequency
    caps (PRD §8.5) via a deterministic Ledger,
  * scales the staple grains to bring day energy within tolerance of the target,
  * validates every day and can return iso-nutrient alternatives for any dish (§11.6).

This is also the guaranteed fallback when no LLM is configured or an LLM step fails.
"""
from __future__ import annotations

import zlib
from datetime import date, timedelta
from typing import Dict, List, Optional, Tuple

from . import KB_VERSION
from .domain import (
    DayPlan, DietType, Goal, MealEntry, MealSlot, Member, NutrientTargets, Recipe, Role,
    Season, ValidationReport,
)
from .knowledge import (
    EQUIVALENCE_CLASSES, FREQUENCY_POLICY, PULSE_IDS, RECIPES,
)
from .nutrition import add, delta_label, iso_distance, make_component, zero

# Share of daily energy per meal (breakfast/lunch/dinner/snacks) — DGI menu splits.
SLOT_ENERGY = {"breakfast": 0.25, "lunch": 0.33, "dinner": 0.27, "snacks": 0.15}
KCAL_TOLERANCE = 0.12
GRAIN_SCALE_BOUNDS = (0.4, 2.4)


def season_for_month(month: int) -> Season:
    if month in (12, 1, 2):
        return Season.WINTER
    if month in (3, 4):
        return Season.SPRING
    if month in (5, 6):
        return Season.SUMMER
    return Season.MONSOON  # Jul–Nov


# ---------------------------------------------------------------------------
# Candidate filtering
# ---------------------------------------------------------------------------
def diet_ok(recipe: Recipe, member: Member) -> bool:
    # Diet suitability is derived from the recipe's ingredients (veg/non-veg, vegan,
    # Jain, gluten-free) — see diet.py. Lazy import avoids any module load-order cycle.
    from .diet import diet_ok as _classify_ok
    return _classify_ok(recipe, member)


def excluded(recipe: Recipe, member: Member) -> bool:
    ex = member.excludes
    if not ex:
        return False
    if recipe.hero in ex or (recipe.tags & ex):
        return True
    return any(ing.food_id in ex for ing in recipe.ingredients)


def season_ok(recipe: Recipe, season: Season) -> bool:
    return recipe.seasons is None or season in recipe.seasons


def base_pool(role: Role, member: Member, season: Season) -> List[Recipe]:
    return [r for r in RECIPES.values()
            if r.role == role and diet_ok(r, member)
            and not excluded(r, member) and season_ok(r, season)]


# ---------------------------------------------------------------------------
# Frequency + uniqueness ledger (PRD §8)
# ---------------------------------------------------------------------------
class Ledger:
    def __init__(self, policy: dict = FREQUENCY_POLICY, single_region: bool = False, variant: int = 0):
        self.p = policy
        self.single_region = single_region
        self.variant = variant       # regenerate: reshuffles the tie-break for a different plan
        self.dish_last: Dict[str, int] = {}          # recipe_id -> day index
        self.hero_days: Dict[str, List[int]] = {}     # food_id -> [day idx]
        self.pulse_days: Dict[str, List[int]] = {}
        self.region_days: Dict[str, List[int]] = {}
        self.fmt_days: Dict[str, List[int]] = {}      # dish format (chilla/dosa/sabzi…) -> [day idx]
        self.reasons: List[str] = []

    @staticmethod
    def _count(days: List[int], di: int, window: int = 7) -> int:
        return sum(1 for d in days if di - window < d <= di)

    def dish_allowed(self, r: Recipe, di: int) -> bool:
        if "staple" in r.tags:
            return True
        if r.role == Role.SNACK:
            gap = self.p["snack_min_gap_days"]
        elif r.role == Role.VEG:
            gap = self.p.get("veg_min_gap_days", 3)
        else:
            gap = self.p["dish_min_gap_days"]
        last = self.dish_last.get(r.id)
        return last is None or (di - last) >= gap

    def freq_allowed(self, r: Recipe, di: int) -> bool:
        # hero-ingredient weekly cap
        if r.hero and r.hero in self.p["ingredient_per_week"]:
            if self._count(self.hero_days.get(r.hero, []), di) >= self.p["ingredient_per_week"][r.hero]:
                return False
        # any single pulse cap
        for ing in r.ingredients:
            if ing.food_id in PULSE_IDS:
                if self._count(self.pulse_days.get(ing.food_id, []), di) >= self.p["pulse_per_week"]:
                    return False
        # region-days cap (skipped if the user chose a single region)
        if r.region and not self.single_region:
            if self._count(self.region_days.get(r.region.value, []), di) >= self.p["region_days_per_week"]:
                return False
        # dish-format weekly cap — variety across formats (no 7 chillas / a week of sabzi)
        if "staple" not in r.tags:
            if self._count(self.fmt_days.get(_format(r), []), di) >= self.p.get("format_per_week", 3):
                return False
        return True

    def allowed(self, r: Recipe, di: int) -> bool:
        return self.dish_allowed(r, di) and self.freq_allowed(r, di)

    def record(self, r: Recipe, di: int) -> None:
        self.dish_last[r.id] = di
        if r.hero:
            self.hero_days.setdefault(r.hero, []).append(di)
        for ing in r.ingredients:
            if ing.food_id in PULSE_IDS:
                self.pulse_days.setdefault(ing.food_id, []).append(di)
        if r.region:
            self.region_days.setdefault(r.region.value, []).append(di)
        self.fmt_days.setdefault(_format(r), []).append(di)

    def days_since(self, r: Recipe, di: int) -> int:
        last = self.dish_last.get(r.id)
        return 999 if last is None else di - last


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
_FORMATS = {
    "chilla", "cheela", "chila", "paratha", "dosa", "idli", "uttapam", "pesarattu",
    "upma", "poha", "porridge", "pongal", "dhokla", "thepla", "adai",
    "sabzi", "bhaji", "masala", "curry", "poriyal", "thoran", "bhaja", "fry", "kadhi",
    "kofta", "bharta", "tadka", "khichdi", "pulao", "biryani", "raita", "roti",
    "sambar", "rasam", "stew", "roast", "bhurji", "tikka", "salad", "soup", "ghugni",
}


def _format(r: Recipe) -> str:
    """Coarse dish 'format' for variety capping (e.g. chilla / dosa / sabzi)."""
    for w in reversed(r.name.lower().replace("(", " ").replace(")", " ").replace("-", " ").split()):
        w = w.strip(".,")
        if w in _FORMATS:
            return w
    words = r.name.lower().split()   # fall back to the last word
    return words[-1] if words else r.id


def _score(r: Recipe, member: Member, ledger: Ledger, di: int) -> float:
    s = 0.0
    if r.region in member.region_prefs:
        s += 3.0
    if "high_protein" in r.tags and member.goal == Goal.MUSCLE:
        s += 2.0
    s -= ledger._count(ledger.fmt_days.get(_format(r), []), di, window=2) * 0.9   # spread formats (no back-to-back chillas)
    s += min(ledger.days_since(r, di), 12) * 0.1            # favour least-recently-used
    # Stable tie-break for variety. NB: Python's built-in hash() of a str is salted by
    # PYTHONHASHSEED, so it varies per process — using it here made plans (and tests, and
    # the offline demo) non-reproducible. crc32 is stable across processes.
    tie = zlib.crc32(r.id.encode() if ledger.variant == 0 else f"{r.id}:{ledger.variant}".encode())
    s += ((tie + di * 7) % 5) * 0.06
    return s


def _pick(pool: List[Recipe], member: Member, ledger: Ledger, di: int,
          warnings: List[str], label: str) -> Optional[Recipe]:
    cands = sorted(pool, key=lambda r: _score(r, member, ledger, di), reverse=True)
    for r in cands:
        if ledger.allowed(r, di):
            return r
    # relaxed pass: keep diet/excludes, drop min-gap (record a visible warning, not a silent repeat)
    for r in cands:
        if ledger.freq_allowed(r, di):
            warnings.append(f"{label}: library thin — reused '{r.name}' inside the gap window")
            return r
    return cands[0] if cands else None


class DeterministicPlanner:
    def __init__(self, policy: dict = FREQUENCY_POLICY):
        self.policy = policy

    def plan(self, member: Member, targets: NutrientTargets, start: date, days: int,
             variant: int = 0) -> List[Tuple[DayPlan, ValidationReport]]:
        single_region = len(member.region_prefs) == 1
        ledger = Ledger(self.policy, single_region=single_region, variant=variant)
        out: List[Tuple[DayPlan, ValidationReport]] = []
        for di in range(days):
            d = start + timedelta(days=di)
            out.append(self._one_day(member, targets, d, di, ledger))
        return out

    def _one_day(self, member, targets, d: date, di: int, ledger: Ledger):
        season = season_for_month(d.month)
        warnings: List[str] = []
        # More protein-dense mains for muscle/gain goals (PRD §6.3 protein target).
        main_scale0 = {Goal.MUSCLE: 1.5, Goal.GAIN: 1.3}.get(member.goal, 1.1)

        # Pick and record each dish immediately so nothing repeats within the same day
        # (and so dinner never reuses lunch's main/veg).
        bf = _pick(base_pool(Role.BREAKFAST, member, season), member, ledger, di, warnings, "Breakfast")
        ledger.record(bf, di)
        l_main = _pick(base_pool(Role.MAIN, member, season), member, ledger, di, warnings, "Lunch main")
        ledger.record(l_main, di)
        l_veg = _pick(base_pool(Role.VEG, member, season), member, ledger, di, warnings, "Lunch veg")
        ledger.record(l_veg, di)
        d_main = _pick(base_pool(Role.MAIN, member, season), member, ledger, di, warnings, "Dinner main")
        ledger.record(d_main, di)
        d_veg = _pick(base_pool(Role.VEG, member, season), member, ledger, di, warnings, "Dinner veg")
        ledger.record(d_veg, di)
        snacks = self._pick_snacks(member, ledger, di, season, warnings, n=2)
        for sr in snacks:
            ledger.record(sr, di)

        # alternate the staple grain by slot & day for variety (grains are Tier-0/exempt)
        lunch_grain = RECIPES["rice_plain" if di % 2 == 0 else "roti"]
        dinner_grain = RECIPES["roti" if di % 2 == 0 else "rice_plain"]

        def assemble(ms: float):
            bf_c = make_component(bf)
            lm, dm = make_component(l_main, ms), make_component(d_main, ms)
            lv, dv = make_component(l_veg), make_component(d_veg)
            sn = [make_component(s) for s in snacks]
            fixed = [bf_c, lm, lv, dm, dv, *sn]
            fixed_kcal = sum(c.nutrients["kcal"] for c in fixed)
            grain_kcal = max(targets.kcal - fixed_kcal, 250.0)
            lg = self._grain_component(lunch_grain, grain_kcal / 2)
            dg = self._grain_component(dinner_grain, grain_kcal / 2)
            protein = (sum(c.nutrients["protein"] for c in fixed)
                       + lg.nutrients["protein"] + dg.nutrients["protein"])
            return bf_c, lm, lv, dm, dv, sn, lg, dg, protein

        # Grow the mains (bounded) until the protein target is ~met (grains then fill less energy).
        ms = main_scale0
        packed = assemble(ms)
        for _ in range(4):
            if packed[-1] >= 0.9 * targets.protein_g or ms >= 2.0:
                break
            ms = min(2.0, ms + 0.3)
            packed = assemble(ms)
        bf_c, lm, lv, dm, dv, sn, lg, dg, _ = packed

        empty = MealEntry(MealSlot.SNACK2, [], zero())
        entries = [
            MealEntry(MealSlot.BREAKFAST, [bf_c], bf_c.nutrients),
            self._combo(MealSlot.LUNCH, [lg, lm, lv]),
            self._combo(MealSlot.DINNER, [dg, dm, dv]),
            MealEntry(MealSlot.SNACK1, [sn[0]], sn[0].nutrients) if sn else empty,
            MealEntry(MealSlot.SNACK2, [sn[1]], sn[1].nutrients) if len(sn) > 1 else empty,
        ]
        totals = zero()
        for e in entries:
            totals = add(totals, e.nutrients)

        dp = DayPlan(date=d.isoformat(), member_id=member.id, season=season.value,
                     entries=entries, totals=totals,
                     notes="; ".join(dict.fromkeys(warnings)))
        return dp, validate(dp, targets)

    def _grain_component(self, grain: Recipe, kcal_target: float):
        base_kcal = make_component(grain).nutrients["kcal"]
        scale = max(GRAIN_SCALE_BOUNDS[0], min(GRAIN_SCALE_BOUNDS[1], kcal_target / base_kcal))
        return make_component(grain, scale)

    def _combo(self, slot: MealSlot, comps) -> MealEntry:
        n = zero()
        for c in comps:
            n = add(n, c.nutrients)
        return MealEntry(slot, comps, n)

    def _pick_snacks(self, member, ledger, di, season, warnings, n=2):
        pool = base_pool(Role.SNACK, member, season)
        chosen = []
        for _ in range(n):
            cands = sorted([r for r in pool if r.id not in {c.id for c in chosen}],
                           key=lambda r: _score(r, member, ledger, di), reverse=True)
            pick = next((r for r in cands if ledger.allowed(r, di)), cands[0] if cands else None)
            if pick:
                chosen.append(pick)
        return chosen

    # ---- iso-nutrient alternatives (PRD §11.6) ----
    def alternatives(self, member: Member, recipe_id: str, season: Season,
                     ledger: Optional[Ledger] = None, di: int = 0, n: int = 3):
        ledger = ledger or Ledger(single_region=len(member.region_prefs) == 1)
        target = RECIPES[recipe_id]
        orig = make_component(target).nutrients
        pool = [r for r in base_pool(target.role, member, season)
                if r.id != recipe_id and ledger.freq_allowed(r, di)]
        ranked = sorted(pool, key=lambda r: iso_distance(make_component(r).nutrients, orig))
        result = []
        for r in ranked[:n]:
            nut = make_component(r).nutrients
            result.append({"recipe": r, "nutrients": nut, "delta": delta_label(nut, orig)})
        return result


# ---------------------------------------------------------------------------
# Validator (always deterministic) — PRD §9.4
# ---------------------------------------------------------------------------
def validate(day: DayPlan, t: NutrientTargets) -> ValidationReport:
    tot = day.totals
    checks: Dict[str, tuple] = {}
    hard: List[str] = []
    warns: List[str] = list(filter(None, day.notes.split("; "))) if day.notes else []

    kcal_ok = t.kcal * (1 - KCAL_TOLERANCE) <= tot["kcal"] <= t.kcal * (1 + KCAL_TOLERANCE)
    checks["kcal"] = (round(tot["kcal"]), t.kcal, kcal_ok)
    if not kcal_ok:
        warns.append(f"Energy {round(tot['kcal'])} kcal outside ±{int(KCAL_TOLERANCE*100)}% of {t.kcal}")

    prot_ok = tot["protein"] >= 0.9 * t.protein_g
    checks["protein"] = (round(tot["protein"], 1), t.protein_g, prot_ok)
    if tot["protein"] < 0.7 * t.protein_g:
        hard.append(f"Protein {round(tot['protein'])} g well below target {t.protein_g} g")
    elif not prot_ok:
        warns.append(f"Protein {round(tot['protein'])} g just under target {t.protein_g} g — add a protein source")

    na_ok = tot["sodium"] <= t.sodium_mg_max
    checks["sodium"] = (round(tot["sodium"]), t.sodium_mg_max, na_ok)
    if not na_ok:
        hard.append(f"Sodium {round(tot['sodium'])} mg over limit {round(t.sodium_mg_max)} mg")

    fib_ok = tot["fibre"] >= 0.85 * t.fibre_g
    checks["fibre"] = (round(tot["fibre"], 1), t.fibre_g, fib_ok)

    passed = sum(1 for _, _, ok in checks.values() if ok)
    dqs = int(60 + passed * 8 + (8 if not warns else 0) + (0 if hard else 4))
    dqs = max(0, min(100, dqs))
    in_tol = kcal_ok and not hard
    return ValidationReport(in_tolerance=in_tol, checks=checks,
                            hard_violations=hard, warnings=warns, dqs=dqs)
