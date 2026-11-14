# Rituva

A guideline-grounded, seasonal, region-aware, **LLM-agnostic** nutrition & menu planner.
It turns a person's profile (age, BMI, health/lab measurements, conditions, any
doctor-prescribed diet, regional taste) into daily / weekly / monthly / yearly menus
that meet published dietary guidelines — **without ever inventing a nutrition number.**

Full specification: [`PRD.md`](PRD.md). Visual design: [`design/prototype.html`](design/prototype.html).

[![Backend tests](https://github.com/ankitjha67/Rituva/actions/workflows/tests.yml/badge.svg)](https://github.com/ankitjha67/Rituva/actions/workflows/tests.yml)
[![Build Android APK](https://github.com/ankitjha67/Rituva/actions/workflows/build-apk.yml/badge.svg)](https://github.com/ankitjha67/Rituva/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/badge/latest%20APK-download-2ea44f?logo=android&logoColor=white)](https://github.com/ankitjha67/Rituva/releases/latest)

---

## The one rule that shapes the architecture

> **The LLM proposes; the deterministic engine disposes.**
> Every nutrient value is *computed* from the Knowledge DB (food-composition data),
> never produced by a language model. An ingredient missing from the DB is flagged,
> not fabricated. See PRD §9.2.

> **Knowledge base & data licence.** This public repo ships a **curated composition
> database (~95 foods / 94 recipes)** that is safe to redistribute. The full
> **IFCT 2017** tables (ICMR-NIN; ~601 foods / 1302 recipes) are **personal-use
> licensed** — they are *not* included here and must not be, without written NIN
> permission. The engine loads them automatically if you place the extraction locally
> (`rituva/ifct_local.py`, gitignored); otherwise it falls back to the curated set. So
> a clone builds and runs out of the box on the public data.

## Quick start (no dependencies, no API key)

```bash
python -m rituva.cli --member aarav --days 7 --alt
```

You'll get a validated 7-day plan: BMI/BMR/targets (cited to DGI 2024), five meals a
day, per-day energy/macros vs target, a frequency-regulation summary, and — with
`--alt` — iso-nutrient alternatives with a per-ingredient breakdown straight from the
DB (e.g. *Chickpeas 55 g → protein 10.6 g · carb 31 g · fibre 8.9 g [IFCT 2017]*).

More examples:

```bash
python -m rituva.cli --member diya --days 7 --regions south,east   # blend regions
python -m rituva.cli --member aarav --days 366                     # full-year, all unique
python -m rituva.cli --member aarav --provider nvidia --api-key "$NVIDIA_API_KEY"
```

Run the tests (standalone or via pytest):

```bash
python tests/test_core.py         # no pytest needed
pytest -q                         # if pytest is installed
```

Run the full app — REST API **and** the installable PWA on the approved design:

```bash
uvicorn rituva.api:app --reload   # API docs at /docs · app at http://localhost:8000/app/
```

## What runs today

| Area | Status | Module |
|---|---|---|
| Domain model | ✅ | `rituva/domain.py` |
| Knowledge DB (foods, recipes, cited rules, frequency policy) | ✅ seed | `rituva/knowledge.py` |
| Nutrition math (BOM × composition) | ✅ | `rituva/nutrition.py` |
| Target engine (BMI/BMR/TDEE/macros + doctor/known precedence) | ✅ | `rituva/targets.py` |
| Deterministic planner (uniqueness, frequency caps, grain balancing, alternatives) | ✅ | `rituva/planner.py` |
| Validator + Diet-Quality score | ✅ | `rituva/planner.py` |
| LLM gateway (NVIDIA/OpenAI/Ollama, key-only, auto-discovery, graceful fallback) | ✅ | `rituva/gateway.py` |
| Orchestration (LangGraph, with dependency-free fallback) | ✅ skeleton | `rituva/graph.py` |
| CLI | ✅ | `rituva/cli.py` |
| System context (date/time/season/current-meal) | ✅ | `rituva/context.py` |
| REST API (FastAPI) + SQLite persistence | ✅ | `rituva/api.py` · `rituva/store.py` |
| Hybrid RAG (BM25+TF-IDF, RRF) + long-term memory | ✅ | `rituva/retrieval.py` · `rituva/memory.py` |
| Food logging + adherence (actuals vs plan) | ✅ | `rituva/adherence.py` (+ API) |
| PWA frontend on the approved design (served at `/app`) | ✅ | `web/` |
| Grocery list (categorized, household-scaled) | ✅ | `rituva/grocery.py` (+ API + PWA/app) |
| .xlsx export (Excel parity, G7) | ✅ | `rituva/export.py` (+ API + PWA) |
| Native Android app (Flutter) — **standalone**: on-device engine, menus/swaps/recipes/grocery, animated analytics, NVIDIA assistant, **on-device PDF/print export**, and **barcode → Open Food Facts** lookup, all offline | ✅ | `mobile/` (see `mobile/README.md`) |
| Live Postgres/pgvector · wearables (Health Connect) · OTA code-push | ⏳ next | — (PRD §12, §18.4, §19) |

## How the requirements map to code

- **Regional N/S/E/W preferences, blendable** → `Member.region_prefs`, `--regions`, region-day caps.
- **Doctor-prescribed diet / known targets are authoritative** → `targets.effective_targets` precedence (PRD §6.5).
- **No repetition; frequency regulated & interchangeable** → `planner.Ledger` (dish min-gap + per-hero/pulse/region weekly caps) + equivalence classes (PRD §8.5).
- **Iso-nutrient alternatives, each with DB numbers** → `planner.DeterministicPlanner.alternatives` + `nutrition.recipe_breakdown` (PRD §11.6).
- **Any LLM, key-only, graceful fallback** → `gateway.build_gateway` / `FallbackRouter` (PRD §10.5).
- **Advanced RAG + LangGraph + memory** → `graph.py` skeleton (RAG/memory nodes stubbed for the DB-backed build, PRD §9.7).

## Project layout

```
rituva/
  domain.py       # enums + dataclasses (the vocabulary)
  knowledge.py    # seed Knowledge DB: FOODS, RECIPES, GUIDELINE_RULES, FREQUENCY_POLICY, SEED_MEMBERS
  nutrition.py    # compute nutrients from BOM × composition; iso-nutrient distance
  targets.py      # BMI/BMR/TDEE + guideline targets + doctor/known precedence
  planner.py      # Ledger (uniqueness+frequency), DeterministicPlanner, validator
  gateway.py      # LLM providers, auto-discovery, FallbackRouter
  graph.py        # pipeline (LangGraph or sequential fallback)
  retrieval.py    # hybrid RAG (BM25 + TF-IDF, RRF-fused) over cited rules + recipes
  memory.py       # per-user never/dislike/like → shapes future plans
  adherence.py    # actuals vs plan vs targets (logging feedback loop)
  context.py      # system date/time/season/current-meal detection
  store.py        # SQLite (default) / Postgres persistence
  api.py          # FastAPI REST layer (+ mounts the PWA at /app)
  cli.py          # runnable CLI
web/              # PWA frontend on the approved design (served at /app)
mobile/           # Flutter standalone Android app (on-device engine; see mobile/README.md)
scripts/export_kb.py  # build the bundled KB (`--public` = curated set only, no IFCT)
tests/test_core.py · tests/test_api.py
CONTEXT.md        # living build tracker — read this to resume
PRD.md            # full product spec (v1.5)
design/           # approved visual prototype (all tabs + web)
```

## Not medical advice

Rituva provides guideline-based general nutrition education, not medical nutrition
therapy. Therapeutic/condition modes are advisory and prompt you to confirm with a
clinician. See PRD §13.2.

## Download the Android app (APK) & how updates work

The APK is built **in GitHub Actions** (no local Android/Flutter toolchain needed) and
runs **fully standalone** — planning, swaps, recipes, grocery lists and animated
analytics are all computed on the phone, offline. No server, no account.

- **Direct download:** the newest build is attached to the **[latest release](https://github.com/ankitjha67/Rituva/releases/latest)** as `Rituva-*.apk`. On Android, enable "install unknown apps" and open the file. It ships the public curated library (~95 foods / 94 recipes).
- **Bring your own assistant key:** the in-app chat assistant runs **directly on NVIDIA**, no server. Get a free key at [build.nvidia.com](https://build.nvidia.com) and paste it in **Profile → Assistant** (stored only on your phone). Leave it blank and the deterministic engine still does everything except free-form chat.
- **Update flow:** every push/merge to `main` that touches `mobile/**` rebuilds the APK and refreshes the `latest` prerelease. The first CI run takes ~15–20 min; later runs are faster (Flutter + Gradle caches).
- **Optional dev backend:** the app needs no server, but a developer can bake one in with the repo **Variable** `RITUVA_API` (e.g. `https://your-host`) and deploy `rituva.api:app` (`uvicorn`/Docker). There is no in-app server setting.
- **True over-the-air code push** (patch the running app without a new APK) is possible via **[Shorebird](https://shorebird.dev)** once a Shorebird token is added as a repo secret.
