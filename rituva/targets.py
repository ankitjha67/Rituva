"""TargetEngine — computes each member's daily nutrient targets from the guidelines,
with the precedence order of PRD §6.5:

    doctor_diet  >  known (user/dietitian) targets  >  guideline-computed

Formulae and limits are all cited to DGI 2024 / WHO (see `knowledge.GUIDELINE_RULES`).
No target is ever produced by an LLM.
"""
from __future__ import annotations

from dataclasses import replace
from typing import Tuple

from .domain import Goal, Member, NutrientTargets, Sex

# Guideline constants (cited)
FAT_PCT = 0.27                       # DGI 2024 p.54 (20-30%E)
FIBRE_PER_1000 = 25.0                # DGI 2024 p.17
SODIUM_MAX = 2000.0                  # DGI 2024 p.91 (<5 g salt)
ADDED_SUGAR_MAX = 25.0               # DGI 2024 p.111
ENERGY_FLOOR = 1000.0                # DGI 2024 p.64
PROTEIN_G_PER_KG = {                 # goal -> g/kg (DGI p.58 RDA 0.83; muscle ≤1.6, p.60)
    Goal.MAINTAIN: 1.0, Goal.LOSE: 1.2, Goal.GAIN: 1.4, Goal.MUSCLE: 1.5,
}
GOAL_KCAL_ADJ = {Goal.MAINTAIN: 0, Goal.LOSE: -500, Goal.GAIN: 350, Goal.MUSCLE: 300}
# Micronutrient RDAs — ICMR-NIN 2020 (adults). Iron is sex-specific (menstrual losses).
IRON_MG_RDA = {Sex.M: 19.0, Sex.F: 29.0}
CALCIUM_MG_RDA = 1000.0
B12_UG_RDA = 2.2
CITATIONS = ("DGI 2024 p.54/58", "WHO FS-394", "ICMR-NIN RDA 2020")


def bmi(weight_kg: float, height_cm: float) -> float:
    h = height_cm / 100.0
    return weight_kg / (h * h)


def bmi_category_asian(value: float) -> str:
    """Asian cut-offs — DGI 2024 p.62-64."""
    if value < 18.5:
        return "Underweight"
    if value < 23:
        return "Normal"
    if value < 27.5:
        return "Overweight"
    return "Obese"


def bmr_mifflin(sex: Sex, weight_kg: float, height_cm: float, age: int) -> float:
    """Mifflin–St Jeor (the formula the reference Excel uses)."""
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return base + (5 if sex == Sex.M else -161)


def tdee(member: Member) -> float:
    return bmr_mifflin(member.sex, member.weight_kg, member.height_cm, member.age) * member.pal


def compute_targets(member: Member) -> NutrientTargets:
    """Guideline-computed targets (precedence tier 4)."""
    kcal = tdee(member) + GOAL_KCAL_ADJ.get(member.goal, 0)
    kcal = max(kcal, ENERGY_FLOOR)
    protein_g = PROTEIN_G_PER_KG.get(member.goal, 1.0) * member.weight_kg
    fat_g = kcal * FAT_PCT / 9.0
    carb_kcal = max(kcal - protein_g * 4 - fat_g * 9, 0)
    carb_g = carb_kcal / 4.0
    fibre_g = FIBRE_PER_1000 * kcal / 1000.0
    return NutrientTargets(
        kcal=round(kcal), protein_g=round(protein_g), fat_g=round(fat_g),
        carb_g=round(carb_g), fibre_g=round(fibre_g),
        sodium_mg_max=SODIUM_MAX, added_sugar_g_max=ADDED_SUGAR_MAX,
        iron_mg=IRON_MG_RDA.get(member.sex, 19.0),
        calcium_mg=CALCIUM_MG_RDA, b12_ug=B12_UG_RDA,
        source="computed", citations=CITATIONS,
    )


def effective_targets(member: Member) -> NutrientTargets:
    """Apply the §6.5 precedence: doctor > known > computed.

    Doctor/known values are user-supplied FACTS and are used verbatim (not recomputed
    or 'optimised'). Anything they omit falls back to the computed value.
    """
    t = compute_targets(member)

    def _overlay(src: dict, source_name: str) -> NutrientTargets:
        return replace(
            t,
            kcal=src.get("kcal", t.kcal),
            protein_g=src.get("protein_g", t.protein_g),
            fat_g=src.get("fat_g", t.fat_g),
            carb_g=src.get("carb_g", t.carb_g),
            fibre_g=src.get("fibre_g", t.fibre_g),
            sodium_mg_max=src.get("sodium_mg_max", t.sodium_mg_max),
            added_sugar_g_max=src.get("added_sugar_g_max", t.added_sugar_g_max),
            iron_mg=src.get("iron_mg", t.iron_mg),
            calcium_mg=src.get("calcium_mg", t.calcium_mg),
            b12_ug=src.get("b12_ug", t.b12_ug),
            source=source_name,
            citations=(src.get("source", source_name),),
        )

    if member.known_targets:
        t = _overlay(member.known_targets, "user_provided")
    if member.doctor_diet:
        t = _overlay(member.doctor_diet, "doctor_prescription")
    return t


def targets_report(member: Member) -> Tuple[NutrientTargets, dict]:
    """Return targets plus the derived anthropometry used to compute them."""
    b = bmi(member.weight_kg, member.height_cm)
    info = {
        "bmi": round(b, 1),
        "bmi_category": bmi_category_asian(b),
        "bmr": round(bmr_mifflin(member.sex, member.weight_kg, member.height_cm, member.age)),
        "tdee": round(tdee(member)),
    }
    return effective_targets(member), info
