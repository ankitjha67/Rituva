# Product Requirements Document
# Rituva — An Open-Source, Guideline-Grounded, Seasonal & Region-Aware Nutrition and Menu Planner

**Document status:** Draft v1.5
**Author:** Product & Engineering
**Last updated:** 2026-07-25
**Working title / codename:** Rituva (successor to the personal "Eastern Diet Planner" Excel workbooks)
**Changelog v1.1:** Dedicated per-user profiles; **regional North/South/East/West Indian diet preferences with multi-select blending** (§5.2, §7.6); **clinical/lab measurements and user-known nutritional targets** (§5.1); **doctor-prescribed diet as an authoritative input** (§6.5); explicit **growth & development** framing (§2, §6.2); **Android app + responsive website** platforms and a **Platforms / Information-Architecture / Visual-Design** section with a browseable prototype for tab-by-tab approval (§17).
**Changelog v1.2:** **Frequency regulation & interchangeability** — per-ingredient / category / cuisine caps so nothing over-repeats (no mushroom 3×/wk, paneer 4×/wk, or clustered regional days) (§8.5); **iso-nutrient swap & alternatives** — decline any dish and get equivalent-calorie/nutrient options, each showing a **per-ingredient nutrient breakdown read from the Knowledge DB (IFCT 2017), never the LLM** (§11.6); **advanced grounded RAG + LangGraph orchestration + per-user LLM memory** for mapping and generation (§9.7, §12.3); Swap/Alternatives screen added to the design (§17.4).
**Changelog v1.3:** **NVIDIA `build.nvidia.com` (NIM) as a first-class provider** plus **key-only configuration** — the user just pastes & saves an API key, and models are **auto-discovered and auto-configured** (best model for quality steps, fast model for cheap steps) with an **availability-aware graceful fallback** chain that switches to the next working model/provider automatically, and finally to the no-LLM deterministic planner (§10.5); project scaffolding started (schema + target engine + deterministic planner + LangGraph skeleton, §18).
**Changelog v1.5:** Reference implementation now covers **all four build phases (A–D)** — expanded Knowledge DB, hybrid RAG + long-term memory through the LangGraph pipeline, the food-logging + adherence feedback loop, and a **served PWA frontend** (`web/`, at `/app`) on the approved design (§18.4). Added **`CONTEXT.md`** as the living build tracker. (A second session, "Kimi", co-built Phases B/C; independently re-verified.)
**Changelog v1.4:** Product **renamed NutriPlan → Rituva** (the earlier name is taken on the app stores; *Rituva* is from Sanskrit ऋतु, *ritu*, "season" — see §2.1). Added **system-context detection** — date, time, season and the current meal are read from the device clock (§7.8, `context.py`, `GET /context`). Shipped the **FastAPI REST layer + SQLite persistence** (`api.py`, `store.py`, §18). Added **§19 — competitive landscape & feature-gap roadmap** from an app-store survey of the category (logging/wearable/CGM/adaptive-target gaps we don't yet cover).

---

## 0. How to read this document

This PRD specifies an application that turns a person's **profile + dietary preferences + region** into **daily, weekly, monthly and full-year menu plans** that are (a) nutritionally adequate against published dietary guidelines, (b) built from **seasonal, locally-available** vegetables, pulses and staple foods, (c) tuned for **age-related ailments, growth, and lifestyle/NCD management**, and (d) **non-repeating** across the year at the dish/menu level.

Two hard commitments shape every design decision:

1. **Evidence, not invention.** Every nutrition rule, target, threshold, portion and food-group quantity in this system traces to a named source document, page-cited in §14 (Evidence Register). The LLM is never the source of a number. This is a first-class architectural constraint (§9, §10), not a disclaimer.
2. **Fully open source and LLM-agnostic.** The entire stack is open-source-licensable, can run **100% locally/offline**, and can drive menu generation with **any** LLM — paid API (Claude, GPT, Gemini) or open-weights local model (Llama, Qwen, Mistral via Ollama/vLLM/llama.cpp) — behind a single adapter interface (§10).

The existing **Eastern Diet Planner** Excel workbooks (v5/v6.3/v7) are the reference implementation of the desired *output*; Rituva generalizes them from a hand-authored 52-week personal sheet into a profile-driven engine for any user, region, life-stage and health condition (§2.4, §11).

---

## 1. Evidence base (the sources this product is built on)

Rituva's nutrition logic is derived **exclusively** from the following primary sources. All were read in full during requirements analysis; exact figures with page citations are consolidated in §14.

| # | Short name | Full identity | Role in product |
|---|-----------|---------------|-----------------|
| S1 | **DGI 2024** | *Dietary Guidelines for Indians, Revised Edition 2024* — ICMR-National Institute of Nutrition (NIN), Hyderabad. 148 pp, **17 guidelines, 10 food groups**. | **Primary** rule base: My Plate, food-group quantities by body weight/life-stage, macro/micronutrient targets, HFSS thresholds, cooking & safety rules, elderly nutrition. |
| S2 | **Disease Nutrition Therapy** | *Dietary Guidelines & Nutrition Therapy for Specific Diseases* — Nutrition Division, Ministry of Health, Sri Lanka, 2014 (UNICEF). 14 conditions. | **Condition/therapeutic engine**: per-disease macro splits, sodium/protein-per-kg, GI/GL, renal K/PO₄ food lists. |
| S3 | **DGA 2025–2030** | *Dietary Guidelines for Americans, 2025–2030* — USDA & US-HHS, Jan 2026. | **Life-stage guidance** (infancy → older adults, pregnancy, lactation, vegetarian/vegan nutrient-risk lists); a second national FBDG for cross-region generalization. |
| S4 | **WHO FS-394** | WHO *Healthy diet*, Fact Sheet N°394, updated Aug 2018 (+ its 19-item WHO/FAO reference list). | **Global quantified limits**: fat/sat-fat/trans-fat/free-sugar/salt/fruit-veg targets; the WHO/FAO evidence chain (§14.7). |
| S5 | **GNR 2026** | *2026 Global Nutrition Report — Integrating food and health systems for climate-resilient nutrition* — PATH. 132 pp. | **Diet-quality scoring rubric** (variety/diversity, adequacy, moderation, balance); sustainability weighting; life-course framing. |
| S6 | **SOFI 2026** | FAO *The State of Food Security and Nutrition in the World 2026* (`cd8306en`), Cost & Affordability of a Healthy Diet. | **Healthy Diet Basket** (6 groups/11 items @ 2330 kcal); **MDD-W / MDD-C** diet-diversity indicators; **cost/affordability** model for budget-aware planning. |
| S7 | **Eastern Diet Planner** | Personal Excel workbooks v5.xlsm, v6.3.xlsx, v7.xlsm (ICMR-NIN 2024 + IFCT 2017 based). | **Output-format reference** and validated worked example (profile → targets → 52 unique weeks → grocery). |

> **Provenance discipline.** Where two sources disagree (e.g., DGA 2025–2030 protein 1.2–1.6 g/kg vs DGI RDA 0.83 g/kg; DGA sat-fat <10 %E vs DGI <5 %E visible SFA), Rituva stores **both** values as source-attributed rules and selects by the user's active **guideline profile** (default = the user's country FBDG). It never silently averages or invents a compromise number.

---

## 2. Product overview

### 2.1 Vision
A free, open-source nutrition companion — a **lively, futuristic, richly-designed Android app and responsive website** — that gives every person a **doctor-of-guidelines-in-your-kitchen**. Each person has a dedicated profile with their full details (age, BMI, health/lab measurements, diseases, any doctor-prescribed diet, and their own daily calorie/nutrient targets if they know them) and their **regional taste** (North / South / East / West Indian cuisine, singly or blended). From that profile plus the **DGI 2024 and WHO** guidance, an LLM curates daily menu and diet plans that drive **overall growth and development** — telling them exactly what to cook for breakfast, lunch, dinner and snacks, using what is fresh in their region this month, meeting their calorie/protein/fibre/micronutrient needs, respecting every allergy, condition and prescription, and never repeating the same menu across the year. **It strictly follows the source documents; no number is invented and no nutrition fact is hallucinated** (§9). **The name** — *Rituva*, from Sanskrit **ऋतु (ritu, "season")** — reflects the signature idea: eat in tune with your season, auto-detected from your device (§7.8).

### 2.2 Problem statement
- Generic meal-plan apps ignore **regional seasonality**, **local staples/cuisine**, and **Indian/South-Asian food composition**, and rarely encode **national dietary guidelines** faithfully.
- Guideline PDFs (DGI 2024, DGA, WHO) are authoritative but **not actionable** at the plate/day level for a lay user.
- Condition-aware nutrition (diabetes, hypertension, CKD, thyroid, pregnancy, elderly sarcopenia) is fragmented across clinical documents.
- Pure-LLM "AI meal planners" **hallucinate nutrient values and portions**, producing plausible but wrong plans — unacceptable for a health tool.
- Existing personal solution (the Excel planner) is powerful but **hand-authored, single-profile, single-region, and capped at 52 weeks**.

### 2.3 Goals (what success looks like)
- **G1 — Guideline-faithful plans.** Every generated day meets the user's energy/macro/fibre targets within tolerance and violates **zero** hard constraints (allergens, condition limits, exclusions). Measured by the automated validator (§9.4).
- **G2 — Seasonal & regional.** ≥ 80% of vegetables/fruits in any month's plan are in-season for the user's region; staples/pulses reflect the local food culture. (§7.6)
- **G3 — Non-repeating across the year.** No composed dish or full-day menu repeats within a configurable window; a full **366-day** plan is generable with all days distinct at the menu level. (§8)
- **G4 — Age & ailment aware.** Correct life-stage food-group quantities and condition constraints for every supported profile (infant → elderly, pregnancy/lactation, 14+ conditions). (§6)
- **G5 — LLM-agnostic & open source.** Runs with any configured LLM incl. fully local; all components OSS-licensed; offline-capable. (§10, §12)
- **G6 — Zero fabricated nutrition facts.** 100% of nutrient numbers computed from the food-composition DB; 100% of rules carry a source citation surfaced in the UI. (§9)
- **G7 — Excel-parity output.** Reproduces and improves on the Eastern Diet Planner output (profile, targets, week library, grocery list, health alerts) with export back to `.xlsx`. (§11)
- **G8 — Dedicated profiles, regional taste & prescriptions honored.** Each user has a private profile carrying full details, clinical measurements, self-known targets, and regional (N/S/E/W) cuisine preferences (single or multiple). A **doctor-prescribed diet**, when present, is treated as an authoritative constraint that overrides guideline defaults on conflict, with the divergence shown transparently. (§5, §6.5, §7.6)
- **G9 — Two beautiful, consistent surfaces.** A native-quality **Android app** and a **responsive website** share one backend and one design system, delivering a lively/futuristic/rich experience with light & dark themes and an accessible elderly mode. Every tab and layout is specified in §17 and provided as a browseable prototype for approval. (§17)

### 2.4 Non-goals (explicitly out of scope)
- **Not a medical device / not clinical MNT.** Rituva gives *guideline-based general nutrition education*, not individualized medical nutrition therapy. Therapeutic condition modes (CKD stages, dialysis, etc.) are **advisory** and prompt the user to a clinician/renal dietitian. (§13.2)
- Not a calorie-tracking/food-logging app (may integrate later).
- Not a grocery-delivery or recipe-video platform (grocery list is exportable; integrations are future work).
- Does not diagnose disease or prescribe supplements/drugs.
- Does not generate images of food in v1.

### 2.5 Relationship to the Eastern Diet Planner (migration)
The Excel workbook's sheets map directly onto Rituva's domain model, which lets us import the user's existing, validated content as **seed data**:

| Excel sheet | Rituva concept | §ref |
|---|---|---|
| Profile | `Profile` / `HouseholdMember` | §5 |
| Targets | `NutrientTargets` (computed) | §7.3 |
| Rotation | `SeasonCalendar` | §7.6 |
| Week_Library (52×7, 5 meals/day, pipe-delimited) | `Menu` / `DayPlan` / `MealSlot` | §11.2 |
| Ingredients (component→grocery BOM) | `RecipeIngredient` | §7.5 |
| Groceries_All / Grocery_List | `GroceryList` (aggregated, scaled) | §11.4 |
| FoodDB (per-100g, IFCT 2017) | `FoodComposition` | §7.4 |
| Health_Alerts | `ConditionRule` + surfaced guidance | §6 |

---

## 3. Personas & primary use cases

### 3.1 Personas
- **P1 — Household planner (primary).** Cooks for a family of 2–6 with mixed ages, preferences and conditions (the seed profile: a couple, lacto-vegetarian, Bihari/Eastern-India cuisine, managing common conditions like diabetes and hypertension). Wants a weekly plan + auto grocery list.
- **P2 — Health-condition manager.** Has diabetes/hypertension/CKD/pregnancy and needs plans that respect targets without reading clinical PDFs.
- **P3 — Life-stage caregiver.** Parent/child-of-elderly needing correct complementary-feeding (6–24 mo), child/adolescent, or elderly (sarcopenia/bone) plans.
- **P4 — Self-optimizer.** Wants muscle-gain/weight-loss/maintenance with variety and macro adherence.
- **P5 — Deployer/contributor (technical).** Self-hosts Rituva, adds a new region's seasonal calendar and cuisine pack, points it at a local LLM.

### 3.2 Top user stories (v1)
1. As P1, I enter my household's profiles once and get **today's** breakfast/lunch/dinner/2 snacks with portions and a reason for each.
2. As P1, I generate **this week** (7 unique days) and a **consolidated grocery list** scaled to household size.
3. As P1, I generate a **month** and a **full year (366 days)** with no repeated menus.
4. As P2 (diabetic), every plan keeps added sugar and high-GI foods within guideline limits and flags carbohydrate per meal.
5. As P3, I pick "infant 9–12 months" and get guideline-correct complementary-feeding menus and quantities.
6. As P4, I set goal = muscle gain and get protein-target-hitting plans with veg-friendly protein pairing (cereal:pulse 3:1).
7. As any user, I can **swap** any dish and the plan re-balances and updates the grocery list.
8. As any user, I can see **why** a dish was chosen (which guideline/target) and **export to Excel/PDF**.
9. As P5, I switch the LLM from a cloud API to a local Ollama model in config and everything still works offline.
10. As P1, I select **multiple regional cuisines** (e.g., South + East Indian) and the plans blend both authentically while still hitting my targets.
11. As P2, I enter my **doctor-prescribed diet** (e.g., "renal, 1500 kcal, low-potassium") and my **lab values** (HbA1c, eGFR, TSH…); the app makes the prescription authoritative, refines targets from my measurements, and flags anything that diverges from the general guideline — never inventing a number.
12. As any user, I use the same account on the **Android app and the website** and see an identical, beautifully-designed plan on both.

---

## 4. Scope & phased delivery (summary; full roadmap §13)

- **MVP (Phase 1):** Single/household profiles; India (ICMR-NIN) guideline profile; deterministic planner + one LLM adapter; day/week generation; seasonal India calendar; grocery list; Excel/PDF export; core conditions (diabetes, hypertension, weight goals, vegetarian). Local-first.
- **Phase 2:** Month/year (366-day) generation with full uniqueness engine; life-stage modes (pregnancy, lactation, infant/child/adolescent, elderly); more conditions (CKD advisory, dyslipidemia, thyroid, PCOS, fertility, liver, TB); diet-quality score; cost/affordability mode.
- **Phase 3:** Multi-region/multi-country guideline packs (DGA/WHO profiles), cuisine packs, contributor tooling, recipe-DB community sharing, optional integrations (wearables, grocery APIs).

---

## 5. Profile & preference model (system inputs)

Mirrors and extends the Excel **Profile** sheet. A **Household** contains one or more **Members**; plans can be per-member or household-blended (with per-member portioning).

### 5.1 Member attributes
- **Identity/anthropometry:** name, age (or DOB), sex, weight (kg), height (cm). Derived: BMI, BMI category (Asian & WHO cut-offs, §7.2).
- **Activity level:** PAL 1.2–1.9 (sedentary→heavy) mapped to DGI activity bands (sedentary/moderate/heavy). (S1 p.54)
- **Goal:** Lose / Maintain / Gain / Muscle (drives energy adjustment & protein g/kg, §7.3).
- **Diet type:** Omnivore / Lacto-vegetarian / Lacto-ovo / Ovo / Vegan / Pescatarian / Jain / Halal / Kosher / custom. Drives protein sourcing and nutrient-risk watchlists (S3 p.9 veg/vegan risk nutrients).
- **Life stage (auto from age/sex + flags):** infant 0–6 mo / 6–12 mo / child 1–3 / 4–6 / 7–9 / 10–12 / adolescent 13–15 / 16–18 / adult / pregnant (trimester) / lactating (0–6 / 7–12 mo) / elderly 60+. Each maps to a food-group quantity row (S1 Table 1.6, §7.3).
- **Health conditions (multi-select):** diabetes/pre-diabetes, hypertension, CHD/dyslipidemia, CKD (+stage, advisory), thyroid, PCOS/irregular cycles, acidity/GERD, fertility/pre-conception, anemia, liver (history), gout, food allergies/intolerances (lactose, gluten, nut), bariatric, etc. (§6)
- **Family/genetic history (context, soft-weighting):** e.g., parental diabetes/BP/heart/bone — nudges preventive constraints (low-GI, low-salt, calcium+Vit D), never a hard rule.
- **Micronutrient focus flags:** derived from conditions (e.g., fertility → folate/zinc; thyroid → iodine/selenium; hair-fall → zinc/protein; pregnancy → iron/folate/iodine/B12).
- **Clinical & lab measurements (optional, user-entered):** blood pressure; fasting & post-prandial glucose; HbA1c; total/LDL/HDL cholesterol & triglycerides; TSH; hemoglobin/CBC; serum creatinine/eGFR; uric acid; ferritin; vitamin D; vitamin B12; waist circumference. Values are **user-supplied facts** (not invented). They (a) auto-suggest conditions against cited cutoffs (e.g., BP ≥140/90 → hypertension, S2 p.33; HbA1c bands, S1 Table I), (b) refine severity of condition rules, and (c) populate a trend view. The app never fabricates a lab value or a clinical threshold — thresholds come only from the cited sources.
- **Known daily requirements (optional, user/dietitian-provided):** if the user already knows their targets (kcal, protein, sodium, etc.), they may enter them. These **override** the guideline-computed targets (precedence in §6.5). If unknown, the app computes them from the guidelines (§7.2–7.3) — this is the default path.
- **Doctor-prescribed diet (optional, authoritative):** a structured entry — diet name/type (e.g., DASH, renal, diabetic 1500 kcal, low-FODMAP), target energy/macros, explicit allowed/avoid lists, fluid/sodium/potassium/protein limits, start & review dates — or an uploaded prescription (photo/PDF) whose contents the LLM **extracts to structured fields and shows back for the user to confirm** (never auto-trusted, never numerically embellished). Once confirmed it becomes a **HARD, source-attributed ("your doctor") constraint set** (§6.5).
- **Regional diet preference (N/S/E/W, single or multiple):** the user picks one or more Indian regional cuisines — **North, South, East, West** — optionally weighted (e.g., 60% South / 40% East). Drives the active **Cuisine Pack(s)** used in generation (§7.6). Fully extensible to other countries/regions later.

### 5.2 Preference model (encoded as generation constraints)
- **Regional cuisine bias (N/S/E/W Indian, multi-select & blendable):** one or more of **North** (roti/paratha, rajma/chole, paneer, mustard/ghee, tandoor), **South** (rice, idli/dosa/uttapam, sambar/rasam, coconut, curry leaves, gingelly oil), **East** (rice, fish where non-veg, sattu, litti-chokha, dalma, ghugni, mustard oil, panch-phoron), **West** (bajra/jowar, dhokla/thepla, dal-baati, kokum, groundnut oil, varied veg). Multiple selections blend authentically with optional weights; a legacy free-form "cuisine bias" (e.g., "Eastern India — Bihari") is still supported as a sub-style within its region. Featured signature dishes per region are catalogued in the Cuisine Pack (§7.6).
- **Featured foods** (favor), **Reduced** (down-weight), **Avoid-occasional** (cap to N times/year), **Excluded** (hard-remove).
- **Meal structure:** meals/day (default 3 meals + 2 snacks, per Excel; DGI notes 2–3 meals/day acceptable, S1 p.2), meal timing windows, cheat-meal slot policy.
- **Kitchen constraints:** cooking time budget, equipment, batch-cooking preference.
- **Budget:** optional cost ceiling (drives cost-aware selection, §7.7, S6).
- **Portion basis:** persons to cook for, leftover policy, grocery scaling factor.

### 5.3 Input methods
Form-based onboarding (like the Excel yellow cells), an optional conversational intake (LLM parses free text into the structured profile — then **shown back for confirmation**, never acted on silently), and `.xlsx`/JSON import from an existing Eastern Diet Planner workbook.

---

## 6. Condition-aware, life-stage & age-related-ailment engine

This is the clinical-nutrition heart of the product and directly answers the requirement to be *"thoughtful about age-related ailments and food helping in overall growth and lifestyle management."* Rules are stored as source-cited `ConditionRule` records (data, not code) and compiled into hard/soft constraints for the planner (§9).

### 6.1 Rule representation
```
ConditionRule {
  id, condition, applies_to (life_stage/sex/age range),
  constraint_type: HARD | SOFT | TARGET | PREFERENCE | FLAG,
  target: { nutrient|food_group|food_tag|GI|GL, operator, value, unit, per: day|meal|kg_bw|week },
  rationale, source_ref (doc,page), severity, clinician_review: bool
}
```

### 6.2 Life-stage food-group quantities (growth & aging)
The master table (S1 Table 1.6 / Annexure V) drives per-life-stage food-group grams. Encoded verbatim (raw g/day; see §14.1 for the full transcription), e.g.:
- **Infant 7–12 mo (8.5 kg):** cereals 25 g, pulses 12 g, GLV 20 g, veg 25 g, roots 20 g, fruit 40–60 g, nuts 7 g, fat 10 g + breast milk ~580 ml. Complementary-feeding energy **650–720 kcal/day, protein 9–10.5 g** (S1 p.27). Introduce egg/fish/meat from **8 months**; **MDD ≥5 food groups**; meal frequency by age (S1 p.27–28). **No added sugar < 2 years** (S1 p.146).
- **Child 4–6 y:** ~1370 kcal, 46 g protein; **7–9 y:** ~1710 kcal, 59 g. Calcium RDA **850–1050 mg/day** for peak bone mass (S1 p.38).
- **Adult sedentary man 65 kg:** ~2080 kcal, 72 g protein; **sedentary woman 55 kg:** ~1660 kcal, 57 g (S1 Table 1.6, p.11).
- **Pregnancy:** +350 kcal (2nd–3rd trimester), +8 g protein (2nd tri) / +18 g (3rd tri); weight gain 10–12 kg at normal BMI; IFA **60 mg iron + 0.5 mg folic acid** from wk 12 (S1 p.13–19). Focus: iron, folate, iodine, B12, LC n-3 (S3 p.8; S1 p.13).
- **Lactation:** +600 kcal/+13.6 g protein (0–6 mo); +520 kcal/+10.6 g (7–12 mo) (S1 p.15).
- **Elderly 60+ (age-related ailments):** man ~1740 kcal/62 g, woman ~1530 kcal/56 g; fewer calories but **higher micronutrient density**; **≥⅓ cereals whole-grain**, 200–400 ml low-fat milk, 400–500 g veg+fruit, a fistful of nuts, ~2 L water; soft, less-salt preparations. Targets sarcopenia (protein quality + resistance activity), osteoporosis (calcium+Vit D+weight-bearing), and reduces dementia/Parkinson's/CVD risk (S1 Guideline 16, p.117–122).

### 6.3 Condition constraint packs (examples; full set §14.4)
Compiled from S2 (Sri Lanka nutrition therapy) cross-checked with S1/S3/S4:
- **Diabetes / pre-diabetes:** carbohydrate 50–60 %E (as low as 33% if overweight); **45–60 g carb/meal**; prefer **GI < 55**; 3 meals + 2 snacks, don't skip; saturated fat < 7 %E; sodium < 1550 mg if CVD risk; fruit only GI ≤ 55 (S2 p.3–14). App action: hard-cap added sugar, prefer low-GI staples (millets, parboiled/brown rice, whole-wheat, legumes), surface carb-per-meal.
- **Hypertension:** DASH pattern; **sodium < 2300 mg (ideal < 1500 mg)**; fruit+veg 4–5 servings each (~400 g each); total fat ~20–27 %E, sat ≤ 7 %E; K/Ca/Mg-rich foods (S2 p.27–33; S4 p.5). App: low-salt recipe variants, potassium-rich sides, DASH serving targets.
- **CHD / dyslipidemia:** total fat 25–35 %E, **sat < 7 %E, trans < 1 %E, dietary cholesterol < 200 mg**; soluble fibre 5–10 g/day; oily fish ≥ 2×/week; plant stanols/sterols (S2 p.15–25, 45–50). 
- **CKD (advisory, clinician-gated):** energy 30–35 kcal/kg; **protein 0.6–0.8 g/kg pre-dialysis**, 1.2 g/kg on dialysis; **potassium & phosphate food-list filtering** (low-K < 125 mg/serv lists), sodium 1–3 g; fluid = urine + 500 ml (S2 p.51–73). App: shows renal-safe food lists, **hard-blocks** high-K/PO₄ items in renal mode, always with "confirm with your renal dietitian."
- **Thyroid:** iodized salt, adequate iodine 150 µg, selenium (Brazil nut rotation); moderate goitrogen handling (S7 Health_Alerts; S1 iodine).
- **Acidity/GERD:** 4–5 small meals, don't skip breakfast, last meal ≥3 h before bed, limit fried/very-spicy (S7).
- **Fertility/pre-conception (both sexes):** start folate ≥400 µg 3 months prior, iron stores, zinc (pumpkin/sesame), selenium; whole-diet quality (S1 p.13; S7).
- **Weight management:** deficit **500–750 kcal/day**, floor **≥1000 kcal/day**, safe loss **0.5 kg/week**, protein ≥15 %E (up to 1.6 g/kg for muscle; **>1.6 g/kg gives no extra muscle gain**, S1 p.60, p.81–83).
- **Age-related ailment cross-map** (preventive, from family history): osteoporosis→Ca+VitD; CVD/BP→salt/sat-fat down, whole grains up; type-2 diabetes→low-GI (up to 80% preventable by diet+activity, S1 p.15).

### 6.4 Conflict resolution
When multiple conditions/life-stages produce overlapping constraints, the compiler takes the **most restrictive HARD bound**, unions FLAGs, and averages TARGETs only within the same source family; irreconcilable conflicts (e.g., pregnancy high-iron vs CKD protein limits) raise a **clinician-review flag** rather than auto-resolving.

### 6.5 Target precedence & the doctor-prescribed diet (authoritative inputs)
The system resolves a member's effective targets/constraints by a strict **precedence order**, so individualized medical advice always wins over the general guideline — and so that "user-provided facts" are never confused with "invented numbers":

1. **Doctor-prescribed diet** (highest) — HARD constraints attributed to *"your doctor."* When a prescription conflicts with a guideline default (e.g., doctor sets 1500 kcal renal diet with potassium limit vs. DGI My Plate defaults), **the prescription governs** and the divergence is shown plainly ("Your doctor's plan differs from the general DGI guideline here — following your doctor.").
2. **User/dietitian-known targets** — explicit kcal/macro/micro numbers the user entered; override computed values.
3. **Condition & life-stage rules** — the cited `ConditionRule` packs (§6.2–6.3).
4. **Guideline-computed targets** (lowest/default) — TargetEngine from DGI/WHO (§7.2–7.3), used whenever the higher tiers are absent.

**Anti-invention safeguards for this feature:**
- A prescription **uploaded** as image/PDF is parsed by the LLM into structured fields and **shown back to the user for confirmation**; unparseable or ambiguous values are left blank for the user to fill — never guessed.
- The app **stores what the doctor/user provided verbatim** (with a `source: "doctor_prescription" | "user_provided"` tag) and **computes nothing new on top of it**; it does not "round," "optimize," or extrapolate prescribed numbers.
- Safety floor: if a prescription appears unsafe against a cited hard limit (e.g., energy below the DGI ≥1000 kcal/day floor, S1 p.64), the app still honors the prescription but **surfaces a non-blocking caution with the citation** and suggests confirming with the prescriber — it does not silently alter the doctor's number.
- Every menu generated under a prescription carries the prescription in its `Provenance` (§9.5) so the plan is fully auditable.

---

## 7. Nutrition knowledge base & the deterministic core

The knowledge base (KB) is the single source of truth for all numbers. It is versioned, source-cited, and independently testable. The LLM reads from it; it never overwrites it.

### 7.1 Food groups (S1 Table 1.1 — 10 groups)
Cereals & millets · Pulses · Vegetables · Nuts/oilseeds/oils & fats · Green leafy vegetables · Fruits · Dairy · Roots & tubers · Flesh foods (fish/poultry/egg/lean meat) · Spices & herbs. A balanced day draws from **≥5–7 of 10 groups daily**, others **≥2–3×/week** (S1 p.5); "half the plate" = vegetables + fruits + GLV + roots/tubers (S1 p.16).

### 7.2 Anthropometry & energy
- **BMI = weight(kg) / height(m)².** Categories — **Asian:** normal 18.5–23, overweight 23–27.5, obese > 27.5; **WHO:** 18.5–25 / 25–30 / >30 (S1 p.62–64; S5 p.126). Store both; default to Asian for India profile.
- **BMR:** Mifflin–St Jeor (default; used by the Excel) with Henry/Oxford & ICMR-adjusted as selectable alternatives; Harris–Benedict retained for clinical parity (S2 Annex 9).
  - Men: 10W + 6.25H − 5A + 5; Women: 10W + 6.25H − 5A − 161.
- **TDEE = BMR × PAL.** **Target kcal = TDEE + goal adjustment** (gain +300…+500; muscle per protein need; loss −500…−750 with ≥1000 floor).

### 7.3 Macronutrient & fibre targets (per member/day)
- **Energy split:** carbohydrate 50–55 %E, protein 10–15 %E, fat 20–30 %E (S1 p.5). Cereals/millets ≤45 %E; pulses+flesh ~14 %E (S1 p.16).
- **Protein:** RDA **0.83 g/kg** (EAR 0.66) baseline (S1 p.58); goal-adjusted up to **1.2–1.6 g/kg** for muscle/older adults (S3 p.2; S1 p.60). Quality via **cereal:pulse 3:1** + 250 ml milk (S1 p.58).
- **Fat:** total ≤ 30 %E; **visible cooking oil 20–50 g/day by activity** (sedentary ♀20/♂30, moderate ♀30/♂40, heavy ♂50) (S1 p.54); saturated < 10 %E (WHO S4) / < 5 %E visible SFA (S1); **trans < 1 %E** (S4); EFA minimums n-6 ≥3 %E (~6.6 g), n-3 0.6–1.2 %E (~2.2 g) (S1 p.54).
- **Free/added sugar:** < 10 %E, ideally **< 5 %E ≈ ≤ 25 g/day** (S4; S1 p.111). No added sugar < 2 y (S1 p.146).
- **Salt:** **< 5 g/day (≈ 2 g/2300 mg sodium)** (S1 p.91; S4 p.5; WHO S4).
- **Fibre:** ~**25 g per 1000 kcal** (S1 p.17); DASH ~30 g (S2 p.30).
- **Water:** ~**2 L/day incl. beverages** (S1 p.106); Excel formula derives L/day from weight/activity.
- **Micronutrient RDAs (ICMR-NIN 2020):** iron, calcium (1000 mg adult; 850–1050 mg adolescent), B12 (2.2 µg), folate, Vit D (600 IU), zinc, magnesium, iodine (150 µg), Vit A/C, etc. Stored per life-stage/sex with veg-bioavailability notes (S7 Targets; S1 Tables 1.4–1.5).

### 7.4 Food composition database (`FoodComposition`)
- Per-100 g values: kcal, protein, carbohydrate, fat, fibre, iron, calcium, B12, + extensible (Zn, Mg, folate, Vit A/C/D, Na, K, PO₄, GI/GL). **Every row carries a `source` field** (IFCT 2017 primary, USDA FDC fallback) (S7 FoodDB; S1 Tables 1.3–1.5).
- Seed from the Excel FoodDB (75–79 items) + IFCT 2017 full tables; extensible per region.
- Group-average macro/micronutrient rows (S1 Tables 1.3–1.5) support estimation when a specific item is absent (flagged as estimate, never presented as exact).

### 7.5 Recipes & the ingredient BOM (`Recipe`, `RecipeIngredient`)
- **Recipe** = a named dish with: meal-slot eligibility (breakfast/lunch/dinner/snack), cuisine/region tags, season tags, diet-type flags, condition flags (e.g., `low_gi`, `renal_safe`, `high_protein`), cooking method, time, cost tier, and a **component list**.
- **RecipeIngredient** = component → grocery item, **QtyPerPerson, unit, category** (exactly the Excel `Ingredients` sheet BOM, e.g., "Matar paneer → Paneer 50 g + Green peas 60 g"). This BOM is what makes deterministic nutrient totals and grocery aggregation possible.
- **Nutrient totals per recipe are computed** by summing `RecipeIngredient × FoodComposition` — **never taken from an LLM**. This is the anti-hallucination linchpin (§9.2).

### 7.6 Seasonality & region model (`Region`, `SeasonCalendar`, `SeasonalAvailability`)
- **Region** → agro-climatic zone → **season calendar**. The Excel uses 4 seasons (Winter/Spring/Summer/Monsoon) mapped week→season; Rituva generalizes to a **month × region → in-season produce** table.
- `SeasonalAvailability(region, month, food_item, availability_score)` seeded from published seasonal-produce calendars (India first; per-country extensible). DGI explicitly directs "fresh, locally available, **preferably seasonal**" vegetables/fruits (S1 p.49).
- The planner **prefers** in-season produce (soft constraint, target ≥80% in-season, G2) and season-gates certain dishes (e.g., "sarson saag — winter only," "sattu drink — summer," "eat well-cooked, avoid raw salads — monsoon," per Excel Notes).
- Staples/pulses/cuisine come from a **Cuisine Pack** (region → signature dishes, preferred grains, oils, spice profiles).

**Regional Cuisine Packs (North / South / East / West India) & blending.** Each pack is data (`cuisine_pack`) defining preferred grains, pulses, oils, spice/tempering profile, signature dishes per meal slot, and typical cooking methods. Users may select **one or several** packs, optionally weighted; the candidate retriever (§9.1 stage 3) then draws dishes proportionally and the optimizer keeps daily balance. Representative pack contents (extensible, seeded then community-grown):
| Region | Grains/staples | Signature dishes (by slot) | Oils/fats & tempering |
|---|---|---|---|
| **North** | wheat (roti/paratha/phulka), basmati rice | breakfast: paratha, chana-based, poha; lunch/dinner: dal, rajma, chole, paneer sabzi, saag; | ghee, mustard/soybean oil; jeera/garam masala; tandoor/tawa |
| **South** | rice, idli/dosa batter, millets (ragi) | breakfast: idli, dosa, uttapam, upma, pongal; lunch/dinner: sambar, rasam, poriyal, kootu, curd rice; | gingelly/coconut oil; mustard-curry-leaf tempering; steaming |
| **East** | rice, sattu, poha (chura) | breakfast: dahi-chura, sattu paratha, ghugni; lunch/dinner: dalma, litti-chokha, machha jhol (non-veg), shukto, panch-phoron dals; | mustard oil; panch-phoron; light stews |
| **West** | bajra/jowar, wheat, rice | breakfast: thepla, dhokla, poha, thalipeeth; lunch/dinner: dal-baati, undhiyu, usal, kadhi, bhaji; | groundnut oil, ghee; kokum/tamarind; roasting |
Multi-select example: "South + East" yields days that mix (e.g.) a dosa breakfast with a dalma-and-rice lunch, all still meeting My Plate group targets and uniqueness rules. Blending never overrides nutrition constraints — region shapes *which* compliant dish is chosen, not *whether* the day is balanced.

### 7.7 Diet-quality & cost scoring (evaluation, not just generation)
- **Diet-Quality Score (DQS)** implementing the GNR 2026 four dimensions (S5 p.120): **variety/diversity** (food-group & item counts; MDD-W ≥5/10, MDD-C ≥5/8 from S6), **adequacy** (targets met), **moderation** (added sugar/salt/sat-fat/UPF within limits), **balance** (macro distribution in range). Scored per day/week and shown to the user.
- **HFSS/UPF gate** (S1 Table 15.1/15.2): per-100 g thresholds (solids >250 kcal, salt >625 mg, added sugar >3 g, added fat >4.2 g) and Group A/B/C processing classification; UPFs (Group C) hard-capped; nuts/seeds exempt from HFSS despite density.
- **Cost/affordability mode** (S6): least-cost selection within nutritional constraints using regional prices; optional budget ceiling; Healthy Diet Basket (6 groups/11 items @2330 kcal) as an affordability reference.

### 7.8 System context detection (date · time · season · current meal)
Rituva reads the **device's own clock** (mobile or desktop) so the user never has to set a date — it just knows what day, season and meal it is:
- **Date** → the plan auto-advances; "Today" always shows the correct day and the year-plan lands on the right date.
- **Time of day** → highlights the current/next meal slot (breakfast → snack → lunch → snack → dinner) and the greeting.
- **Month → season** (via the region's calendar, §7.6) → drives seasonal produce selection.
- **Locale/timezone** from the device; the user can still override the date or region to plan ahead.
Implemented in `context.detect()` (returns date, time, season, current meal, greeting), surfaced at `GET /context` and in the CLI header, and consumed by the planner (which keys each day's season off its date). See §18.

---

## 8. The uniqueness engine (the "366 unique days" requirement)

The requirement — *"no repetition of food items in a week or month or year… all unique 366 days a year"* — is the product's signature feature. It must be implemented **honestly**: a literal reading (zero food-item ever repeats) is mathematically and nutritionally impossible, because the guidelines **mandate** that certain food groups appear **every single day** (S1 My Plate: cereals + pulses + milk/curd + vegetables + fruit daily; S1 p.5). You cannot supply 366 distinct cereals or 366 distinct pulses, and forcing that would *violate* the very guidelines the product exists to honor. Rituva therefore implements a **tiered uniqueness model** that delivers a genuinely different eating experience every day of the year while keeping each day nutritionally complete.

### 8.1 The three tiers
- **Tier 0 — Staple base (bounded recurrence, by design).** Food *groups* that DGI requires daily — cereal, pulse, dairy, oil, nuts/seeds, salt. These recur because they must. Uniqueness here is expressed as **rotation of form and species**: the cereal rotates across the whole grain/millet set (rice → whole-wheat roti → bajra → ragi → jowar → foxtail → oats → maize…) and its *preparation* rotates (plain rice → jeera rice → lemon rice → curd rice → pulao…), and DGI's own rule that **20–30% of cereals be millets** (S1 p.129) is used to force grain diversity. A **minimum-gap constraint** governs Tier 0: the *same grain in the same form* may not recur within *G₀* days (default 3–4).
- **Tier 1 — Composed dishes (strict non-repetition).** The named dish/recipe (e.g., "Chana ghugni," "Palak paneer," "Bisi bele bhath"). **No composed dish repeats within the uniqueness window** *W* (default: the whole planning horizon — so across a 366-day plan, all daily dish-sets are distinct, and no individual dish repeats within a configurable rolling window, default 21–30 days). This is exactly what the Eastern Diet Planner already achieves at 52-week granularity ("all 52 weeks unique") — Rituva generalizes it to 366 days.
- **Tier 2 — Hero ingredient of the day (rotated).** The "feature" vegetable/legume/protein differs day-to-day, drawn from the **in-season** set for the user's region, so the *sensory identity* of each day is distinct even when Tier 0 staples recur.

### 8.2 Uniqueness is a policy, not a constant
The scope is a user/deployer setting so the product can satisfy either interpretation:
- `UNIQUENESS_SCOPE ∈ {day, week, month, year}` — the window over which **full-day menus** must be distinct (default `year`).
- `DISH_MIN_GAP_DAYS` — min days before any composed dish may reappear (default 21; set to 366 for "never repeats in a year").
- `INGREDIENT_MIN_GAP_DAYS` per food-group tier (staples exempt or gapped small; hero vegetables gapped large).
- `STAPLE_RECURRENCE_FLOOR` — explicitly documents that Tier-0 groups recur daily by nutritional necessity (surfaced in the UI so the user understands *why* rice appears often — no silent behavior).

### 8.3 Feasibility math (why this is achievable and where the limits are)
- **Menu-level uniqueness (366 distinct days): trivially feasible.** A day = (breakfast, lunch, dinner, snack1, snack2). With even 40 breakfasts × 60 lunches × 60 dinners × 30 × 30 the combinatorial space is > 10⁹ — 366 distinct daily *combinations* is easy.
- **Dish-level non-repetition across a year: feasible with an adequate library.** 366 days × 5 slots = 1,830 dish instances. With per-slot pools of ≥ ~120 breakfasts, ~200 lunch mains, ~200 dinner mains, ~80 snacks (achievable by combining a seed recipe DB with LLM-assisted, validated variation — §9), no dish need repeat within a year. The planner **logs and surfaces** the realized repeat-gap so any shortfall is visible, never hidden (anti-"silent cap" principle).
- **Ingredient-level non-repetition: intentionally NOT promised for staples.** The UI states plainly: "Staples (rice, wheat/millets, pulses, curd, oil) recur because your dietary guidelines require them daily; their form and the featured vegetables/pulses change every day." This is the honest, guideline-faithful treatment the brief demands ("no hallucinations, no invention").

### 8.4 Enforcement mechanism
A `RotationHistory(member/household, date, slot, recipe_id, hero_ingredient, grain, grain_form)` ledger is the source of truth. During generation the candidate filter excludes any recipe/ingredient that would violate its tier's min-gap given the ledger. Because the planner is **deterministic** (§9), uniqueness is a **hard constraint** in the solver, not a hope — a plan that cannot satisfy it fails loudly (and the UI suggests widening the library or relaxing a gap), rather than silently repeating.

### 8.5 Frequency regulation & interchangeability (category quotas)
Non-repetition (§8.1–8.4) governs whole dishes and menus; **frequency regulation** governs how often an *ingredient, food-category or cuisine* may recur — so no single item dominates the week/month even when it never technically "repeats" as a dish. This directly answers *"no mushroom 3×/week, no paneer 4×/week, not 3 South-Indian days"* — it must be regulated and interchangeable.

- **`FrequencyPolicy` (data, user-adjustable defaults):** per-ingredient, per-category and per-cuisine ceilings over rolling windows. Illustrative defaults (all editable):
  | Scope | Default cap |
  |---|---|
  | Mushroom (ingredient) | ≤ 2 / week |
  | Paneer (ingredient) | ≤ 3 / week |
  | Soya / tofu (ingredient) | ≤ 2 / week |
  | Any single vegetable | ≤ 2–3 / week |
  | Any one pulse/dal | ≤ 2 / week (force dal variety) |
  | Deep-fried / cheat slot | ≤ 1 / week |
  | Any one region (N/S/E/W) | ≤ 3 days / week (unless a single region is chosen) |
- **Interchangeability via equivalence classes.** Items are grouped into swappable classes — *veg-protein anchors* {paneer, tofu, soya chunks, chana, rajma, lobia}, *leafy greens* {spinach, methi, sarson…}, *millets* {bajra, jowar, ragi, foxtail}, etc. When a cap is hit, the planner draws the day's requirement from a **different member of the same class**, preserving the nutrient target while forcing variety.
- **Enforcement.** Caps compile to HARD constraints in the optimizer (§9.3) and are tracked in `RotationHistory` (extended with rolling `ingredient` / `category` / `cuisine` counters). Enforcement is deterministic — "mushroom already used twice this week" *blocks* a third automatically, not reliant on the LLM to remember.
- **Transparency.** The Swap screen (§17.4) shows live counters ("Mushroom 2/2 · cap reached", "South-Indian days 2/3"), so the regulation is visible, not a black box.

---

## 9. Menu generation pipeline (constraint-first, LLM-second) & anti-hallucination

This section answers two core requirements simultaneously: **(a)** "can use any LLM (paid or open source) for menu generation," and **(b)** "no hallucinations, AI slop, non-factual inventions." The design principle is **the LLM proposes, the deterministic engine disposes.** Nutrition math, targets, limits, seasonality and uniqueness are enforced by code against the KB; the LLM is confined to bounded, verifiable creative tasks.

### 9.1 Pipeline stages
```
Profile+Prefs+Region+Date-range
      │
      ▼
[1] Target Computation (deterministic) ── energy/macros/micros/limits per member/day  (§7.2–7.3)
      │
      ▼
[2] Constraint Compilation (deterministic) ── hard/soft constraints from conditions, life-stage,
      │                                        allergens, exclusions, HFSS gates, uniqueness ledger
      ▼
[3] Candidate Retrieval (deterministic) ── filter Recipe DB by: meal-slot, diet-type, season(region,month),
      │                                     condition flags, exclusions, min-gap uniqueness → candidate pools
      ▼
[4] Menu Assembly (deterministic optimizer, LLM-optional) ── select dishes per slot to hit targets
      │        │                                              within tolerance & satisfy all HARD constraints
      │        └── (optional) LLM ranks/varies WITHIN the allowed candidate set, or drafts NEW recipes → [4a]
      ▼
[4a] New-recipe validation (deterministic) ── decompose LLM recipe into KB ingredients; unknown item ⇒ REJECT/flag;
      │                                        compute nutrients from FoodComposition; must pass HFSS + targets
      ▼
[5] Nutrient Verification (deterministic) ── recompute totals from BOM×FoodComposition; assert within tolerance
      │                                        & zero HARD violations; else repair (swap/regenerate, bounded retries)
      ▼
[6] Explanation & Grocery (LLM-optional text, deterministic numbers) ── rationale per dish w/ citations; BOM→grocery
      ▼
Validated DayPlan/WeekPlan/…  (+ DQS score §7.7, + provenance §9.5)
```

### 9.2 The anti-hallucination contract (hard rules)
1. **Numbers never come from the LLM.** Every kcal/protein/sodium/GI value is computed by the engine from `FoodComposition` (IFCT 2017 / USDA), which carries a `source`. If the LLM emits a number, it is discarded and recomputed.
2. **Closed ingredient vocabulary.** Any recipe (seed or LLM-generated) is decomposed into KB `FoodItem`s. An ingredient not resolvable to the KB is **flagged and rejected**, never fabricated or assigned invented nutrients. (Optionally, the deployer can allow "propose new FoodItem with source URL" into a review queue — human-gated, never auto-trusted.)
3. **Schema-constrained decoding.** The LLM must return **structured JSON** conforming to a strict schema (via JSON-mode/function-calling for APIs, or GBNF/grammar-constrained decoding for llama.cpp/vLLM). Free-form prose menus are not accepted.
4. **Every rule is cited.** Constraints and targets carry `source_ref (doc,page)` from the KB; the UI can show "sodium capped at 5 g/day — DGI 2024, Guideline 11, p.91."
5. **Deterministic validation gate.** No plan reaches the user until stage [5] passes: targets within tolerance, zero HARD-constraint violations, uniqueness satisfied. Failures trigger bounded repair, then a **deterministic fallback planner** (no LLM) that is guaranteed to produce a valid plan from the seed DB.
6. **No medical/therapeutic invention.** Condition rules come only from the cited sources (S1–S4); the engine never "reasons up" a new clinical limit. Therapeutic modes carry the clinician-review flag (§6.4, §13.2).
7. **Provenance object attached to every plan** (§9.5) — makes the whole plan auditable and reproducible.

### 9.3 The deterministic optimizer (stage 4)
Two interchangeable implementations behind one interface:
- **MVP — greedy + backtracking scheduler.** Per slot, pick the best-fitting candidate (closest to remaining macro/micro budget, respects gaps, prefers in-season & featured), backtrack on infeasibility. Fast, transparent, no heavy deps.
- **Advanced — constraint/ILP solver (OR-Tools CP-SAT or PuLP/CBC).** Model: decision vars = recipe selection per slot per day; objective = minimize deviation from targets (+ cost, + seasonality bonus, − monotony penalty); hard constraints = energy band, protein floor, sodium/sugar/sat-fat ceilings, allergen/exclusion = 0, HFSS gate, food-group daily minimums (≥5 of 10 groups, S1), uniqueness min-gaps. Produces provably-constraint-satisfying week/month blocks.
- **Tolerances (defaults, configurable):** energy ±7%, protein ≥100% of target (no upper cap unless renal), fat 20–30 %E, added sugar ≤ limit (hard), sodium ≤ limit (hard), fibre ≥90% of target.

### 9.4 Validator (stage 5) — always deterministic
Recomputes the full nutrient profile of each day from the BOM, checks every constraint, and emits a machine-readable `ValidationReport { targets_met[], hard_violations[], soft_warnings[], dqs_score, in_season_pct }`. The **automated test suite** (§13.4) runs this validator over generated fixtures to guarantee G1/G6.

### 9.5 Provenance & reproducibility
Each plan stores a `Provenance { kb_version, llm_provider, llm_model, prompt_hash, seed, rule_citations[], food_db_sources[], generated_at }`. Given the same KB version, seed and profile, generation is reproducible; swapping the LLM cannot change nutrient numbers (only dish *choice/wording*), which is exactly the guarantee the "no AI slop" requirement needs.

### 9.6 Where the LLM genuinely adds value (bounded)
- **Culturally-appropriate variation & naming** within the allowed candidate set (e.g., turning a slot into a regionally-authentic dish).
- **New candidate recipes** for thin regions/cuisines — always routed through [4a] validation before entering the pool.
- **Natural-language rationale, substitutions, and grocery consolidation text** (numbers still computed by code).
- **Conversational profile intake** parsing (→ structured, shown back for confirmation).
- **Not** used for: computing nutrients, inventing portions, setting medical limits, or asserting seasonality — all deterministic/KB-driven.

### 9.7 Retrieval, orchestration & memory (advanced LLM stack)
Mapping and generation use an advanced but strictly **grounded** LLM stack. None of it changes the anti-hallucination contract (§9.2): retrieval and memory decide *which compliant dish is chosen*; they never supply a nutrient number or a medical limit.

- **Advanced RAG (hybrid, grounded).** Retrieval fuses **dense** semantic search (recipe/rule embeddings in pgvector/FAISS) with **sparse** keyword search (BM25), re-ranked, over two indexes: (a) the **cited guideline rules** KB and (b) the **recipe/food corpus**. A lightweight **Nutrition Knowledge Graph** maps `user targets/conditions/region/season → eligible food classes → recipes → ingredients → FoodComposition → guideline citations`, so every retrieved candidate is provenance-tagged and carries the exact rules that justify it. The generator only sees vetted, in-scope, cited context.
- **LangGraph orchestration.** The pipeline (§9.1) runs as a **stateful LangGraph**: typed nodes (`compute_targets → compile_constraints → retrieve_candidates → assemble/optimize → validate → repair → explain`), conditional edges (bounded repair loop; automatic fall-through to the **deterministic planner** on failure), **checkpointed** state (resumable long year-plan generation), and **human-in-the-loop interrupts** (confirm a scanned prescription, approve a swap). Deterministic nodes never call the LLM; only `retrieve` / `assemble(variation)` / `explain` do, through the §10 adapter.
- **Memory & context.** A per-user **long-term memory store** persists preferences, liked dishes, **declined / never items**, swap history and the rotation + frequency ledgers; the retriever conditions on it so "rejected mushroom twice," "prefers South breakfasts," or "paneer cap reached" carry forward across sessions and devices. **Short-term/working memory** is the current plan state inside the LangGraph run. Memory is per-profile, local-first, and user-inspectable/erasable (§13.1).
- **Deterministic where it counts.** Targets, limits, nutrient totals, uniqueness and frequency caps stay code-enforced; the graph's LLM nodes operate only inside the candidate set the deterministic core permits.

---

## 10. LLM abstraction layer (any paid or open-source model)

### 10.1 Adapter interface
A single provider-agnostic interface isolates all model calls:
```python
class LLMProvider(Protocol):
    def generate(self, messages, *, schema: JSONSchema | None, temperature, max_tokens) -> StructuredResponse: ...
    def embed(self, texts: list[str]) -> list[Vector]: ...          # for recipe/KB retrieval
    @property
    def capabilities(self) -> Caps: ...   # json_mode, function_calling, grammar, context_len, local
```
Implementations (all optional, config-selected):
- **Cloud APIs:** **NVIDIA `build.nvidia.com` / NIM** (OpenAI-compatible catalog of Llama, Qwen, DeepSeek, Nemotron, Mistral… under one key), Anthropic (Claude), OpenAI (GPT), Google (Gemini), Groq, Mistral, etc.
- **Local/open-weights:** **Ollama**, **llama.cpp** (GGUF, GBNF grammar), **vLLM**, **LM Studio**, **text-generation-webui** — for Llama, Qwen, Mistral, Gemma, Phi, etc.
- **Unified option:** ship a **LiteLLM**-backed default adapter so ~100 providers work via one config, plus a native Ollama adapter for zero-dependency local use.
- **No-LLM mode:** the deterministic fallback planner (§9.3) runs the whole product with **no model at all** — important for offline/privacy and as the correctness backstop.

### 10.2 Configuration (example)
```yaml
llm:
  provider: ollama            # anthropic | openai | gemini | ollama | llamacpp | litellm | none
  model: qwen2.5:14b-instruct
  base_url: http://localhost:11434
  temperature: 0.4
  structured_output: grammar  # json_mode | function_calling | grammar
  max_tokens: 2048
embeddings:
  provider: local             # bge-small / nomic-embed via Ollama, or sentence-transformers
```
API keys via env/secret store only; **never** logged; **never** required for local mode.

### 10.3 Structured-output strategy by capability
- `function_calling`/`json_mode` → pass JSON schema, validate response, one bounded retry on schema failure.
- `grammar` (llama.cpp/vLLM) → compile the schema to **GBNF** so even small local models emit valid JSON.
- Neither → constrained prompt + robust parser + retry; if still invalid → deterministic fallback (never ship malformed).

### 10.4 Prompt design (grounded, bounded)
System prompt injects: the compiled constraints, the **candidate list** (the LLM may only choose/vary within it unless in "propose-new" mode), the relevant **cited KB rules** (RAG-retrieved), and the uniqueness ledger summary. The model is instructed that its output is data (structured menu), that it must not invent nutrient numbers, and that unknown ingredients are disallowed. This keeps even a small local model on-rails.

### 10.5 Key-only configuration, model auto-discovery & graceful fallback
Rituva is designed so a non-technical user can **just paste an API key and go** — everything else is automatic.

- **NVIDIA `build.nvidia.com` (NIM) as a first-class provider.** The NVIDIA API Catalog exposes many best-in-class open models (Llama, Qwen, DeepSeek, Nemotron, Mistral, …) through one **OpenAI-compatible** endpoint (`https://integrate.api.nvidia.com/v1`) with a single key. Rituva ships an NVIDIA adapter; the user enters and saves the key on Settings and nothing else is required.
- **Zero-config model setup.** On key save the app **auto-discovers** the models available to that key (provider `/models` listing), classifies them (chat / instruct / reasoning / embedding, context length, speed tier), and **auto-selects sensible defaults** — a *best* model for quality-critical steps (new-recipe drafting, explanations) and a *fast* model for cheap steps — with no model-picking required. Advanced users may override.
- **Graceful fallback chain.** Each capability (generate / embed) is backed by an **ordered fallback list** for the active key. If the primary model is unavailable — 429/rate-limit, 5xx, timeout, decommissioned model, quota exhausted — the gateway **automatically switches to the next available model** for that same key, transparently, and remembers the last-good model to cut latency. If the whole provider is down it falls to another configured provider, and finally to the **no-LLM deterministic planner** (§9.3), so the product never hard-fails.
- **Multi-provider, one abstraction.** The same key-only flow applies to any provider (NVIDIA, OpenAI, Anthropic, Google, Groq, local Ollama). Keys live in the OS secret store / encrypted at rest, are **never logged**, and cloud calls are opt-in with a data-egress notice (§13.1).
- **Health-aware routing.** A lightweight background probe tracks each model's availability/latency; the router prefers healthy, fast models and demotes failing ones for a cool-down window.

---

## 11. Output formats (day / week / month / year) — Excel parity and beyond

### 11.1 Views
- **Today view:** the 5 meal slots with dishes, portions (g + katori/spoon per S1 Annexure I), per-meal & per-day nutrient totals vs target, DQS, and a one-line cited rationale per dish.
- **Week view:** Mon–Sun grid (the Excel `Current_Week` shape), 5 meals/day, notes column (season/condition tips), weekly nutrient roll-up and grocery list.
- **Month view:** 4–5 week blocks, seasonal theme per block, monthly grocery + cost estimate.
- **Year view (366):** all days generated with menu-level uniqueness; calendar navigation; season bands (region calendar).

### 11.2 Canonical plan data (maps 1:1 to the Excel Week_Library)
Internal representation mirrors the workbook's pipe-delimited raw columns so import/export is loss-free:
```
DayPlan { date, member/household, season, slots: {
   breakfast:[components…], lunch:[…], dinner:[…], snack1:[…], snack2:[…] }, notes,
   totals:{kcal,protein,fat,carb,fibre,iron,calcium,…}, dqs, provenance }
```
Example row (Excel-compatible): `Rice|Chana ghugni|Gajar matar|Broccoli|Raita` for a lunch slot — the app parses/produces exactly this format.

### 11.3 Exports
- **`.xlsx`** rebuilding the Eastern Diet Planner workbook (Profile, Targets, Rotation, Week_Library, Ingredients, Groceries_All, FoodDB, Health_Alerts) via `openpyxl` — so the user keeps their familiar artifact.
- **PDF** (print-friendly week/month), **CSV/JSON** (data), **iCal** (optional meal reminders), **Markdown**.

### 11.4 Grocery engine (deterministic)
Aggregates each plan's `RecipeIngredient` BOM × servings × people-count × scaling-factor into a categorized, de-duplicated shopping list (Staples, Dals/Legumes, Vegetables, GLV, Dairy, Nuts/Seeds, Fruits, Spices, Beverages, Other) with quantities and units — exactly the Excel `Groceries_All`/`Grocery_List` behavior, but computed for any horizon (day→year) and any household size. Unmapped components are surfaced as "add to Ingredients" prompts, never silently dropped.

### 11.5 Health-alerts surface
Condition-specific guidance cards (the Excel `Health_Alerts` sheet), now generated from the active `ConditionRule` set with citations and the specific foods the plan uses to meet them (e.g., "Iron 29 mg/day target — today's methi + sesame + jaggery + lemon pairing; DGI 2024").

### 11.6 Iso-nutrient swap, alternatives & per-ingredient nutrient display
Any dish can be declined for a given day/meal — or "not this week" / "never." The app then offers **equivalent alternatives matched on calories and nutrients**, not arbitrary substitutes:

- **Matching.** Alternatives are ranked by nearest-neighbour distance on the nutrient vector (energy + protein/carb/fat/fibre, then key micros), restricted to the **same meal slot**, the diet type, **all active constraints** (conditions, doctor's diet, allergens/exclusions), the **uniqueness** rules (§8.1–8.4) and the **frequency caps** (§8.5). So a declined "Mushroom paneer" (mushroom cap reached) yields e.g. Tofu bhurji / Soya-chunk curry / Rajma — each in a tight calorie band and using a *different* protein anchor.
- **Every option shows its numbers, from the DB.** Each suggestion and each alternative displays a **per-ingredient nutrient breakdown read from the Knowledge DB** — e.g. *Arhar dal 200 g → protein / carbohydrate / fibre in g (or mg)* — computed as `RecipeIngredient × FoodComposition` (IFCT 2017), plus a **delta vs the original** ("−12 kcal · +2 g protein"). **These figures are read from the DB and never generated by the LLM** (§9.2 rule 1); an ingredient absent from the DB is flagged, never assigned invented values.
- **Re-balance on accept.** Choosing an alternative updates that day's totals, the grocery list, the rotation ledger and the frequency counters, then re-validates the day (§9.4).
- **Source of alternatives.** Primary = deterministic nutrient-vector search over the recipe DB; the LLM may *additionally* propose culturally-fitting options, but only after passing new-recipe validation (§9.1 stage 4a), so their nutrients too come from the DB.

---

## 12. Technical architecture

### 12.1 Principles
Open-source only · local-first & offline-capable · privacy by default (health data stays on device/self-host) · deterministic core with pluggable LLM · data (rules, foods, recipes) separated from code and independently versioned/testable.

### 12.2 Component diagram
```
┌──────────────────────────── Frontend (Web / PWA) ─────────────────────────────┐
│  Onboarding · Today/Week/Month/Year · Swap · Grocery · Health Alerts · Export  │
│  React/Next.js (or Streamlit for MVP)  —  offline PWA cache                     │
└───────────────▲───────────────────────────────────────────────────────────────┘
                │ REST/JSON (OpenAPI)
┌───────────────┴──────────────────── Backend (FastAPI, Python) ─────────────────┐
│  API layer  │  Auth (local/JWT, optional)  │  Plan orchestrator (state machine) │
│                                                                                 │
│  Nutrition Core (deterministic, no-LLM):                                        │
│    • TargetEngine (BMR/TDEE/BMI, macro/micro targets)     §7.2–7.3              │
│    • ConstraintCompiler (conditions/life-stage/allergen)  §6, §9.2             │
│    • Planner/Optimizer (greedy+backtrack | OR-Tools)      §9.3                 │
│    • Validator (recompute & assert)                       §9.4                 │
│    • GroceryEngine · DQS · Seasonality · Uniqueness ledger §7.6–7.7, §8         │
│                                                                                 │
│  LLM Gateway (adapter: Anthropic/OpenAI/Gemini/Ollama/llama.cpp/LiteLLM/none)  │
│  RAG/Retrieval (KB rules + recipe embeddings via pgvector/FAISS)               │
└───────────────▲───────────────────────────────────────────────────────────────┘
                │
┌───────────────┴───────────────── Data layer ──────────────────────────────────┐
│  PostgreSQL (+pgvector)  OR  SQLite (single-user/offline)                       │
│  Tables: users, members, targets, food_composition, food_items, recipes,        │
│  recipe_ingredients, regions, season_calendar, seasonal_availability,           │
│  conditions, condition_rules, guideline_rules(KB), plans, day_plans,            │
│  rotation_history, grocery_lists, provenance                                    │
│  Seed data packs: IFCT-2017 foods · India recipe pack · India season calendar   │
│  · guideline-rules pack (DGI/DGA/WHO/SL-therapy, cited) · cuisine packs          │
└────────────────────────────────────────────────────────────────────────────────┘
```

### 12.3 Recommended stack (all OSS)
- **Backend:** Python 3.11+, **FastAPI**, Pydantic v2 (schema validation doubles as LLM structured-output contracts), SQLModel/SQLAlchemy.
- **Optimizer:** Google **OR-Tools** (CP-SAT) with a pure-Python greedy fallback (no native dep for MVP).
- **DB:** **PostgreSQL 16 + pgvector** (server/multi-user); **SQLite** (offline/desktop). Migrations via Alembic.
- **LLM:** LiteLLM + native **Ollama** adapter; **llama.cpp** GBNF for grammar-constrained local output; sentence-transformers/`bge`/`nomic-embed` for embeddings.
- **Orchestration & retrieval:** **LangGraph** (stateful graph, checkpointing, human-in-the-loop interrupts); hybrid RAG = **pgvector/FAISS** (dense) + **BM25** (`rank_bm25` or OpenSearch, sparse) with re-ranking; the **Nutrition Knowledge Graph** stored relationally in Postgres (or `networkx`/`rdflib` for a standalone KG); per-user memory persisted in Postgres/SQLite.
- **LLM gateway:** provider adapters incl. **NVIDIA NIM** (`integrate.api.nvidia.com`, OpenAI-compatible) with **model auto-discovery** and an **availability-aware fallback router**; keys in OS keyring / encrypted at rest.
- **Frontend:** **Next.js/React** + Tailwind (PWA, offline cache) for the full app; **Streamlit** acceptable for MVP/internal.
- **Exports:** **openpyxl** (.xlsx), WeasyPrint/ReportLab (PDF).
- **Packaging/deploy:** **Docker Compose** (api + db + optional ollama); single-binary/desktop option via Tauri or PyInstaller for local-only users.
- **Testing:** pytest, Hypothesis (property-based nutrient/uniqueness tests), schemathesis (API).
- **License:** permissive OSS (Apache-2.0 or MIT) for code; data packs under their respective source terms with citation.

### 12.4 Data model (core tables — abbreviated schema)
```sql
member(id, household_id, name, dob, sex, weight_kg, height_cm, pal, goal, diet_type,
       life_stage, conditions[], preferences_json, created_at)
nutrient_target(id, member_id, date_scope, kcal, protein_g, fat_g, carb_g, fibre_g,
       sodium_mg_max, added_sugar_g_max, satfat_pct_max, micros_json, source_ref)
food_item(id, name, group, region_tags[], diet_flags[], gi, gl, cost_tier)
food_composition(food_item_id, per_100g_kcal, protein_g, carb_g, fat_g, fibre_g,
       iron_mg, calcium_mg, b12_ug, zinc_mg, mg_mg, folate_ug, vitd_iu, na_mg, k_mg,
       source)                              -- e.g. 'IFCT 2017' (NEVER an LLM)
recipe(id, name, slots[], cuisine_tags[], season_tags[], diet_flags[],
       condition_flags[], method, cook_minutes, cost_tier)
recipe_ingredient(recipe_id, food_item_id, qty_per_person, unit, category)   -- the BOM
region(id, name, country, agro_zone)
season_calendar(region_id, month, season)
seasonal_availability(region_id, month, food_item_id, availability_score)
condition(id, name, kind)                   -- disease | life_stage | allergy | goal
condition_rule(id, condition_id, applies_to_json, constraint_type, target_json,
       rationale, source_ref, severity, clinician_review)
guideline_rule(id, topic, statement, value_json, source_doc, source_page, kb_version)
plan(id, household_id, horizon, start_date, end_date, uniqueness_scope, provenance_json)
day_plan(id, plan_id, member_id, date, season, slots_json, totals_json, dqs, notes)
rotation_history(household_id, member_id, date, slot, recipe_id, hero_ingredient,
       grain, grain_form)
grocery_list(plan_id, item, category, quantity, unit, notes)
```

### 12.5 Key APIs (OpenAPI)
```
POST /households, /members                         create/update profiles
GET  /members/{id}/targets                          computed nutrient targets (+citations)
POST /plans        {member|household, horizon, start_date, region, options}  → generate
GET  /plans/{id}/day/{date}                         day view (+validation report, provenance)
POST /plans/{id}/swap {date, slot}                  re-balance a single slot, keep constraints
GET  /plans/{id}/grocery                            aggregated grocery list
GET  /plans/{id}/export?format=xlsx|pdf|json|ics    export
GET  /plans/{id}/validation                         ValidationReport (targets, violations, DQS)
POST /recipes  (contributor)  · GET /regions/{id}/season?month=  · GET /guideline-rules?topic=
```
Every generation response includes the `ValidationReport` and `Provenance` so the client can display "meets targets / cited by" transparently.

---

## 13. Non-functional requirements, roadmap, testing, risks

### 13.1 Non-functional requirements
- **Privacy:** health/profile data local by default; self-host first-class; no telemetry without opt-in; LLM calls to cloud are opt-in and the app warns which data leaves the device.
- **Offline:** full generation possible with local LLM or no-LLM fallback; PWA caches plans/grocery.
- **Performance:** a validated week in ≤ 5 s with local optimizer (no LLM); a year block generated incrementally/async with progress. Cache targets & candidate pools.
- **Internationalization:** units (g/ml/katori/cup), languages (English/Hindi first; extensible), regional cuisine packs.
- **Accessibility:** WCAG 2.1 AA; large-text/elderly-friendly mode (relevant to the elderly persona).
- **Extensibility:** new region = add season_calendar + seasonal_availability + cuisine pack + (optional) guideline profile; no code change.
- **Data governance:** KB and food DB are versioned; every rule/number carries a source; a "Sources" screen lists every document and page used.

### 13.2 Safety, medical scope & disclaimers
- Prominent disclaimer: *guideline-based general nutrition education, not medical advice / not MNT.* (mirrors the Excel "Not medical advice" note.)
- Therapeutic/condition modes (diabetes tight control, CKD stages, dialysis, pregnancy complications) show a **"confirm with your doctor/dietitian"** gate and cite the source guideline; CKD/renal filtering is advisory and clinician-flagged (§6.3).
- No supplement/drug dosing beyond what a cited guideline states as general advice (e.g., DGI IFA note) — always "discuss with provider."
- Infant/complementary-feeding mode strictly follows DGI G3–G4 (exclusive breastfeeding 0–6 mo, no added sugar <2 y) and never recommends against breastfeeding.

### 13.3 Phased roadmap (detail)
- **Phase 1 — MVP (India, core):** profiles+targets; deterministic planner; 1 LLM adapter + no-LLM mode; day/week; India season calendar + seed recipe pack (import from Excel); grocery; xlsx/PDF export; conditions: diabetes, hypertension, weight goals, vegetarian; DQS v1. Exit: G1/G6/G7 pass on fixtures.
- **Phase 2 — Depth:** month/year (366) + full uniqueness engine; life-stage modes (pregnancy, lactation, infant/child/adolescent, elderly) with DGI tables; conditions +CKD(advisory)/dyslipidemia/thyroid/PCOS/fertility/liver/TB; cost/affordability mode; conversational intake; OR-Tools optimizer. Exit: G2/G3/G4 pass.
- **Phase 3 — Breadth/community:** multi-country guideline packs (DGA/WHO profiles) & cuisine packs; contributor tooling + recipe review queue; wearable/grocery-API integrations; sharing; mobile wrappers.

### 13.4 Testing & validation strategy (guarantees the "no invention" promise)
- **Nutrient-accuracy tests:** golden recipes with hand-verified totals; assert engine == expected within rounding; assert **no nutrient value originates from the LLM** (provider mocked to return only choices).
- **Constraint tests:** property-based (Hypothesis) — for random valid profiles, generated days **never** violate HARD constraints (allergen=0, sodium/sugar caps, condition limits).
- **Uniqueness tests:** generate 366 days; assert menu-level uniqueness and per-tier min-gaps hold; report realized repeat-gaps.
- **Seasonality tests:** ≥ G2 threshold of produce in-season for each month/region.
- **Guideline-fidelity tests:** spot-check that encoded numbers equal the cited source values (e.g., My Plate 250/85/300/35/27/400/100; salt ≤5 g; sugar <5 %E) — a regression guard against KB drift.
- **LLM-swap tests:** identical profile+seed across two providers yields identical nutrient numbers (only wording/choice differs).
- **Import/export round-trip:** Excel → import → export → structurally equal.

### 13.5 Risks & mitigations
| Risk | Mitigation |
|---|---|
| LLM hallucinates nutrients/portions | Numbers computed by engine; closed vocabulary; validation gate; no-LLM fallback (§9.2) |
| "366 unique" misread as impossible literal | Tiered model + explicit policy + honest UI messaging (§8) |
| Thin recipe DB for a region ⇒ repeats | LLM-assisted validated variation; surface realized gaps; contributor packs |
| Food-composition gaps/errors | Source-tagged rows; group-average estimates flagged; IFCT primary, USDA fallback |
| Over-reach into medical therapy | Clinician-review flags; disclaimers; advisory-only therapeutic modes (§13.2) |
| Seasonal calendar inaccuracy | Region packs reviewed; availability_score soft-constraint; user override |
| Guideline updates (new DGI/DGA) | KB versioned; rules are data; add new guideline profile without code change |
| Cloud-LLM privacy leakage | Local-first; opt-in cloud with data-egress warning; keys never logged |

---

## 14. Evidence Register (every number, source-cited)

This register is the machine- and human-readable backbone of the KB. Values are transcribed from the source documents with page citations; the app stores them as `guideline_rule`/`condition_rule`/`food_composition` records. **If a value is not here (or in the linked source), the app does not assert it.**

### 14.1 DGI 2024 "My Plate for the Day" — reference 2000 kcal (S1 p.3, p.7, back cover)
| Food group | Vegetarian raw g/day | %E | Non-veg raw g/day | %E |
|---|---|---|---|---|
| Cereals & millets | 250 | 42 | 260 | 45 |
| Pulses | 85 | 14 | 55 | 9 |
| Chicken/meat/egg | — | — | 70 | 5 |
| Milk/curd (ml) | 300 | 11 | 300 | 11 |
| Vegetables + GLV | 400 | 9 | 400 | 8 |
| Fruits | 100 | 3 | 100 | 3 |
| Nuts & seeds | 35 | 9 | 30 | 11 |
| Fats & oils | 27 | 12 | 27 | 12 |
| **Total** | **~1200 g → ~2000 kcal, protein ~72 g (15 %E), fat ~66 g (30 %E), carb ~55 %E** | | | |
Rules: ≥50% cereals as whole grain; **millets 20–30% of cereals** (adults), 20% (children ≤10 y); 30 g pulses substitutable with meat/egg for non-veg (S1 p.129).

### 14.2 DGI 2024 food-group quantities by body weight / life stage (S1 Annexure V / Table 1.6, p.129 / p.11)
Raw g/day: Cereals&Millets · Pulses · GLV · Vegetables · Roots&Tubers · Fruits · Nuts · Milk/Curd(ml) · Fats&Oils · Energy(kcal) · Protein(g). *(Full 21-row table stored in KB; representative rows:)*
| Group (body wt) | Cer | Pul | GLV | Veg | R&T | Fru | Nut | Milk | Fat | kcal | Prot |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Man sedentary 65 kg | 260 | 85 | 100 | 200 | 100 | 100 | 40 | 300 | 30 | ~2080 | 72 |
| Woman sedentary 55 kg | 190 | 60 | 100 | 200 | 100 | 100 | 30 | 300 | 25 | ~1660 | 57 |
| Pregnant (55+10) | 220 | 75 | 150 | 200 | 100 | 150 | 40 | 400 | 30 | ~2020 | 72 |
| Lactating 0–6 mo | 260 | 85 | 150 | 200 | 100 | 150 | 40 | 400 | 35 | ~2245 | 77 |
| Infant 7–12 mo (8.5 kg) | 25 | 12 | 20 | 25 | 20 | 40–60 | 7 | +BM ~580 | 10 | — | — |
| Child 1–3 y (12.9 kg) | 100 | 50 | 50 | 100 | 50 | 60–75 | 10 | 350 | 20 | ~1110 | 38 |
| Child 4–6 y (18.3 kg) | 160 | 60 | 50 | 100 | 50 | 75 | 15 | 350 | 20 | ~1370 | 46 |
| Child 7–9 y (25.3 kg) | 200 | 65 | 100 | 150 | 100 | 100 | 20 | 400 | 25 | ~1710 | 59 |
| Boys 16–18 y (55 kg) | 390 | 130 | 100 | 200 | 100 | 150 | 45 | 400 | 40 | ~2860 | 98 |
| Elderly man >60 | 170 | 75 | 100 | 200 | 100 | 150 | 30 | 400 | 25 | ~1740 | 62 |
| Elderly woman >60 | 140 | 70 | 100 | 200 | 100 | 150 | 30 | 400 | 15 | ~1530 | 56 |
Note: normal BMI reference 18.5–23; diets ~30 %E fat, ~15 %E protein; sources IFCT 2017, Nutrient Requirements for Indians 2020.

### 14.3 Macronutrient/limit targets & anthropometry (S1; S4; S3)
- Energy split: carb 50–55 %E, protein 10–15 %E, fat 20–30 %E (S1 p.5). Cereals ≤45 %E; pulses+flesh ~14 %E (S1 p.16).
- Protein: EAR 0.66, **RDA 0.83 g/kg** (S1 p.58); muscle/elderly up to **1.2–1.6 g/kg** (S3 p.2); **>1.6 g/kg no extra muscle gain** (S1 p.60). Cereal:pulse **3:1** + 250 ml milk for EAA (S1 p.58).
- Fat: total ≤30 %E; **visible oil by activity** — sed ♀20/♂30, mod ♀30/♂40, heavy ♂50 g/day (S1 p.54); **sat <10 %E** (S4) / <5 %E visible SFA (S1 p.93); **trans <1 %E** (S4); n-6 ≥3 %E (~6.6 g), n-3 0.6–1.2 %E (~2.2 g) (S1 p.54).
- Added/free sugar **<10 %E, ideally <5 %E (≤25 g/day)**; no added sugar <2 y (S4; S1 p.94, p.129).
- Salt **<5 g/day (<2 g/2300 mg Na)** (S1 p.91,93; S4 p.5). Fibre **~25 g/1000 kcal** (S1 p.17). Water **~2 L/day incl. beverages** (S1 p.89).
- BMI = kg/m². **Asian:** normal 18.5–23, overweight 23–27.5, obese >27.5 (S1 p.62–64). **WHO:** 18.5–25 / 25–30 / >30 (S4; S6 p.198). Waist risk **>90 cm ♂ / >80 cm ♀** (S1 p.64).
- BMR Mifflin–St Jeor (default): ♂ 10W+6.25H−5A+5; ♀ 10W+6.25H−5A−161. Harris–Benedict retained for clinical parity (S2 Annex 9). TDEE = BMR×PAL. Weight loss: deficit 500–750 kcal, **floor ≥1000 kcal/day**, **0.5 kg/week** (S1 p.64,81–83).
- Pregnancy: +350 kcal (2nd–3rd tri), protein +8 g (2nd)/+18 g (3rd); gain 10–12 kg; **IFA 60 mg iron + 0.5 mg folic acid from wk 12** (S1 p.13–19). Lactation: +600 kcal/+13.6 g (0–6 mo), +520 kcal/+10.6 g (7–12 mo) (S1 p.15).

### 14.4 Condition constraint packs (S2, cross-checked S1/S3/S4) — abbreviated
| Condition | Key quantified rules (source pages) |
|---|---|
| **Diabetes** | Carb 50–60 %E (33% if overweight); **45–60 g carb/meal**; prefer **GI<55**; sat fat <7 %E; 3 meals+2 snacks; Na<1550 mg if CVD risk; fruit GI≤55 (S2 p.3–14) |
| **Hypertension** | DASH; **Na <2300 (ideal <1500) mg**; fruit+veg 4–5 serv each (~400 g); fat ~20–27 %E, sat ≤7 %E; K/Ca/Mg-rich (S2 p.27–33; S4 p.5) |
| **CHD / dyslipidemia** | Fat 25–35 %E, **sat <7 %E, trans <1 %E, cholesterol <200 mg**; soluble fibre 5–10 g; oily fish ≥2×/wk; stanols/sterols (S2 p.15–25,45–50) |
| **CKD (advisory)** | 30–35 kcal/kg; **protein 0.6–0.8 g/kg** pre-dialysis, 1.2 on dialysis; K/PO₄ food-list filtering (low-K <125 mg/serv); Na 1–3 g; fluid=urine+500 ml (S2 p.51–73) |
| **Liver** | Energy 25–45 kcal/kg; protein 1.2–2.0 g/kg (don't restrict in encephalopathy); 4–7 small meals; abstain alcohol (S2 p.81–88) |
| **TB** | +200–300 kcal; protein 1.2–1.5 g/kg (~75–100 g); micronutrient-dense; 6 small meals if poor appetite (S2 p.123–128) |
| **Thyroid** | Iodized salt, iodine 150 µg, selenium; moderate goitrogens (S1 iodine; S7) |
| **Acidity/GERD** | 4–5 small meals; last meal ≥3 h pre-bed; limit fried/very-spicy (S7) |
| **Fertility/pre-conception** | Folate ≥400 µg 3 mo prior; iron stores; zinc; selenium (S1 p.13; S7) |
| **Elderly (age-related)** | ≥⅓ cereals whole-grain; 200–400 ml low-fat milk; 400–500 g veg+fruit; protein quality vs sarcopenia; Ca+VitD vs osteoporosis; ~2 L water (S1 p.101, G16) |

### 14.5 HFSS / UPF thresholds (S1 Table 15.1, p.96; Table 15.2 A/B/C, p.97–98)
Per 100 g solid: kcal >250, salt >625 mg, added sugar >3 g, added fat >4.2 g ⇒ "high." Per 100 ml liquid: kcal >70, salt >175 mg, added sugar >2 g, added fat >1.5 g. Processing groups A (unaltered)/B (altered, no additives)/C (**UPF**) × calorie classes 1/2/3; all Group C = UPF (hard-cap); **nuts/seeds exempt** from HFSS despite density. HFSS fat = >15 %E added fat (>30 g/2000 kcal); high SFA >10 g/day visible or >5 %E; high salt >5 g/day; high sugar >5 %E or >25 g/day.

### 14.6 Glycemic Index/Load, common Indian foods (S1 Annexure III, p.126) — engine uses for diabetes/low-GI modes
Rice GI 78.2 / GL 49.4 · Wheat chapatti 65.7/32.8 · Bengal gram 38.0/19.0 · Green gram 42.5/21.2 · Red gram 43.0/21.5 · Wheat+chana dhal 32.4/16.2 · Idli sambar 68.7/34.3 · Vada sambar 36.9/18.4 · Curd rice 64.9/32.5 · Vegetable dosa 64.0/32.0 · Pesarattu 60.7/33.7. (n=10; per 50 g available carb; indicative.) Complementary Sri Lankan GI set in S2 Annex 3 (white rice 87, whole-meal bread 70–82, most vegetables <15, legumes 14–48).

### 14.7 WHO Healthy-Diet quantified limits + evidence chain (S4)
Adults: fruit+veg **≥400 g/day** (excl. starchy roots); free sugars **<10 %E (ideally <5 %E ≈ 50 g @2000 kcal)**; total fat **<30 %E**; sat fat **<10 %E**; trans fat **<1 %E** (eliminate industrial trans); salt **<5 g/day (iodized)**; breastfeed exclusively 0–6 mo, continue to 2 y+. WHO/FAO reference chain (the 19 refs on S4): Hooper 2015 (total fat & body weight, Cochrane CD011834); WHO TRS 916 (2003); FAO FNP 91 (2010, fats/fatty acids); Nishida & Uauy 2009 (trans fats); WHO SFA/TFA guideline 2018; WHO REPLACE 2018; WHO Sugars guideline 2015; WHO Sodium guideline 2012; WHO Potassium guideline 2012; Comprehensive implementation plan MIYCN 2014; NCD action plan 2013–2020; Mozaffarian 2014 (sodium & CVD deaths, NEJM 371:624); Te Morenga 2014 (sugars & cardiometabolic risk, AJCN 100:65); WHO Global strategy 2004; WHO marketing-to-children 2010; Ending Childhood Obesity 2016; Rome Declaration 2014; ICN2 Framework for Action 2014; WHO GPW13 2019–2023.

### 14.8 SOFI 2026 healthy-diet constructs & India context (S6)
- **Healthy diet — 4 principles (FAO/WHO 2024):** adequate, balanced, diverse, moderate (+ safe) (S6 p.1, p.53).
- **Healthy Diet Basket (2330 kcal, 11 items/6 groups):** starchy staples 1160 kcal (49.8%), animal-source 300 (12.9%), legumes/nuts/seeds 300 (12.9%), oils/fats 300 (12.9%), fruits 160 (6.9%), vegetables 110 (4.7%) (S6 Table 3.1, p.55).
- **Diet-diversity indicators:** **MDD-W** ≥5 of 10 groups (women 15–49); **MDD-C** ≥5 of 8 groups (children 6–23 mo) (S6 p.197; Annex 1B).
- **India (Annex 1A):** PoU 9.8%; wasting <5 = 18.7%; stunting <5 = 32.9%; child overweight 3.7%; adult obesity 8.0%; anaemia women 53.7%; exclusive breastfeeding 63.7%; low birthweight 27.4%; MDD children 23.6%; CoHD **4.11 PPP$/day (2025)**; unaffordability 35.5% / 520.1 M people (2025).
- **GNR 2026 diet-quality dimensions** (S5 p.120): variety/diversity, adequacy, moderation, balance — implemented as the DQS (§7.7).

### 14.9 Food composition (sample; S7 FoodDB seeded from IFCT 2017; S1 Tables 1.3–1.5)
Per 100 g raw — kcal/protein/carb/fat/fibre/iron/calcium: Rice milled 356/7.9/78/0.5/2.8/0.7/7.5 · Wheat atta 320/11.4/64.3/1.5/11.4/3.9/30 · Bajra 347/10.9/61.8/5.4/11.5/6.4/27 · Ragi 321/7.2/66.8/1.9/11.2/4.6/**364** · Moong dal 347/24/59/1.2/8.2/4.5/75 · Chana dal 360/22.5/60.1/5.3/15.1/4.9/56 · Soya chunks 345/**52**/33/0.5/13/20/350 · Paneer (group) · Spinach/GLV group 45/3.8/5/0.7/—/8.07(Fe)/279(Ca) · Groundnut oil 900/0/0/100. Group-average rows (S1 Tables 1.3–1.5) back estimation when an item is absent (flagged as estimate). Every row carries `source` (IFCT 2017 primary; USDA fallback).

### 14.10 Seasonality model (illustrative; extensible per region)
The Excel's 4-season week-mapping (Winter W01–08/W49–52, Spring W09–12, Summer W13–25, Monsoon W26–48) generalizes to `season_calendar(region, month→season)` + `seasonal_availability(region, month, item, score)`. Season-gated behaviors observed in the seed data become rules: *sarson saag → winter only; sattu drink/coconut water → summer; "eat well-cooked, avoid raw salads" → monsoon; gajar halwa/dark-chocolate treat → winter weekend.* DGI mandate: "fresh, locally available, **preferably seasonal**" (S1 p.49).

### 14.11 Source citation list (bibliography)
- **S1** ICMR-NIN Expert Committee. *Dietary Guidelines for Indians, Revised Edition 2024.* Hyderabad: ICMR-National Institute of Nutrition; 2024. (148 pp; 17 guidelines; 10 food groups.)
- **S2** Withana C (author); Mahamithawa AMASB (ed.). *Dietary Guidelines & Nutrition Therapy for Specific Diseases.* Nutrition Division, Ministry of Health, Sri Lanka; 2014 (UNICEF-sponsored).
- **S3** USDA & US-HHS. *Dietary Guidelines for Americans, 2025–2030.* Washington, DC; Jan 2026.
- **S4** WHO. *Healthy diet.* Fact Sheet N°394, updated Aug 2018 (+ 19-ref WHO/FAO evidence chain, §14.7).
- **S5** Ghosh S, Zanello G, et al. *2026 Global Nutrition Report — Integrating food and health systems for climate-resilient nutrition.* Seattle: PATH; 2026 (132 pp).
- **S6** FAO, IFAD, UNICEF, WFP, WHO. *The State of Food Security and Nutrition in the World 2026 — Understanding and addressing the high cost of a healthy diet.* Rome: FAO; 2026. https://doi.org/10.4060/cd8306en
- **S7** Eastern Diet Planner workbooks v5/v6.3/v7 (personal; ICMR-NIN 2024 + IFCT 2017 based) — output-format reference.
- **Supporting data:** *Indian Food Composition Tables (IFCT) 2017*, NIN; *Nutrient Requirements for Indians (RDA/EAR) 2020*, ICMR-NIN; *USDA FoodData Central* (fallback composition).

---

## 15. Glossary
- **BOM** — Bill of Materials: the component→ingredient→quantity breakdown of a recipe (the Excel `Ingredients` sheet); enables deterministic nutrient totals and grocery aggregation.
- **DQS** — Diet-Quality Score (GNR 2026 four dimensions: variety, adequacy, moderation, balance).
- **FBDG** — Food-Based Dietary Guideline (e.g., DGI 2024, DGA 2025–2030).
- **HFSS / UPF** — High-Fat-Sugar-Salt foods / Ultra-Processed Foods (DGI Guideline 15 thresholds).
- **HDB** — Healthy Diet Basket (SOFI 2026; 6 groups/11 items @2330 kcal).
- **MDD-W / MDD-C** — Minimum Dietary Diversity for Women / Children (diversity indicators).
- **My Plate** — ICMR-NIN's daily balanced-plate food-group quantities.
- **PAL** — Physical Activity Level (1.2 sedentary → 1.9 heavy).
- **RDA / EAR** — Recommended Dietary Allowance / Estimated Average Requirement (ICMR-NIN 2020).
- **Tier 0/1/2 uniqueness** — staple base (bounded recurrence) / composed dishes (non-repeat) / hero ingredient (rotated), §8.
- **Provenance** — the per-plan record binding KB version, LLM, seed and citations for reproducibility/audit.

---

## 16. Open questions / decisions to confirm
1. **Default guideline profile** per user region (India→DGI; US→DGA; else→WHO) — confirm auto-selection vs. explicit choice at onboarding.
2. **`DISH_MIN_GAP_DAYS` default** — 21 (variety-first) vs 366 (strict "never repeat in a year"). Recommendation: 21 with a "strict year" toggle.
3. **Household blending** — single blended plan with per-member portions vs. per-member plans sharing a grocery list. Recommendation: shared menu, per-member portions (matches the Excel's 2-person model).
4. **Recipe seed corpus** — import the Eastern Diet Planner library first; target pool sizes for full-year non-repetition (§8.3).
5. **Cloud-LLM policy** — ship local-only by default; require explicit opt-in per deployment for any cloud provider.
6. **Micronutrient depth in MVP** — start with iron/calcium/B12/protein/fibre (Excel set) then extend to zinc/folate/VitD/iodine (Phase 2).

## 17. Platforms, Information Architecture & Visual Design (Android + Web)

Rituva ships as a **native-quality Android app** and a **responsive website (PWA)**, sharing one backend/API (§12) and one design system. The experience is **lively, futuristic and rich** — motion-aware, data-visual, glass-and-glow — while staying calm and legible for daily use and accessible for elderly users.

### 17.1 Target platforms
- **Android app:** Flutter (recommended) or React Native — one codebase, native performance, offline cache, push reminders, home-screen widgets (today's meals), camera for prescription/label capture. Min Android 8+.
- **Website / PWA:** Next.js/React responsive from 360 px (mobile web) to desktop; installable PWA; offline plan viewing; identical account & data via the shared API.
- **Parity rule:** every feature works on both; layouts adapt (bottom-tab nav on mobile → left rail + wider canvas on desktop). Same design tokens, so a screen looks unmistakably "Rituva" on both.

### 17.2 Visual design language ("lively / futuristic / rich")
- **Mood:** fresh, health-forward, energetic, premium. Food-warm but tech-precise.
- **Color:** a vivid **green→teal** core (vitality) with **lime** highlight and a warm **coral/amber** accent (food, energy), over **deep-ink** surfaces in dark mode and airy off-white in light mode. Macro colors are fixed and consistent everywhere (protein = teal, carbs = amber, fat = violet, fibre = green).
- **Surfaces:** **glassmorphism** cards (blur + translucent fill + hairline border), soft layered shadows, generous 20–28 px radii, subtle mesh-gradient/aurora backgrounds and gentle glow on primary actions.
- **Data-visual first:** animated **macro rings**, calorie **progress arc**, micronutrient bars, weekly **adherence heatmap**, lab-trend sparklines, seasonal calendar bands, a **Diet-Quality Score** dial.
- **Motion:** purposeful micro-interactions (ring count-up, card rise on tap, shared-element transition into meal detail, swipe-to-swap), 150–300 ms, spring easing; fully respects `prefers-reduced-motion`.
- **Typography:** a friendly-geometric display (e.g., Sora/Space Grotesk) + highly legible text (Inter); large numerals for targets.
- **Theming:** light + dark (dark is the hero look); an **Elderly / High-legibility mode** (larger type, higher contrast, simplified cards) for the elderly persona.
- **Iconography/imagery:** rounded duotone icons; food shown via a curated illustration/emoji set in v1 (no AI-generated food images), real photography optional later.
- **Accessibility:** WCAG 2.1 AA contrast, ≥44 px targets, full dynamic-type scaling, screen-reader labels on every ring/chart.

### 17.3 Information architecture (navigation & screen inventory)
**Primary nav (5 tabs)** — mobile bottom bar / desktop left rail:
1. **Home (Today)** · 2. **Plan** (Week / Month / Year) · 3. **Discover** (Recipes & regional cuisines) · 4. **Health** (conditions, measurements, doctor diet, targets) · 5. **Profile** (household, preferences, settings).
**Supporting screens:** Onboarding flow (multi-step), Meal/Recipe detail, Swap sheet, Grocery list, Insights/Analytics, Notifications, LLM & data settings, Export, Sources/citations viewer, Auth.

### 17.4 Screen-by-screen specification (what each tab shows — for approval)
1. **Onboarding (multi-step, progressive):** welcome → personal details (age, sex, height, weight → **live BMI ring**) → activity & goal → **regional cuisine picker (N/S/E/W, multi-select chips)** → diet type & allergies/exclusions → **health measurements** (optional labs) & conditions → **doctor-prescribed diet** (enter or scan) → known targets (optional) → review & confirm. Friendly, one-decision-per-screen, skippable-optional fields, progress bar.
2. **Home / Today:** greeting + date + season badge; **calorie arc + 3 macro rings**; the **5 meal cards** (breakfast/lunch/dinner/2 snacks) with dish, portion (g + katori), kcal, and a tap-through; **water tracker**; "Why this plan" chip → citations; quick **Swap** and **Cook mode**; today's **Diet-Quality Score**; condition/health nudges (e.g., "sodium 78% of your limit").
3. **Meal / Recipe detail:** hero dish, region tag, meal slot; **ingredient BOM with per-ingredient nutrient breakdown** (e.g. *Arhar dal 200 g → protein / carb / fibre*) read from the Knowledge DB with `source: IFCT 2017`; computed nutrition panel (macros + key micros); step-by-step method, time, cost tier; **citation line** for any rule it satisfies; swap / add-to-grocery / mark-cooked; uniqueness note ("not repeated for 27 days").
3b. **Swap & equivalent alternatives (§8.5, §11.6):** decline a dish → ranked iso-calorie / iso-nutrient options (same slot, all constraints, frequency caps, uniqueness), each with a **per-ingredient DB nutrient breakdown** and a **delta vs the original** ("−12 kcal · +2 g protein"); **live frequency counters** ("Mushroom 2/2 · cap reached", "South-Indian days 2/3"); "not today / this week / never" controls; footnote reminding that every figure is from IFCT, not the model.
4. **Plan — Week:** 7-day × 5-slot grid (the Excel `Current_Week` shape), per-day kcal & DQS, notes column (season/condition tips); tap a cell → meal detail; **Generate/Regenerate week**; weekly nutrient roll-up.
5. **Plan — Month:** calendar with **season bands** and a per-day dot (DQS color); tap → day; month grocery + cost estimate; "all days unique" indicator.
6. **Plan — Year (366):** scrollable year calendar, season ribbon, uniqueness meter ("366/366 distinct"); jump to any date; async generation with progress.
7. **Discover:** browse recipes filtered by **region (N/S/E/W)**, meal slot, condition-safe tags, season; recipe cards; a **"Regional mix"** control to set/blend cuisine weights; save favorites (favor in generation).
8. **Health:** condition cards with **cited targets**; **doctor-prescribed diet** card (active prescription, review date, "following your doctor" badge); **measurements** entry + **lab-trend sparklines** (HbA1c, BP, lipids, TSH…); nutrient-focus flags; "confirm with clinician" gates on therapeutic modes.
9. **Insights / Analytics:** weekly/monthly **adherence heatmap**, macro-distribution trend, **DQS** over time, micronutrient coverage (iron/calcium/B12/…), sodium/sugar vs limits, in-season %.
10. **Grocery:** auto-aggregated, categorized, household-scaled list (Staples, Dals, Vegetables, GLV, Dairy, Nuts/Seeds, Fruits, Spices, Beverages); check-off; export/share; unmapped-item prompts.
11. **Profile & Settings:** household members (switch/add), regional & diet preferences, **LLM config** — *paste one API key (e.g. NVIDIA build.nvidia.com) → models auto-configured with graceful fallback*, or local Ollama, or no-LLM; units (g/katori), language (English/Hindi…), theme + elderly mode, privacy/data (local-first), **export to .xlsx/PDF**, **Sources** screen listing every document/page used.

### 17.5 Regional-preference UX (N/S/E/W)
A four-way chip/segmented selector with map-style region cards; multi-select allowed with an optional weight slider per selected region; live preview of "a typical day" updates as regions change. Legacy sub-styles (e.g., Bihari within East) offered as a secondary chip.

### 17.6 Doctor-prescribed-diet UX
Card with two entry paths — **"Scan prescription"** (camera/upload → LLM extract → **confirmation screen** where the user verifies each field) and **"Enter manually"** (structured form). Active prescriptions show a distinct badge across the app and a "following your doctor" note wherever their numbers differ from the guideline default (§6.5).

### 17.7 Design tokens (starter set)
- **Color (dark):** bg `#0B1220`, surface-glass `rgba(255,255,255,.06)`, primary `#22E3A7`, primary-2 `#12B5C9`, lime `#B6F36B`, accent-coral `#FF7A66`, text `#E6EDF3`, muted `#8A97A6`. **Macros:** protein `#12B5C9`, carbs `#F5B23D`, fat `#A78BFA`, fibre `#37D67A`. (Light theme = same hues on `#F7FAF9`/white surfaces.)
- **Type scale:** 32/24/20/17/15/13; display font Sora, text font Inter.
- **Radius:** card 24, chip 999, sheet 28. **Spacing:** 4-pt base (8/12/16/20/24/32).
- **Elevation:** layered soft shadows + 12–20 px backdrop-blur on glass. **Motion:** 200 ms spring default.

### 17.8 Component library (shared across Android & web)
Macro Ring, Calorie Arc, Meal Card, Nutrient Bar, Region Chip, Condition Card, Lab Sparkline, DQS Dial, Season Badge, Water Tracker, Swap Sheet, Citation Chip, Grocery Row, Segmented Nav, Glass Card, Progress Stepper, Empty/Loading/Skeleton states.

### 17.9 Prototype & approval process
A **browseable, interactive HTML prototype** accompanies this PRD (rendered in the browser during review) showing every tab above in an Android device frame plus a desktop-web layout, in the actual color/motion language. **Review flow:** the user approves each tab/layout (✅/changes) — onboarding, home, meal detail, week, month/year, discover, health, insights, grocery, settings. Approved screens become the source of truth for hi-fi design (Figma) and front-end implementation; requested changes are logged against the specific screen in §17.4.

---

## 18. Reference implementation (scaffold)

A runnable scaffold of the deterministic core lives in the `rituva/` package. It
proves the architecture end-to-end **with zero third-party dependencies and no API key**
(the standard library only), and is the correctness backstop the rest of the system
builds on.

### 18.1 Layout
```
rituva/
  domain.py     # enums + dataclasses (PRD §12.4 vocabulary)
  knowledge.py  # seed Knowledge DB — FOODS (IFCT 2017), RECIPES (BOM), GUIDELINE_RULES,
                #   FREQUENCY_POLICY, EQUIVALENCE_CLASSES, SEED_MEMBERS
  nutrition.py  # nutrient totals = BOM × FoodComposition; UnknownFoodError; iso-distance
  targets.py    # BMI (Asian), BMR (Mifflin–St Jeor), TDEE, macro targets; doctor/known precedence (§6.5)
  planner.py    # Ledger (dish min-gap + hero/pulse/region weekly caps), DeterministicPlanner
                #   (grain-scaled to target), validator + Diet-Quality score, iso-nutrient alternatives
  gateway.py    # OpenAI-compatible providers (NVIDIA NIM / OpenAI / Ollama), key-only
                #   auto-discovery, availability-aware FallbackRouter -> no-LLM (§10.5)
  graph.py      # pipeline; LangGraph when installed, dependency-free sequential fallback (§9.7)
  context.py    # system date/time/season/current-meal detection from the device clock (§7.8)
  store.py      # SQLite persistence + JSON (de)serialization of members/plans
  api.py        # FastAPI REST layer (members · targets · plans · day · alternatives · context)
  cli.py        # runnable CLI
tests/test_core.py · tests/test_api.py     # run under pytest OR standalone
requirements.txt · README.md
```

### 18.2 Run it
```bash
python -m rituva.cli --member aarav --days 7 --alt        # validated week + alternatives
python -m rituva.cli --member diya --regions south,east   # blended regions
python -m rituva.cli --member aarav --days 366            # full year, all unique
python -m rituva.cli --provider nvidia --api-key $NVIDIA_API_KEY   # key-only LLM (optional)
python tests/test_core.py                                    # 6/6 green
uvicorn rituva.api:app --reload                              # REST API + Swagger UI at /docs
```

### 18.3 What it demonstrates (verified)
- **No invented numbers.** All nutrients computed from the DB; the CLI prints a live check
  (`200 g Arhar dal → protein 44.6 g …[IFCT 2017]`) — the exact IFCT value, not a guess.
  `UnknownFoodError` fires for any food absent from the DB (test-covered).
- **Targets + precedence.** BMI 24.1 / BMR 1646 for the seed profile; doctor-prescribed diet
  overrides computed targets (test-covered).
- **Uniqueness + frequency regulation.** Over 28 days, mains never repeat within the 6-day gap
  and per-hero weekly caps (mushroom ≤2, paneer ≤3…) are never exceeded (test-covered); a
  366-day plan generates with every day distinct and caps held all year.
- **Iso-nutrient alternatives** with per-ingredient DB breakdowns and deltas vs the original.
- **LLM-agnostic + graceful fallback.** `provider=none` runs the whole product; a configured
  key auto-discovers models and fails over model→model→provider→no-LLM.

### 18.4 Status & next (live tracker: `CONTEXT.md`)
**Landed (scaffold Phases A–D complete):** expanded Knowledge DB (95 foods / 94 recipes);
SQLite persistence (`store.py`, Postgres-ready) + **FastAPI REST layer** (`api.py`); **system-context
detection** (`context.py`, §7.8); **hybrid RAG** (`retrieval.py` — BM25 + TF-IDF, RRF-fused over cited
rules + recipes) + **long-term memory** (`memory.py` — never/dislike/like) wired through the LangGraph
pipeline (`graph.py`, §9.7); **food-logging + adherence** feedback loop (`adherence.py`, §19.2); and a
served **PWA frontend** (`web/`) on the approved design at `/app`. Tests: **9/9 core + 13 pytest**.
**Next:** native Android; live Postgres + pgvector embeddings for the dense channel; `.xlsx`/PDF/calendar
export (§11.3); OR-Tools optimizer (§9.3); Grocery endpoint/view; and the remaining §19 P0/P1
(barcode/photo logging, wearables/CGM, adaptive targets, notifications).
> **`CONTEXT.md`** in the repo root is the living build tracker — read it first when resuming.

---

## 19. Competitive landscape & feature-gap roadmap

Rituva's differentiation is on the **supply / generation** side — guideline-grounded, seasonal, regional (N/S/E/W), 366-day non-repeating, frequency-regulated, condition- and doctor-diet-aware, iso-nutrient swaps, LLM-agnostic, and **no invented numbers**. A 2026 survey of category leaders (MyFitnessPal, Yazio, Lifesum, Cronometer, Noom, MacroFactor, Eat This Much, Samsung Food, Mealime, PlateJoy; India: HealthifyMe, Fittr, PlanNEat, NutriScan) shows they compete and *retain* on the **demand / feedback** side. Rituva is currently **generation-first / open-loop**; the category is **consumption-tracking / closed-loop**. This section catalogs the gaps and prioritizes closing them.

### 19.1 What Rituva already has vs. the category
| Capability | Rituva | Category norm |
|---|---|---|
| Auto guideline-grounded meal-plan generation | ✅ core | partial (premium tiers) |
| Seasonal + regional (N/S/E/W) Indian cuisine, blendable | ✅ | rare (a few India-native apps) |
| 366-day non-repeating + frequency caps / interchangeability | ✅ (unique) | none |
| Condition + doctor-prescribed-diet aware | ✅ | HealthifyMe (coach-led) |
| Iso-nutrient swaps with per-ingredient DB nutrients | ✅ | rare |
| Cited, never-invented nutrition numbers | ✅ (differentiator) | crowdsourced DBs are a top complaint |
| LLM-agnostic incl. local/offline + graceful fallback | ✅ | none |
| Grocery list + Excel export | ✅ | list ✅; delivery integration common |
| **Food logging / consumption loop** | ❌ | ✅ universal |
| **Wearable / Apple Health / Health Connect / CGM** | ❌ | ✅ common |
| **Adaptive targets from logged intake + weight trend** | ❌ | MacroFactor (moat) |
| **Engagement (reminders, streaks, coach, community)** | ❌ | ✅ universal |

### 19.2 P0 — table stakes (turn a plan generator into a real app)
- **Food logging & consumption loop:** manual search, **barcode scan**, **AI photo meal recognition**, voice logging → compute *adherence* and *actuals vs plan* (every major app).
- **Native Android app + offline** (web PWA already in §17) — logging on the go, cooking offline.
- **Health-platform + wearable integration:** Apple Health + **Google Health Connect** (Google Fit was deprecated Feb 2025); pull steps/weight/activity; India: smart scale + **CGM (Freestyle Libre / Dexcom)** given the condition focus.
- **Progress analytics:** weight trend, adherence %, nutrient trends over time.
- **Reminders / notifications + basic streaks** (retention floor).
- **In-app AI chat assistant** — expose our swaps/explanations conversationally, grounded and cited (cf. HealthifyMe *Ria*, Cronometer *Oracle*).
- **Grocery-delivery integration** — India: **Blinkit / Zepto / Instamart / BigBasket** (analogue of Instacart/Amazon Fresh) + **pantry/staples tracking** to de-dupe.

### 19.3 P1 — differentiators / premium-expected
- **Adaptive targets** — recompute kcal/macros from weight-trend + logged intake (MacroFactor's moat; strong retention).
- **Micronutrient dashboard** vs RDA — we already compute micros (§7.4); surface a daily coverage view (Cronometer-style), crucial for Indian vegetarian diets (B12, iron, protein).
- **Coach / dietitian consult tier + community** — the India ARPU engine (HealthifyMe, Fittr); recipe/progress sharing.
- **Guided cooking mode** (steps, timers, voice/hands-free) + **recipe media** (photos, short video).
- **Meal/day quality grade** — expose our Diet-Quality Score (§7.7) as a Nutri-Score-style badge.
- **Habit trackers:** water, **intermittent-fasting timer**, steps.
- **Localization:** Hindi + major regional languages (UI + food names) — we have regional *cuisine*, add regional *language*.
- **Diabetes/CGM correlation + medication / GLP-1 tracking** — extends condition/doctor-diet awareness into the hot 2025–26 niche.
- **Family / multi-profile household plans** — we model households (§5); add a shared plan across differing diets/conditions in the UI.
- **Deliberate freemium + transparent billing** — design around the category's top complaints (see §19.5).

### 19.4 P2 — emerging / nice-to-have
Gamification (badges/XP/challenges — with disordered-eating safeguards) · content/education (Noom-style CBT lessons for condition management) · recipe import (URL/photo) + user recipes with auto macro/micro · restaurant / branded-food & Indian-chain DB for eating-out · smart-scale / smart-kitchen devices · exports beyond Excel (PDF cards, **calendar sync** for the 366-day plan) · **meal feedback loop** (like/dislike/rating → refine personalization and frequency caps).

### 19.5 Strategic read (and complaint guardrails)
The generation engine is genuinely differentiated, but the category retains on the feedback loop: **logging → wearable/CGM data in → adaptive adjustment → engagement/coaching.** Closing **P0** turns Rituva from a generator into a competitive app; **P1** (adaptive targets + micronutrient insight + coach/community + CGM/diabetes) is where Rituva can beat Western apps for the **Indian condition-management market** HealthifyMe leads. Design *around* the category's biggest complaints (from ~50k reviews): intrusive ads, **paywalling formerly-free features**, **inaccurate crowdsourced nutrition data** (our cited-DB approach is an asset — accuracy is Cronometer's #1 praise), and **deceptive billing** (a competitor was delisted in Apr 2026 for it). Keep core value un-paywalled, the food DB accurate and sourced, and billing transparent.

*Sources: app-store listings and 2025–2026 review/roundup analyses for the apps named above; compiled July 2026. Feature attributions are to specific apps; see the research log in the session notes.*

---

*End of PRD v1.4. Every quantitative claim herein is traceable to §14 and the cited source pages; no nutrition value in this document or the system it specifies — including under a doctor-prescribed diet, and including the reference implementation in §18 — originates from an LLM.*
