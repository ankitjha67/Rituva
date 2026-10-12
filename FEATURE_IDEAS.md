# Rituva — Feature Ideation Catalog (OSINT-grounded)

> Companion to `PRD.md` §19 (competitive-gap roadmap). This catalogs **everything we
> could build**, each idea tied to a **real, current, openly-licensed data source or API**
> so it fits Rituva's one rule: **the engine owns every number; the LLM/vision/voice only
> identifies and explains.** Effort tags: **S** ≈ days, **M** ≈ 1–2 weeks, **L** ≈ 3 weeks+.
> Licensing notes are engineering guidance, not legal advice — the three traps are marked ⚠️.
>
> Verified Oct 2026 across four research sweeps (food/nutrition data, Indian OSINT,
> health/clinical, AI/vision/multilingual). Re-confirm free-tier/licence terms on vendors'
> own pages before locking anything in.

---

## 0. The licensing backbone (read first — it shapes everything)

A public, open-source app can only *bundle/redistribute* permissively-licensed data. What's safe vs. not:

| Source | Licence | Bundle in public app? |
|---|---|---|
| **USDA FoodData Central** | CC0 / US public domain | ✅ cleanest — bundle freely |
| **Open Food Facts** | ODbL (db) + DbCL + CC-BY-SA (images) | ✅ with attribution + **share-alike** |
| **data.gov.in** (Agmarknet, NFHS copy) | **GODL-India** | ✅ with attribution |
| **Poore & Nemecek footprints** (via Our World in Data) | CC BY 4.0 (OWID processed) | ✅ cite "Poore & Nemecek (2018), processed by OWID" |
| AI4Bharat models (IndicTrans2, IndicConformer) | MIT / Apache-2.0 | ✅ (repos often gated — access ≠ licence) |
| Vosk, whisper.cpp, ZXing | Apache-2.0 / MIT | ✅ |
| **IFCT 2017** | ICMR-NIN personal-use | ⚠️ **personal/private only** — already gitignored; never ship publicly |
| **ICMR-NIN RDA/DGI docs** | personal reproduction, no derivatives | ⚠️ **encode the numbers only**; don't commit the PDFs/verbatim tables |
| **INDB** (cooked-dish composition) | no explicit licence, IFCT-derived | ⚠️ same constraint as IFCT — model the *method*, don't copy values |
| FAO/INFOODS, Recipe1M, FoodSeg103, Food-101 | NC / research-only | ⚠️ non-commercial — don't bundle |
| Nutritionix, Edamam, Spoonacular, FatSecret, Sydney GI | proprietary, no-redistribution | online lookup at most; never bundle numbers |

**Rule of thumb:** USDA + Open Food Facts + GODL-India + OWID footprints + MIT/Apache AI models
are the redistributable core. Everything therapeutic stays "numbers encoded, documents not shipped."

---

## 1. Logging & consumption loop — closes PRD §19 P0 (the #1 gap)

Rituva today is generation-first (open-loop). Every competitor retains on logging. This is the biggest unlock.

| Feature | OSINT source / API | Offline | Effort |
|---|---|---|---|
| **Barcode → packaged-food logging** | **Open Food Facts** v3 API (no key; official `openfoodfacts` Dart pkg) + **ML Kit**/**ZXing** scanner (on-device) | bundle India subset (nightly JSONL dump, filter `countries`) → ✅ | **M** |
| Packaged-food search / autocomplete | Open Food Facts | ✅ (bundled subset) | **S** |
| Nutri-Score / NOVA "processing" badges | Open Food Facts fields | ✅ | **S** |
| **Nutrition-label OCR** (products not in OFF) | ML Kit text recognition → FSSAI per-100g + %RDA-on-200kcal parser | ✅ on-device OCR | **L** |
| **Photo → "snap your plate"** | dish ID via GPT-4o/Gemini vision (adapter) **or** on-device TFLite fine-tuned on Indian sets (**IndianFoodNet-30**, **Khana**, **rajistics/indian_food_images**) | cloud ID or on-device model | **M–L** |
| Voice logging ("do roti aur dal khaya") | **Vosk** (Apache-2.0, Hindi model ~44MB) / **whisper.cpp + Indic-Whisper** / `speech_to_text` on-device | ✅ fully offline | **M** |

**Discipline:** vision/voice/barcode only *identify the dish + rough portion*; the engine maps grams → IFCT/USDA
numbers. Portion/volume is the weak link (no phone depth) — keep estimates coarse and user-adjustable. **Nutrition5k**
(CC BY 4.0) is good reference data for a mass→calorie model but is Western cafeteria food.

---

## 2. Health-data integration → *measured* targets — PRD §19 P0/P1 (MacroFactor's moat)

Today `targets.py` uses a **static** `member.pal`. Make it **measured**.

- **Android Health Connect** (`health` Flutter pkg, also serves iOS HealthKit later): reads steps, active/total energy,
  weight, body-fat, sleep, HR — **100% on-device, free, un-gated, minSdk 26.** It's the **aggregation hub**: Fitbit
  (now *Google Health*), Samsung Health and most trackers write *into* HC, so reading HC captures them with zero
  per-vendor deals. **[M]**
- **Wiring (the elegant part):** add a **"measured" precedence tier** below doctor/known, above static-PAL —
  activity factor = (HC total-energy ÷ BMR) over 7–14 days. Weight/body-fat sync auto-re-runs Mifflin-St Jeor.
  In `adherence.py` the target baseline becomes *yesterday's real expenditure* → the adherence score becomes genuine
  energy balance. Wiring once HC read exists: **[S]**.
- **Adaptive targets** (recompute kcal/macros from weight-trend + logged intake) — the retention moat. **[M]**
- Garmin / Fitbit-direct / Samsung-direct APIs are cloud-gated/paused — add only as optional later sync. **[L]**

---

## 3. Clinical condition modes & lab-driven targets — PRD §19 P1 (beats Western apps for India)

Each mode is a **source-cited constraint overlay** on `NutrientTargets` (mirrors the existing `doctor > known > computed`
precedence). Ordered by effort, since several reuse fields the engine already has.

| Mode | Authoritative source | Constrains | Effort |
|---|---|---|---|
| **Hypertension / DASH** | WHO, NHLBI | sodium (2000→1500 option), **potassium floor** | **S** (sodium already modeled) |
| **Pregnancy / lactation** | ICMR-NIN RDA 2020 (already in `rda.py`) | +350/+600 kcal, iron 35mg, folate 500µg, Ca 1200mg, B12 | **S** |
| **Celiac** | medical | hard-exclude gluten → rice/millet/besan | **S** |
| **Dyslipidemia** | ACC/AHA, NHLBI | sat/trans fat, soluble fibre↑ | **S** |
| **PCOS** | 2023 Intl Guideline (Monash) | energy deficit + low-GI (reuse `Goal.LOSE`) | **S** |
| **Hypothyroid** | ATA | iodine adequacy + **drug-food timing rule** (levothyroxine 4h from Ca/iron/soy) | **S** |
| **Diabetes / prediabetes** | ADA 2026, ICMR, RSSDI | **glycemic load/meal cap**, carb-counting, fibre↑ | **M** (needs GI/GL data — §10) |
| **Gout** | ACR 2020 | per-food **purine tier**, fructose/alcohol | **M** |
| **CKD / renal** | KDOQI 2020 | protein 0.55–0.8 g/kg, **K + phosphorus caps** | **L** (needs K/P in food DB) |
| **IBS** | Monash low-FODMAP | **FODMAP tier**, 3-phase time-boxed | **L** (needs FODMAP tagging) |

**Lab-report-driven targets** — map a blood marker → a target change:

| Marker | Threshold → action |
|---|---|
| Hb / ferritin | <12(F)/<13(M) g/dL or ferritin <30 → iron↑, vit-C pairing, flag tea-with-meals |
| Serum B12 | <200 pg/mL → B12↑ (critical for lacto-veg) |
| 25-OH vit D | <20 ng/mL → vit-D↑, sun + fortified |
| HbA1c | ≥5.7% / ≥6.5% → enable Diabetes mode |
| TSH | >4.0–4.5 (low free-T4) → hypothyroid + iodine/timing |
| Lipids | LDL ≥100–130 / TG ≥150 → dyslipidemia mode |
| eGFR / creatinine | <60 → CKD mode (protein/K/P) |
| Uric acid | >6.8 mg/dL → gout/purine mode |

**Lab import via FHIR:** India's **ABDM FHIR R4 IG** delivers labs as `DiagnosticReportLab` + `Observation`, LOINC-coded,
UCUM units. One deterministic `Observation` parser serves both ABDM downloads and Health Connect's on-device FHIR
records. LLM may OCR/suggest the LOINC→marker mapping, **never set a number.** **[M]**

**Guardrail:** CKD, gout, pregnancy belong in the clinician tier (disclaimer + prefer clinician-entered values). PCOS/
hypothyroid/IBS evidence is weak — present as supportive patterns, not prescriptions.

---

## 4. Price-aware & budget planning — **net-new differentiator** (no competitor has this for India)

- **data.gov.in Agmarknet daily mandi prices** (GODL-India, free API key at api.data.gov.in): daily min/max/modal
  wholesale ₹/quintal, ~300 commodities, thousands of APMC mandis. *(Resource id historically
  `9ef84268-...`; verify live — it's WAF-flaky. For history use Ashoka **CEDA Agri-Market API**.)*
- **Features:** budget-aware/least-cost planning within nutritional constraints (**M**); **"cheapest protein today"**
  by ₹/g-protein across dal/paneer/egg/soy (**M**); per-plan cost estimate + weekly grocery budget (**M**); glut-driven
  cheap-produce nudges (**M**). Pairs with SOFI 2026 "Healthy Diet Basket" affordability reference already in `PRD.md` §7.7.
- **Offline:** cache daily snapshots; bundle a rolling price table.

---

## 5. Deeper seasonality & environmental impact — **net-new**

- **True seasonality:** no official open monthly produce calendar exists → derive from **Agmarknet monthly arrivals**
  (peak arrivals = in-season) or bundle a curated region×month table. **IMD climate normals** (free gridded data via
  `imdlib`, MIT) give region-accurate season boundaries without the non-commercial live-forecast API. **[M]**
- **Sustainability score:** **Poore & Nemecek (2018)** footprints via **Our World in Data** CSV API
  (`ghg-per-kg-poore`, `water-per-protein-poore`, …; CC BY 4.0). Small static table → **bundle outright.**
  - Carbon/water footprint per meal & per plan (**S–M**); "low-impact swap" (paneer→dal) (**S**); weekly sustainability
    score with "veg-India is already low-impact" framing (**S**). Use as **relative** scores (global averages).

---

## 6. Festival & fasting modes — **net-new, very India-relevant**

- Compute dates offline — **don't scrape** (Drik Panchang is copyrighted). Gazetted holidays via **`holidays`** (PyPI,
  MIT); lunar tithis (Ekadashi/Navratri/Amavasya) via an **ephemeris** (**skyfield**, MIT — *avoid `pyswisseph`, it's
  AGPL*); Islamic dates via `convertdate`/`hijri-converter` (flag moon-sighting variance).
- **Features:** auto-detected **vrat menus** (no onion/garlic/grain; sabudana/kuttu/singhara/fruit) for Navratri/
  Shravan/Ekadashi (**M**); Ramadan **sehri/iftar** scheduling (**M**); festival-sweet calorie budgeting (**S**).
  Reuses the existing Jain (no onion/garlic/root) classifier in `diet.py`.

---

## 7. Region-aware deficiency defaults — **net-new, smart onboarding**

- **NFHS-5** anemia/deficiency prevalence by **state/age/sex** (data.gov.in CSV = GODL; factsheets at rchiips.org).
  National anemia: children 67%, women 57%, pregnant 52% — huge state spread (Kerala <40% vs MP/Gujarat ~75%).
- **Features:** at onboarding, **pre-set iron/B12/folate emphasis** by the member's state + age + sex (**S**);
  "your state's anemia rate is X — here's an iron-forward week" (**S**). Pairs with the deficiency reference already
  shipped in the Health tab.

---

## 8. Multilingual & voice — PRD §19 P1 (India reach)

- **AI4Bharat / Bhashini** (government, open): **IndicTrans2** (MT, **MIT**, 22 langs, distilled 200M quantizable),
  **IndicConformer** (ASR, **MIT**, community GGUF/CoreML builds exist), **IndicF5 / Indic Parler-TTS** (regional TTS).
  Bhashini ULCA cloud APIs are free (PoC terms — verify for production).
- **Features:** Hindi + regional-language **UI** and **food names** (**M** offline via distilled IndicTrans2 / **S**
  server); **voice assistant & logging** in Hindi (ASR → the §9 assistant) (**M**); regional **read-aloud**
  (`flutter_tts` + Indic TTS) (**S**). Caveat: AI4Bharat HF repos are often gated — access ≠ licence; confirm each model card.

---

## 9. The intelligent assistant — **built this session; here's how to extend it**

**Shipped:** a standalone, context-grounded assistant (`mobile/lib/engine/llm.dart` + `RituvaApi.assistant`) that reads
the member's profile/health/targets + the whole week + engine-computed swap options, and suggests concrete grounded
changes ("different Sunday breakfast" → real alternative + exact kcal/protein delta). Numbers come from the engine.

**Extensions:**
- **Tool-using / action-taking** (next big step): let the assistant *apply* a swap, change a goal, or log a meal via a
  structured action the app executes deterministically (LLM proposes the action, engine performs it). Ties directly to
  **F1** (make swaps apply). **[M]**
- **LLM-written plan explanations & recipe cards on-device** (route through the same NVIDIA client, not just chat). **[S]**
- **Voice in / voice out** (§8) for a hands-free kitchen assistant. **[M]**
- **Proactive nudges** ("you're low on B12 this week — here's a swap") computed by the engine, phrased by the LLM. **[S]**
- **On-device open-weights option** (Ollama/llama.cpp via the adapter) for a fully-offline assistant. **[L]**

---

## 10. Micronutrient & glycemic depth — PRD §19 P1

- **Micronutrient dashboard vs RDA** — partly shipped (Analytics shows iron/calcium/B12 %RDA; B12 gap surfaced). Expand
  to the full ICMR-NIN micro set (zinc, folate, vit A/C/D, iodine, magnesium) with a Cronometer-style coverage view.
  Crucial for Indian vegetarian diets. **[M]**
- **GI/GL engine** from the **International Tables of GI/GL 2021** (Atkinson et al.; ~4,000 items incl. Indian staples —
  curate from primary values, ⚠️ don't copy the supplementary compilation verbatim). Unlocks real diabetic/PCOS/
  prediabetes planning (per-meal GL cap, low-GI swaps, daily GL rollup). **[L, high strategic value]**
- **Composite-dish engine** inspired by **INDB** — recompute cooked-dish nutrients from raw IFCT items ourselves
  (model the method, ⚠️ don't copy INDB's IFCT-derived values). Improves accuracy of curries/dals. **[L]**

---

## 11. Engagement, export & community — PRD §19 P1/P2

| Feature | Open tool | Effort |
|---|---|---|
| Reminders / meal nudges (offline, scheduled) | `flutter_local_notifications` (BSD-3) | **S** |
| Streaks / badges / habit tracking | local SQLite logic | **S** |
| Intermittent-fasting timer, water tracker | local | **S** |
| Read-aloud recipes (accessibility) | `flutter_tts` (+ Indic TTS) | **S** |
| **Calendar sync** for the 366-day plan | `.ics` via `add_2_calendar` / `ical` | **S** |
| PDF cards + print + OS share | `printing` (Apache-2.0) + `share_plus` (BSD-3) | **S** |
| Plan sharing (deep links / exported JSON) | `app_links` + `share_plus` | **M** |
| **Telegram bot** (daily menu, log-by-chat, reminders) | Telegram Bot API (**free**) | **S** (needs a server) |
| WhatsApp menu push | WhatsApp Cloud API (per-msg since Jul-2025; India utility ~₹0.13, 1k free/mo) | **M** |
| Pantry inventory + leftover-aware planning + meal-prep batching | deterministic engine logic (no external API) | **M** |
| Community recipes | GitHub-PR'd recipe JSON (OSS-native) → later in-app submission + moderation | **M→L** |
| ONDC grocery ordering (open-commerce) | ONDC protocol (needs a network participant) | **L** |

---

## 12. Advanced diet-quality indices & adequacy scores — **net-new analytics depth**

*(deep-research provenance: two OSINT passes verified against authoritative sources — see §13 for the data-source twin.)*

**The single unlock:** IFCT 2017 *already* carries vit A/C/E, folate, K, Mg, Zn, fatty-acid profiles, amino acids
(incl. **leucine**) and phytate/oxalate columns. One extraction job (pull those extra columns into `ifct_local.py`)
turns on most indices below **at once**. Numbers stay engine-computed — reuse the existing NAR/adequacy machinery; the
LLM only narrates.

**Ship-now (no new composition data needed):**
- **MDD-W / MDD-C** dietary diversity (FAO 2021 / WHO-UNICEF 2021) — count distinct food groups/day, ≥5 = adequate.
  Maps **directly onto the existing IFCT A–S groups**. 10-dot waffle + weekly groups-hit line. **[S]**
- **NAR / MAR** (Madden & Yoder 1972) — per-nutrient `min(intake/RDA,1)`; MAR = mean of NARs. **MAR gauge shipped this
  session** (§14); add the per-nutrient NAR bars. **[S]**
- **Protein distribution / leucine threshold** (Mamerow 2014; Moore 2015) — per-meal protein vs ~0.4 g/kg (~25–30 g,
  ~2.5–3 g leucine); evenness = CV across the 5 slots. Small-multiples bars with a threshold line. **[S/M]**
- **Weight trajectory** — **NIH Body Weight Planner / Hall dynamic model** (*Lancet* 2011), explicitly **not** the
  discredited 3500-kcal rule. Projects weight from cumulative energy balance (planned kcal − TDEE). Line + projection
  band + "hit X by date" marker. **[M]**
- **Deficiency-risk score** (ICMR-NIN; lacto-veg B12/Fe literature) — `f(mean NAR, variance, trend)` + diet-type flag.
  Traffic-light tiles. Naturally surfaces the B12 gap the heatmap already shows. **[M]**
- **RDA benchmarking** vs **ICMR-NIN 2020** — %RDA per nutrient (already core to the engine). **[S]**

**Gated on the one IFCT-column extraction (then all unlock together):**
- **HEI-2020** (USDA/NCI) — 13 components scored as **density per 1000 kcal**, 100-pt (9 adequacy + 4 moderation). **[M]**
- **AHEI-2010** (Chiuve 2012) — 11 components × 0–10 = 110. **[M]**
- **NRF9.3** (Drewnowski 2010) — 9 encourage − 3 limit, per 100 kcal → a **"best foods" leaderboard**. **[M]**
- **PHDI** planetary-health diet index (Cacau 2021; **EAT-Lancet 2019** reference) — each food group's grams vs
  EAT-Lancet targets. Diverging bar. **[M]**
- **DII** dietary inflammatory index (Shivappa 2014) — 45 params z-scored → centred percentile → × inflammatory score.
  Diverging bar (pro↔anti-inflammatory). ⚠️ **needs the published global reference-mean table — a data-sourcing
  decision to surface to the user.** **[L]**
- **Food synergy / antagonism** (Hallberg; FAO/WHO 2004) — per-meal **iron × vit-C** enhancer; **Ca / tea / coffee ↔
  non-heme Fe** and **phytate:mineral molar-ratio** inhibitors; fat-soluble vits need dietary fat. Pairing chips +
  warning badges, narrated ("dal + lemon → better iron uptake"). **[M]**

**External reference tables (the two items that most need a sourcing decision):**
- **Glycemic Load** needs a GI table (Intl Tables 2021 / Sydney; curate Indian staples) — `GL = GI × avail-carb/100`.
  (Already flagged in §10.) **[L]**
- **Sustainability footprint** — **Poore & Nemecek 2018 (*Science*)** via OWID (kg CO₂e, L water, m² land per food) →
  stacked bar/meal, weekly treemap, and a **gauge vs the EAT-Lancet per-capita boundary**. Extends §5. **[M]**
- **NFHS-5 population benchmarking** (IIPS 2019–21) — "you vs a typical Indian adult" percentile band. Needs NFHS
  reference distributions. **[L]**
- **Glycemic variability** (CV ≤36% target, ADA 2023; MAGE/CONGA) — **hardware-gated on CGM** (see §13). **[L]**
- *Flag: **ANDI** (Fuhrman) is commercial & not peer-reviewed — cite with that caveat or skip.*

---

## 13. Novel data sources & quantified-self signals — **out-of-the-box, offline-first**

**Cross-cutting rule (unchanged):** every signal only **reweights targets, emphasis and insights** — the Knowledge DB
still owns every gram/mg. Cloud signals are fetched-when-online, cached-with-timestamp, and degrade gracefully;
on-device sources need no network at all.

**On-device & free — via Android Health Connect (local DB, no cloud):**
- **Steps / active-calories → dynamic TDEE** (`StepsRecord`, `*CaloriesBurned`) — replaces the static activity factor in
  the energy target. **The single highest-ROI integration for the existing planner.** **[M]**
- **Body composition** (`Weight`, `BodyFat`, `LeanBodyMass`, `BasalMetabolicRate`) — lean-mass trend →
  protein-per-kg-lean target + recomposition chart. **[M]**
- **Blood pressure** (`BloodPressureRecord`) → DASH-style sodium↓ / potassium↑ emphasis, flags high-sodium dishes;
  slots into the condition-aware profiles. **[M]**
- **Sleep / HRV / resting-HR** (`SleepSessionRecord`, `HeartRateVariabilityRmssdRecord`, `RestingHeartRateRecord`) —
  correlate late/heavy dinners vs sleep quality & morning HRV; **recovery-aware targets** (low-HRV day → magnesium/
  tryptophan dinners, tighter caffeine cutoff). A diet→sleep scatter is genuinely new for a meal planner. **[M]**
  ⚠️ health data — local-only.
- **Menstrual cycle** (`MenstruationFlowRecord`, `OvulationTestRecord`…; open-source **`drip`** as a data-model
  reference) — **cycle-phase nutrition**: iron + vit-C in menstruation, luteal energy bump, Ca/Mg for PMS; phase ring
  over the menu. **[M]** ⚠️ reproductive-health data — strictly local, explicit opt-in.
- **Glucose** (`BloodGlucoseRecord`, if a CGM app writes to Health Connect) — zero-cloud read. **[M]**
- **Hydration + continuous HR** (`HydrationRecord` vs the weather target; `HeartRateRecord` series). **[S]**

**Cloud but keyless & cacheable — the open-meteo family (CC BY 4.0, covers India):**
- **Weather** (open-meteo Forecast, **no key**) — temperature-driven hydration target + warming/cooling/monsoon dish
  nudges; augments Rituva's existing **seasonal-menu** engine with *live* weather, not just calendar season. **[S]**
- **Air quality / AQI** (open-meteo Air-Quality, **no key**; or WAQI / OpenAQ / CPCB with a free key) — high-PM2.5 day →
  **antioxidant / vit-C/E nudge** (amla, guava, citrus, greens). **[S]**
- **UV index** (open-meteo, no key; OpenUV free 50/day) — low UVB window (winter, or UVB blocked by high AQI) is the
  real driver of vit-D deficiency → emphasize dietary D (fortified milk, mushrooms) / discuss supplement. A sun↔diet
  link no nutrition app surfaces. **[S]**

**Self-hosted / partner — glycemic-response analytics:**
- **CGM per-dish postprandial ranking** — **Nightscout** (`cgm-remote-monitor`, AGPL-3.0, self-hosted REST
  `/api/v1/entries.json`; Libre/Dexcom/Medtronic uploaders) or the **Dexcom Developer API** (OAuth2). Build a
  *personalized glycemic ranking of the user's own Knowledge-DB dishes* (spike height + incremental AUC) — powerful for
  the diabetic / condition-aware profiles. **[L]** ⚠️ CGM = PHI; keep local, never upload. *(Freestyle Libre has no
  official self-serve API — community LibreLinkUp clients only, ToU risk.)*

**On-device, maximally sensitive — mirrors the IFCT local-only playbook:**
- **Nutrigenomics** — a 23andMe / raw-DNA export is just an `rsid→genotype` TSV; **parse entirely on-device** against a
  small, self-authored SNP→nutrient table. Actionable SNPs: `rs4988235` (LCT/MCM6 **lactase persistence** — big for a
  dairy-heavy Bihari veg diet), `rs1801133` (MTHFR C677T → folate / leafy-green emphasis), `rs762551` (CYP1A2 →
  caffeine timing & cutoff). SNPs reweight; the engine owns the numbers. ⚠️ **SNPedia is CC BY-NC-SA 3.0
  (non-commercial — like IFCT, never bundle its text into the public repo).** Local-only, explicit consent. **[L]**

**Genuinely novel:**
- **Plant-diversity score** — **American Gut / Microsetta** (UCSD Knight Lab) as *population priors* (not per-user
  sequencing) → nudge toward the "~30 different plants/week" finding + fermented-food emphasis. New fibre-diversity
  gauge. **[M]**
- **Moon phase** — computed **on-device astronomically, no API** → **fasting / vrat-aware planning** (Ekadashi,
  Purnima, Amavasya). Culturally apt for Indian households; unique. **[S]** *(ties into §6 festival/fasting modes.)*
- **Honest negative:** no free pollen API covers India (open-meteo pollen is Europe-only) — don't promise it.

**Top-3 ROI:** steps→dynamic TDEE · CGM per-dish glycemic ranking · nutrigenomic lactase/folate/caffeine reweighting.
**Privacy-critical (local-only, explicit consent):** glucose, genetics, menstrual data.

---

## 14. Advanced analytics visualizations & their animations — **shipped + roadmap**

**Shipped this session** (`insights.dart`; every chart a `CustomPainter` driven by `TweenAnimationBuilder`, every number
from the on-device engine totals):
- **8-axis nutrient-balance radar** (Day) — kcal/protein/carb/fat/fibre/Fe/Ca/B12 vs target; green dots when met, amber
  when short; web sweeps open on mount.
- **100-cell calorie-composition waffle** (Day) — protein/carb/fat energy split, with legend.
- **Mean-Adequacy-Ratio semi-gauge** (Week) — arc eases to value.
- **7×6 week-adherence heatmap** (Week) — day × nutrient, on-target / close / short; opacity cascade.
- **Count-up ring gauges** (Day) — values tween from 0 on mount.
- *(Pre-existing, now animated: ring gauges, macro donut, trend bars, budget bars.)*

**Roadmap (viz → metric it serves → the animation that fits):**

| Visualization | Serves (from §12/§13) | Entrance animation |
|---|---|---|
| **Bullet graphs** (AAA-accessible) | HEI / AHEI / NRF9.3 components, NFHS percentile band | measure bar grows; qualitative bands fade in |
| **Diverging bar** (centred at 0) | DII (pro↔anti-inflammatory), PHDI over/under target | bars grow outward from centre |
| **Line + projection band** | weight trajectory, adherence forecast (EWMA) | path draws L→R, band fades, goal marker drops |
| **Small-multiples bars** | protein distribution + leucine threshold line | staggered per meal; threshold slides in |
| **Stacked area** | carb / energy timing across the day | areas rise + crossfade on day-switch |
| **Treemap** | sustainability footprint by food | tiles scale-in (area = impact) |
| **Gauge vs boundary** | footprint vs EAT-Lancet per-capita budget | arc eases to value |
| **AGP percentile band** | CGM glucose (median + IQR envelope) | band draws L→R |
| **Food leaderboard bar** | NRF9.3 / ANDI "best foods", GL ranking | bars grow + reorder |
| **Scatter + trend line** | diet→sleep / diet→HRV correlation | points fade in, trend line draws |
| **Calendar heatmap** (GitHub-style) | 366-day adherence / streak | cells cascade by week |
| **Celebration micro-animation** | goal-met / streak milestone | confetti or ring-burst |

**Animation guardrails** (from `ui-ux-pro-max`): 150–300 ms micro / ≤400 ms complex; **transform + opacity only**
(never width/height/top/left); ease-out on enter, exit ~60–70% of enter; stagger lists 30–50 ms; **respect
`prefers-reduced-motion`**; never block input; charts must not cause layout reflow / CLS.

---

## 15. Suggested build order (maps to PRD §19)

1. **P0 — turn the generator into an app:** food logging loop (barcode via OFF + voice via Vosk) → adherence it already
   computes; **Health Connect** measured TDEE; reminders/streaks. *(§1, §2, §11)*
2. **P1 — win the Indian condition market:** the **S-effort condition modes** (hypertension, pregnancy, celiac,
   dyslipidemia, PCOS) + **lab-driven targets** + **micronutrient dashboard**; the **assistant's action-taking**;
   **price-aware planning** (Agmarknet). *(§3, §4, §9, §10)*
3. **P1/P2 — differentiate:** GI/GL diabetic engine; **festival/fasting modes**; **sustainability score**;
   **region-aware deficiency defaults**; **Hindi + regional languages**. *(§5, §6, §7, §8, §10)*
4. **P2 — reach & delight:** photo logging; Telegram/WhatsApp; community recipes; calendar/PDF export; on-device
   open-weights assistant. *(§1, §11, §9)*

**Analytics-depth track (parallel, mostly engine-only — §12/§13/§14):** the cheapest big win is the **one IFCT-column
extraction** (unlocks HEI/AHEI/NRF9.3/DII/PHDI/food-synergy/leucine together) plus the **ship-now** scores that need no
new data (MDD-W, NAR bars, protein distribution, weight trajectory, deficiency-risk). On the signal side, **steps →
dynamic TDEE** (Health Connect) is the highest-ROI integration for the existing planner. Two items need a data-sourcing
decision first: the **DII global reference table** and **NFHS-5 distributions**.

**Two licensing traps to never trip:** (1) don't ship IFCT/ICMR-NIN documents or INDB values in the public build —
encode numbers only; (2) non-commercial data (FAO, Recipe1M/FoodSeg103) and no-redistribution APIs (Nutritionix,
Edamam, Spoonacular, Sydney GI) are online-lookup at most. USDA + Open Food Facts + GODL-India + OWID footprints +
MIT/Apache AI models are the redistributable core.
