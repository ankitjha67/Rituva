"""Recommended Dietary Allowances and deficiency disorders — the reference module.

Two tables, both transcribed rather than estimated:

  * `RDA_GROUPS` — ICMR-NIN Recommended Dietary Allowances for Indians, taken from
    Annexure 3 (pp. 89-90) of *Dietary Guidelines for Indians* (NIN/ICMR). Every life
    stage the source covers: men and women by activity level, pregnancy, lactation,
    infants, children, and boys/girls by age band.
  * `DEFICIENCIES` — what a shortfall of each nutrient does. Entries the guidelines
    state directly are marked `source="DGI"`; the rest are standard clinical facts
    (WHO/ICMR textbook) and are marked `source="clinical"`, so the two are never
    conflated.

A units note, because it matters medically. The vitamin table's header column renders
as "mg/d" for vitamin A, folate and vitamin B12, but the values there are micrograms —
600 mg of retinol would be acutely toxic, and the ICMR figure is 600 µg. The µ glyph is
dropped in places by the PDF's font encoding (the same table renders infant iron as
"46 µg/kg/day" correctly and infant niacin as "710mg/kg" incorrectly). Units below are
the physiologically correct ones; `UNIT_NOTE` records the discrepancy.
"""
from __future__ import annotations

from typing import Optional

SOURCE = ("ICMR-NIN, *Dietary Guidelines for Indians — A Manual* (National Institute of "
          "Nutrition, Hyderabad; document dated 2012), Annexure 3, pp. 89-90. The "
          "allowances in that annexure are the ICMR 2010 revision.")
EDITION = "ICMR 2010 RDA, as printed in the NIN Dietary Guidelines manual (2012)"

UNIT_NOTE = (
    "Vitamin A, folate and vitamin B12 are micrograms (µg) per day. The source table's "
    "header prints 'mg' for these columns, but the values are µg — the µ glyph is lost "
    "in parts of the PDF. ICMR's vitamin A allowance is 600 µg retinol equivalent."
)

# Where this table and the app's own planning targets disagree — and they do, because
# they are different editions ten years apart. Surfacing this is not optional: without
# it, Analytics would say "iron 29 mg" while the reference table said "21 mg" for the
# same woman, and a reader would rightly not trust either number.
#
# `table` is what the 2010 annexure above prints; `planning` is what `targets.py` uses to
# build menus (the ICMR-NIN 2020 revision, which raised all three). The app plans against
# the newer figures because they are the current standard, and shows both here.
RECONCILIATION = [
    {"nutrient": "Iron", "unit": "mg/day",
     "table": "17 (man) · 21 (woman)", "planning": "19 (man) · 29 (woman)",
     "why": "The 2020 revision raised iron for adults, most sharply for women of "
            "reproductive age, on updated absorption and menstrual-loss estimates."},
    {"nutrient": "Calcium", "unit": "mg/day",
     "table": "600 (adults)", "planning": "1000 (adults)",
     "why": "The 2020 revision raised adult calcium from 600 to 1000 mg/day."},
    {"nutrient": "Vitamin B12", "unit": "µg/day",
     "table": "1", "planning": "2.2",
     "why": "The 2020 revision more than doubled the B12 allowance — relevant here, since "
            "a lacto-vegetarian diet gets B12 only from dairy."},
]
RECONCILIATION_NOTE = (
    "Menus are planned against the newer ICMR-NIN 2020 allowances, so the targets on "
    "Today and Analytics can read higher than this table for iron, calcium and B12. "
    "The table is reproduced as printed rather than quietly updated, because only some "
    "of its values changed in 2020 and the rest are unchanged."
)


class RDA:
    """One life-stage group's daily allowances. `None` means the source leaves it blank
    (it is not an implied zero, and is never filled in by guesswork)."""

    __slots__ = ("group", "stage", "sex", "age_range", "weight_kg", "kcal", "protein_g",
                 "visible_fat_g", "calcium_mg", "iron_mg", "vit_a_ug", "thiamin_mg",
                 "riboflavin_mg", "niacin_mg", "pyridoxine_mg", "vit_c_mg", "folate_ug",
                 "b12_ug", "magnesium_mg", "zinc_mg", "note")

    def __init__(self, group, stage, sex, age_range, weight_kg, kcal, protein_g,
                 visible_fat_g, calcium_mg, iron_mg, vit_a_ug=None, thiamin_mg=None,
                 riboflavin_mg=None, niacin_mg=None, pyridoxine_mg=None, vit_c_mg=None,
                 folate_ug=None, b12_ug=None, magnesium_mg=None, zinc_mg=None, note=""):
        self.group, self.stage, self.sex, self.age_range = group, stage, sex, age_range
        self.weight_kg, self.kcal, self.protein_g = weight_kg, kcal, protein_g
        self.visible_fat_g, self.calcium_mg, self.iron_mg = visible_fat_g, calcium_mg, iron_mg
        self.vit_a_ug, self.thiamin_mg, self.riboflavin_mg = vit_a_ug, thiamin_mg, riboflavin_mg
        self.niacin_mg, self.pyridoxine_mg, self.vit_c_mg = niacin_mg, pyridoxine_mg, vit_c_mg
        self.folate_ug, self.b12_ug = folate_ug, b12_ug
        self.magnesium_mg, self.zinc_mg, self.note = magnesium_mg, zinc_mg, note

    def to_dict(self) -> dict:
        return {k: getattr(self, k) for k in self.__slots__}


# ---------------------------------------------------------------------------
# Annexure 3 — Macronutrients & minerals (p. 89) merged with Vitamins (p. 90)
# ---------------------------------------------------------------------------
RDA_GROUPS = [
    RDA("Man", "Sedentary work", "M", "18+ years", 60, 2320, 60, 25, 600, 17,
        vit_a_ug=600, thiamin_mg=1.2, riboflavin_mg=1.4, niacin_mg=16, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=1, magnesium_mg=340, zinc_mg=12),
    RDA("Man", "Moderate work", "M", "18+ years", 60, 2730, 60, 30, 600, 17,
        vit_a_ug=600, thiamin_mg=1.4, riboflavin_mg=1.6, niacin_mg=18, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=1, magnesium_mg=340, zinc_mg=12),
    RDA("Man", "Heavy work", "M", "18+ years", 60, 3490, 60, 40, 600, 17,
        vit_a_ug=600, thiamin_mg=1.7, riboflavin_mg=2.1, niacin_mg=21, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=1, magnesium_mg=340, zinc_mg=12),

    RDA("Woman", "Sedentary work", "F", "18+ years", 55, 1900, 55, 20, 600, 21,
        vit_a_ug=600, thiamin_mg=1.0, riboflavin_mg=1.1, niacin_mg=12, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=1, magnesium_mg=310, zinc_mg=10),
    RDA("Woman", "Moderate work", "F", "18+ years", 55, 2230, 55, 25, 600, 21,
        vit_a_ug=600, thiamin_mg=1.1, riboflavin_mg=1.3, niacin_mg=14, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=1, magnesium_mg=310, zinc_mg=10),
    RDA("Woman", "Heavy work", "F", "18+ years", 55, 2850, 55, 30, 600, 21,
        vit_a_ug=600, thiamin_mg=1.4, riboflavin_mg=1.7, niacin_mg=16, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=1, magnesium_mg=310, zinc_mg=10),

    RDA("Woman", "Pregnant", "F", "18+ years", None, None, None, 30, 1200, 35,
        vit_a_ug=800, pyridoxine_mg=2.5, vit_c_mg=60, folate_ug=500, b12_ug=1.2, zinc_mg=12,
        note="Add +350 kcal/day and +23 g protein/day to her pre-pregnancy allowance; "
             "thiamin +0.2, riboflavin +0.3, niacin +2 mg/day."),
    RDA("Woman", "Lactating, 0-6 months", "F", "18+ years", None, None, None, 30, 1200, 21,
        vit_a_ug=950, pyridoxine_mg=2.5, vit_c_mg=80, folate_ug=300, b12_ug=1.5,
        note="Add +600 kcal/day and +19 g protein/day; thiamin +0.3, riboflavin +0.4, "
             "niacin +4 mg/day."),
    RDA("Woman", "Lactating, 6-12 months", "F", "18+ years", None, None, None, 30, 1200, 21,
        vit_a_ug=950, pyridoxine_mg=2.5, vit_c_mg=80, folate_ug=300, b12_ug=1.5,
        note="Add +520 kcal/day and +13 g protein/day; thiamin +0.2, riboflavin +0.3, "
             "niacin +3 mg/day."),

    RDA("Infant", "0-6 months", "any", "0-6 months", 5.4, None, None, None, 500, None,
        pyridoxine_mg=0.1, vit_c_mg=25, folate_ug=25, b12_ug=0.2, magnesium_mg=30,
        thiamin_mg=0.2, riboflavin_mg=0.3,
        note="Energy 92 kcal/kg/day, protein 1.16 g/kg/day, iron 46 µg/kg/day, "
             "niacin 710 µg/kg/day. Breast-milk meets these for the first six months."),
    RDA("Infant", "6-12 months", "any", "6-12 months", 8.4, None, None, 19, 500, 5,
        vit_a_ug=350, thiamin_mg=0.3, riboflavin_mg=0.4, pyridoxine_mg=0.4, vit_c_mg=25,
        folate_ug=45, b12_ug=0.2, magnesium_mg=45,
        note="Energy 80 kcal/kg/day, protein 1.69 g/kg/day, niacin 650 µg/kg/day."),

    RDA("Child", "1-3 years", "any", "1-3 years", 12.9, 1060, 16.7, 27, 600, 9,
        vit_a_ug=400, thiamin_mg=0.5, riboflavin_mg=0.6, niacin_mg=8, pyridoxine_mg=0.9,
        vit_c_mg=40, folate_ug=80, b12_ug=0.2, magnesium_mg=50, zinc_mg=5),
    RDA("Child", "4-6 years", "any", "4-6 years", 18, 1350, 20.1, 25, 600, 13,
        vit_a_ug=400, thiamin_mg=0.7, riboflavin_mg=0.8, niacin_mg=11, pyridoxine_mg=0.9,
        vit_c_mg=40, folate_ug=100, b12_ug=0.2, magnesium_mg=70, zinc_mg=7),
    RDA("Child", "7-9 years", "any", "7-9 years", 25.1, 1690, 29.5, 30, 600, 16,
        vit_a_ug=600, thiamin_mg=0.8, riboflavin_mg=1.0, niacin_mg=13, pyridoxine_mg=1.6,
        vit_c_mg=40, folate_ug=120, b12_ug=0.2, magnesium_mg=100, zinc_mg=8),

    RDA("Boy", "10-12 years", "M", "10-12 years", 34.3, 2190, 39.9, 35, 800, 21,
        vit_a_ug=600, thiamin_mg=1.1, riboflavin_mg=1.3, niacin_mg=15, pyridoxine_mg=1.6,
        vit_c_mg=40, folate_ug=140, b12_ug=0.2, magnesium_mg=120, zinc_mg=9),
    RDA("Girl", "10-12 years", "F", "10-12 years", 35.0, 2010, 40.4, 35, 800, 27,
        vit_a_ug=600, thiamin_mg=1.0, riboflavin_mg=1.2, niacin_mg=13, pyridoxine_mg=1.6,
        vit_c_mg=40, folate_ug=160, b12_ug=0.2, magnesium_mg=160, zinc_mg=9),
    RDA("Boy", "13-15 years", "M", "13-15 years", 47.6, 2750, 54.3, 45, 800, 32,
        vit_a_ug=600, thiamin_mg=1.4, riboflavin_mg=1.6, niacin_mg=16, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=150, b12_ug=0.2, magnesium_mg=165, zinc_mg=11),
    RDA("Girl", "13-15 years", "F", "13-15 years", 46.6, 2330, 51.9, 40, 800, 27,
        vit_a_ug=600, thiamin_mg=1.2, riboflavin_mg=1.4, niacin_mg=14, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=210, b12_ug=0.2, magnesium_mg=210, zinc_mg=11),
    RDA("Boy", "16-17 years", "M", "16-17 years", 55.4, 3020, 61.5, 50, 800, 28,
        vit_a_ug=600, thiamin_mg=1.5, riboflavin_mg=1.8, niacin_mg=17, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=0.2, magnesium_mg=195, zinc_mg=12),
    RDA("Girl", "16-17 years", "F", "16-17 years", 52.1, 2440, 55.5, 35, 800, 26,
        vit_a_ug=600, thiamin_mg=1.0, riboflavin_mg=1.2, niacin_mg=14, pyridoxine_mg=2.0,
        vit_c_mg=40, folate_ug=200, b12_ug=0.2, magnesium_mg=235, zinc_mg=12),
]


# ---------------------------------------------------------------------------
# Deficiency disorders
# ---------------------------------------------------------------------------
# `source`: "DGI"      -> stated in the Dietary Guidelines for Indians (quoted/paraphrased)
#           "clinical" -> standard WHO/ICMR clinical knowledge, included for completeness
#                         and labelled so it is never mistaken for a claim from the PDF.
DEFICIENCIES = [
    {"nutrient": "Protein & energy", "condition": "Protein Energy Malnutrition (PEM)",
     "effects": "Kwashiorkor and marasmus in young children; underweight, stunting "
                "(low height for age) and wasting (low weight for height). In adults a "
                "sustained shortfall gives Chronic Energy Deficiency (BMI under 18.5).",
     "at_risk": "Preschool children, adolescent girls, pregnant women, the very poor",
     "foods": "Pulses, milk and milk products, eggs, meat, fish, nuts and oilseeds, "
              "cereal-pulse combinations",
     "source": "DGI"},

    {"nutrient": "Iron", "condition": "Iron Deficiency Anaemia (IDA)",
     "effects": "Anaemia — fatigue and breathlessness. In pregnancy it raises maternal "
                "mortality and the risk of low-birth-weight infants; in children it "
                "increases susceptibility to infection and impairs learning ability.",
     "at_risk": "Women of reproductive age, pregnant women, infants and young children",
     "foods": "Green leafy vegetables, legumes, dry fruits; meat, fish and poultry (better "
              "absorbed). Vitamin C-rich amla, guava and citrus improve absorption from "
              "plant foods; tea with meals blocks it.",
     "source": "DGI"},

    {"nutrient": "Iodine", "condition": "Iodine Deficiency Disorders (IDD)",
     "effects": "Goitre (enlarged thyroid); in the mother it causes cretinism, mental "
                "retardation, delayed motor development, stunting, deaf-mutism and "
                "neuromuscular disorders in the child.",
     "at_risk": "Populations in iodine-poor regions; pregnant women above all",
     "foods": "Iodised salt, sea fish, milk", "source": "DGI"},

    {"nutrient": "Vitamin A", "condition": "Vitamin A Deficiency (VAD)",
     "effects": "Night blindness and Bitot's spots, progressing to xerophthalmia and "
                "irreversible blindness; also raises the risk of infection and death.",
     "at_risk": "Preschool children, pregnant and lactating women",
     "foods": "Green leafy vegetables, carrot, pumpkin, mango, papaya; milk, egg, liver",
     "source": "DGI"},

    {"nutrient": "Folate (folic acid)", "condition": "Macrocytic (megaloblastic) anaemia",
     "effects": "Macrocytic anaemia. In pregnancy, deficiency raises the risk of neural "
                "tube defects and other congenital anomalies and lowers birth weight.",
     "at_risk": "Pregnant women, especially preconception and the first trimester",
     "foods": "Green leafy vegetables, legumes, nuts, liver", "source": "DGI"},

    {"nutrient": "Vitamin C (ascorbic acid)", "condition": "Scurvy",
     "effects": "Weakness, bleeding gums and defective bone growth; poor wound healing "
                "and reduced iron absorption from plant foods.",
     "at_risk": "Diets without fresh fruit or vegetables; heavy smokers",
     "foods": "Amla, guava, citrus, tomato, capsicum, fresh vegetables", "source": "DGI"},

    {"nutrient": "Vitamin B12", "condition": "Megaloblastic anaemia; neuropathy",
     "effects": "Megaloblastic anaemia with tingling and numbness, poor balance and, if "
                "prolonged, irreversible nerve damage. Often overlooked because folate "
                "can mask the anaemia while nerve damage continues.",
     "at_risk": "Long-term vegetarians and vegans, older adults, people on metformin",
     "foods": "Milk and curd, paneer, eggs; fish and meat. Plant foods carry essentially "
              "none, so vegetarians rely on dairy or fortified foods.",
     "source": "clinical"},

    {"nutrient": "Vitamin D", "condition": "Rickets (children); osteomalacia (adults)",
     "effects": "Softening and bowing of bones, delayed growth and bone pain in children; "
                "bone pain, muscle weakness and higher fracture risk in adults. Calcium "
                "cannot be absorbed properly without it.",
     "at_risk": "Little sunlight exposure, covered clothing, older adults, infants",
     "foods": "Sunlight is the main source; fortified milk, egg yolk, fatty fish",
     "source": "clinical"},

    {"nutrient": "Calcium", "condition": "Osteopenia / osteoporosis; poor peak bone mass",
     "effects": "Reduced bone density and higher fracture risk; in children, inadequate "
                "peak bone mass. Works together with vitamin D.",
     "at_risk": "Adolescents, pregnant and lactating women, postmenopausal women",
     "foods": "Milk, curd, paneer; ragi, sesame, green leafy vegetables, small fish "
              "eaten with bones",
     "source": "clinical"},

    {"nutrient": "Thiamin (B1)", "condition": "Beriberi",
     "effects": "Wet beriberi affects the heart (oedema, breathlessness); dry beriberi "
                "affects the nerves (weakness, burning feet). Classically linked to "
                "polished-rice diets.",
     "at_risk": "Diets dominated by polished rice or refined flour; chronic alcohol use",
     "foods": "Whole grains, millets, pulses, nuts; parboiled rather than polished rice",
     "source": "clinical"},

    {"nutrient": "Riboflavin (B2)", "condition": "Ariboflavinosis",
     "effects": "Cracks at the corners of the mouth (angular stomatitis), sore red "
                "tongue, and a burning gritty sensation in the eyes.",
     "at_risk": "Low intake of milk and green leafy vegetables",
     "foods": "Milk and curd, eggs, green leafy vegetables, whole grains, pulses",
     "source": "clinical"},

    {"nutrient": "Niacin (B3)", "condition": "Pellagra",
     "effects": "The classic triad: dermatitis on sun-exposed skin, diarrhoea and "
                "dementia. Associated with maize-dominated diets.",
     "at_risk": "Diets dominated by maize/jowar with little pulse or milk",
     "foods": "Groundnut, pulses, whole grains, milk, meat and fish", "source": "clinical"},

    {"nutrient": "Zinc", "condition": "Growth faltering; impaired immunity",
     "effects": "Poor growth and delayed sexual maturation, more frequent and prolonged "
                "diarrhoea and respiratory infections, poor wound healing, loss of taste.",
     "at_risk": "Young children, adolescents, pregnant women, mainly-cereal diets",
     "foods": "Whole grains, pulses, nuts and oilseeds, milk; meat and shellfish",
     "source": "clinical"},

    {"nutrient": "Dietary fibre", "condition": "Constipation; metabolic risk",
     "effects": "Constipation and poor gut health; low intake is associated with higher "
                "risk of obesity, type-2 diabetes and heart disease.",
     "at_risk": "Diets built on refined cereals with few vegetables, fruit or pulses",
     "foods": "Whole grains and millets, pulses, vegetables, fruit with the skin on",
     "source": "clinical"},
]


# ---------------------------------------------------------------------------
def for_member(sex: str, age: int, pal: float = 1.4) -> Optional[RDA]:
    """The RDA row that best matches a member — used to show 'your reference group'
    beside their computed targets. Returns None if nothing matches."""
    stage_by_pal = "Sedentary work" if pal < 1.45 else (
        "Moderate work" if pal < 1.7 else "Heavy work")

    if age < 1:
        want = ("Infant", "6-12 months")
    elif age <= 3:
        want = ("Child", "1-3 years")
    elif age <= 6:
        want = ("Child", "4-6 years")
    elif age <= 9:
        want = ("Child", "7-9 years")
    elif age <= 12:
        want = ("Boy" if sex == "M" else "Girl", "10-12 years")
    elif age <= 15:
        want = ("Boy" if sex == "M" else "Girl", "13-15 years")
    elif age <= 17:
        want = ("Boy" if sex == "M" else "Girl", "16-17 years")
    else:
        want = ("Man" if sex == "M" else "Woman", stage_by_pal)

    for r in RDA_GROUPS:
        if (r.group, r.stage) == want:
            return r
    return None


def to_dict() -> dict:
    """The whole reference, JSON-ready — served by the API and bundled for offline use."""
    return {
        "source": SOURCE,
        "edition": EDITION,
        "unit_note": UNIT_NOTE,
        "reconciliation": RECONCILIATION,
        "reconciliation_note": RECONCILIATION_NOTE,
        "units": {
            "kcal": "kcal/day", "protein_g": "g/day", "visible_fat_g": "g/day",
            "calcium_mg": "mg/day", "iron_mg": "mg/day", "vit_a_ug": "µg/day",
            "thiamin_mg": "mg/day", "riboflavin_mg": "mg/day", "niacin_mg": "mg/day",
            "pyridoxine_mg": "mg/day", "vit_c_mg": "mg/day", "folate_ug": "µg/day",
            "b12_ug": "µg/day", "magnesium_mg": "mg/day", "zinc_mg": "mg/day",
        },
        "groups": [r.to_dict() for r in RDA_GROUPS],
        "deficiencies": DEFICIENCIES,
    }
