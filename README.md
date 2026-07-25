# Rituva

A guideline-grounded, seasonal, region-aware, **LLM-agnostic** nutrition & menu planner.
It turns a person's profile (age, BMI, health/lab measurements, conditions, any
doctor-prescribed diet, regional taste) into daily / weekly / monthly / yearly menus
that meet published dietary guidelines — **without ever inventing a nutrition number.**

Full specification: [`PRD.md`](PRD.md). Visual design: [`design/prototype.html`](design/prototype.html).

[![Backend tests](https://github.com/ankitjha67/Rituva/actions/workflows/tests.yml/badge.svg)](https://github.com/ankitjha67/Rituva/actions/workflows/tests.yml)
[![Build Android APK](https://github.com/ankitjha67/Rituva/actions/workflows/build-apk.yml/badge.svg)](https://github.com/ankitjha67/Rituva/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/github/v/release/ankitjha67/Rituva?include_prereleases&label=latest%20APK)](https://github.com/ankitjha67/Rituva/releases/latest)

---

## The one rule that shapes the architecture

> **The LLM proposes; the deterministic engine disposes.**
> Every nutrient value is *computed* from the Knowledge DB (IFCT 2017 composition),
> never produced by a language model. An ingredient missing from the DB is flagged,
> not fabricated. See PRD §9.2.

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

## What runs today (this scaffold)

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
| .xlsx export (Excel parity, G7) | ✅ | `rituva/export.py` (+ API + download buttons) |
| Native Android/iOS (Flutter) scaffold | ✅ uncompiled | `mobile/` (see `mobile/README.md`) |
| Live Postgres/pgvector · PDF export · barcode/wearables | ⏳ next | — (PRD §12, §18.4, §19) |

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

The APK is built **in GitHub Actions** (no local Android/Flutter toolchain needed).

- **Direct download:** the newest build is always attached to the **[latest release](https://github.com/ankitjha67/Rituva/releases/latest)** as `Rituva-*.apk`. On Android, enable "install unknown apps" and open the file.
- **Update flow:** every push/merge to `main` rebuilds the APK and refreshes the `latest` prerelease; publishing a versioned **Release** attaches a versioned APK to it. The first CI run takes ~15–20 min; later runs are faster (Flutter + Gradle caches). *There is no "partial" APK build — each version is a full APK, but caching makes rebuilds quick and each release carries only your new changes.*
- **True over-the-air code push** (patch the running app without installing a new APK) is available via **[Shorebird](https://shorebird.dev)** for Flutter — ask to wire it up once you have a Shorebird token (added as a repo secret).
- **Point the app at your backend:** set a repository **Variable** `RITUVA_API` (e.g. `https://your-host`) to bake it into the APK; otherwise it defaults to the emulator URL `http://10.0.2.2:8000`. Deploy `rituva.api:app` anywhere (`uvicorn`/Docker) and set that URL.
