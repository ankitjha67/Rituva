# Rituva — Working Context & Memory

> Living document. Updated at the end of every work session/phase. Read this first
> when resuming work; it records what is built, what is verified, and what is next.
> Spec of record: `PRD.md` (v1.5). Visual source of truth: `design/prototype.html`.
> Repo: **github.com/ankitjha67/Rituva** (public). Demo profiles are genericized (Aarav/Diya).

## North-star constraints (never break these)

- **LLM proposes, deterministic engine disposes.** Every nutrient number is computed
  from the Knowledge DB (`knowledge.py`, IFCT 2017 / USDA, each row `source`-tagged).
  No code path may let an LLM supply a number. Unknown food ⇒ `UnknownFoodError`.
- **Zero-dependency core.** `domain/nutrition/targets/planner/knowledge/context` run
  on the stdlib alone. Optional deps (fastapi, langgraph…) degrade gracefully.
- **Tests must stay green:** `python tests/test_core.py` (9/9) + `pytest -q` (14/14).
- Precedence (PRD §6.5): doctor_diet > known_targets > computed.

## Environment (this machine)

- Windows, Git Bash. Python 3.13.13. fastapi 0.139 + pydantic + pytest 9.1 + openpyxl installed.
- **langgraph NOT installed** → `graph.py` uses its sequential fallback (by design).
- No Postgres server, no psycopg → SQLite is the only runnable backend here.
- Pushed to **github.com/ankitjha67/Rituva** (public). GitHub Actions build the APK (Flutter is
  absent locally). `rituva.db` and `.claude/` are gitignored (`RITUVA_DB` overrides the DB path).

## Phase plan (agreed with user)

| Phase | Scope | Status |
|---|---|---|
| A | Knowledge DB expansion (variety to production-grade) | ✅ DONE (verified 2026-07-25) |
| B | Postgres + hybrid RAG + LangGraph memory | ✅ DONE (2026-07-25) |
| C | P0 feedback loop: food logging + adherence (actuals vs plan) | ✅ DONE (2026-07-25) |
| D | Android/PWA frontend on the approved design vs live API | ✅ DONE — web PWA (2026-07-25). Native Android = future track. |

**All four agreed phases (A–D) are complete.** Post-D backlog delivered this session:
**grocery list**, **.xlsx export**, and a **native Android (Flutter) scaffold** (`mobile/` — NOT
compiled here; no Flutter SDK in the sandbox). Remaining §18.4/§19 backlog: compile/ship the
Android app, live Postgres, PDF export, logging integrations (barcode/photo/wearables/CGM),
adaptive targets, notifications.

## What's built (module → status → notes)

- `domain.py` ✅ enums/dataclasses: Member, Recipe, FoodComposition, DayPlan, ValidationReport…
- `knowledge.py` ✅ **95 foods, 94 recipes** (Phase A: N/S/E/W + omnivore egg/chicken/fish),
  GUIDELINE_RULES (cited), FREQUENCY_POLICY, EQUIVALENCE_CLASSES, PULSE_IDS, 2 seed members.
  Referential integrity verified: no dangling food refs.
- `nutrition.py` ✅ BOM × composition math, `recipe_breakdown`, iso-distance/delta labels.
- `targets.py` ✅ BMI (Asian), Mifflin BMR, TDEE, macro/fibre targets, doctor/known precedence.
- `planner.py` ✅ Ledger (dish min-gap + hero/pulse/region caps), greedy planner with grain
  scaling to kcal target + protein grow-loop, validator + DQS, iso-nutrient alternatives.
  366-day plan: **364/366 on target**, caps held (test-covered).
- `adherence.py` ✅ Phase C: actuals vs plan vs targets, recipe expansion for logging.
- `grocery.py` ✅ aggregate a plan's ingredient BOM → categorized, household-scaled shopping list (§11.4).
- `export.py` ✅ `.xlsx` workbook (Week + Grocery + Targets) via openpyxl — Excel parity (§11.3, goal G7).
- `gateway.py` ✅ OpenAI-compatible providers (NVIDIA/OpenAI/Ollama), key-only auto-discovery,
  FallbackRouter → NoLLM. (Untested against live keys in this env.)
- `graph.py` ✅ Pipeline compute_targets → **retrieve** → plan → explain. The retrieve node
  pulls cited guideline rules; `run()` accepts a store connection so long-term memory
  is applied before planning. LangGraph when installed, sequential fallback otherwise.
- `context.py` ✅ system clock → date/season/current-meal/greeting (PRD §7.8).
- `store.py` ✅ Dual-backend persistence: SQLite default; optional Postgres when
  `RITUVA_DB=postgresql://...` and `psycopg` is installed. Tables: members, plans,
  user_memory, intake. JSON (de)serialization helpers. `_DB` wrapper keeps callers backend-agnostic.
- `memory.py` ✅ `apply_memory` folds never/dislike into member excludes; `VALID_KINDS`.
- `retrieval.py` ✅ Hybrid RAG: BM25 sparse + TF-IDF cosine dense stand-in, RRF-fused over
  the cited guideline rules and the recipe corpus. Every hit carries its source.
- `api.py` ✅ FastAPI endpoints:
  - `/health` / `/context` / `/members` (CRUD) / `/members/{id}/targets`
  - `/plans` (POST creates a validated plan; memory is applied, provenance carries citations)
  - `/plans/{id}` / `/plans/{id}/day/{day}` / `/members/{id}/alternatives`
  - `/members/{id}/memory` (GET/POST/DELETE) — long-term memory
  - `/retrieval` (hybrid search) / `/guideline-rules` (cited rule base)
  - `/members/{id}/intake` (GET/POST) / `/members/{id}/adherence` — Phase C feedback loop
  - `/plans/{id}/grocery` (categorized, household-scaled) / `/plans/{id}/export.xlsx` (download)
- `cli.py` ✅ full demo: targets, 5-slot days, frequency summary, `--alt` swaps, provenance.
- `web/` ✅ **PWA frontend (Phase D)**: `index.html` shell + `styles.css` (approved
  saffron/ink palette, Bricolage/Hanken) + `app.js` (vanilla client, no framework) +
  `manifest.webmanifest` + `sw.js` (offline shell) + `icon.svg` (My Plate ring). Served by
  FastAPI at **`/app`** (StaticFiles mount + `/`→`/app/` redirect + CORS in `api.py`), so
  one `uvicorn` serves API + app. Views: **Today** (calorie ring + macro bars + cited rule +
  meal cards → tap-to-swap), **Plan** (week), **Health** (targets + conditions + never/dislike
  memory add/remove), **Insights** (adherence: actual vs plan vs target + "mark eaten"),
  **Profile** (member switch, engine/provenance, sources sheet). Verified in-browser against
  the live server — all views render live data, no console errors.
- `mobile/` ✅ **native Android/iOS app (Flutter)**: `lib/` = `main.dart` (shell + theme + state +
  Profile w/ **Server-URL setting** + **offline banner**) · `theme.dart` (approved palette) ·
  `api.dart` (**offline-first** HTTP client — falls back to bundled `assets/demo.json`, on-device
  context, `shared_preferences` server URL) · `screens/today.dart` (calorie ring CustomPaint +
  macros + meals + swap sheet) · `screens/plan.dart` (week + grocery sheet) · `screens/health.dart`
  (targets + conditions + never/dislike memory); `assets/demo.json` (engine-built demo bundle,
  DB-grounded, mirrors API shapes); `assets/icon/` (My Plate ring launcher source); `pubspec.yaml`
  (adds `shared_preferences` + `flutter_launcher_icons`). **Built as an APK in CI** (Flutter SDK
  absent locally). Emulator base `http://10.0.2.2:8000`; physical devices set a Server URL in
  Profile or bake `RITUVA_API`. **INTERNET permission** + adaptive icon injected by CI. Fresh
  install with no server → shows the offline demo, not an error.
- `tests/` ✅ `test_core.py` (9 tests, standalone) + `test_api.py` (5 tests: smoke · memory/retrieval ·
  intake/adherence · PWA-serve · grocery/export).

## What's left (backlog, PRD-mapped)

- **Phase D web PWA: ✅ DONE** (`web/`) + **native Android (Flutter): ✅ built as an APK in CI**
  (`mobile/`) with **offline-first demo**, **Server-URL setting**, **INTERNET permission**, and the
  **My Plate ring adaptive icon**. Remaining frontend: Insights/Discover screens; richer online sync;
  in-app light-theme toggle; hi-fi polish; Play/App-Store submission.
- **DONE since:** grocery-list engine + endpoint + PWA sheet (`grocery.py`); `.xlsx` export
  (`export.py`, `/plans/{id}/export.xlsx`, download button in the app).
- **Later (PRD §18.4/§19):** PDF export, OR-Tools optimizer, fuller life-stage/condition packs,
  barcode/photo logging, wearables/CGM, adaptive targets, notifications, real embedding/pgvector
  dense retrieval, native Android (see below).
- **Postgres integration:** store dual-backend is implemented but not integration-tested
  against a live server (none in this environment). The SQLite path is fully tested.

## Verification commands

```bash
python tests/test_core.py         # 9/9
python -m pytest tests/ -q        # 14 passed
python -m rituva.cli --member aarav --days 7 --alt
uvicorn rituva.api:app --reload   # API + Swagger at /docs; PWA at http://localhost:8000/app/
```

## Session log

- **2026-07-25 (Claude Code):** Phase A done — KB expanded 60→95 foods, 54→94 recipes;
  366-day plan 364/366 on target, zero thin-library forced repeats; tests green.
  Started Phase B/C shared store pieces: `store.py` +user_memory/intake tables,
  `memory.py`, `retrieval.py` (BM25).
- **2026-07-25 (Kimi):** Re-read PRD + whole codebase; verified state (tests 7/7,
  KB integrity, 364/366 year plan); created this file. Completed Phase B:
  hybrid retrieval (BM25+TF-IDF+RRF), dual-backend store (SQLite+Postgres),
  memory endpoints, retrieve node in graph, cited rules in provenance.
  Completed Phase C: `adherence.py`, intake logging API with recipe expansion,
  adherence endpoint (actuals vs plan vs targets), tests. Tests green: 12/12.
- **2026-07-25 (Claude Code, resume):** Re-read PRD + full codebase; independently
  re-verified Kimi's Phase B/C (9/9 core, 12 pytest, all imports, CLI, 366-day plan).
  Built **Phase D**: `web/` PWA on the approved design, served by FastAPI at `/app`
  (StaticFiles mount + `/`→`/app/` + CORS). Ran the live server (uvicorn :8099) and verified
  all views in-browser against the API — Today/Health/Insights/Swap render live data;
  adherence, iso-nutrient alternatives, and never/dislike memory all work; no console errors.
  Added a PWA-serve smoke test → **pytest 13/13**, core 9/9. All four phases (A–D) complete.
- **2026-07-25 (Claude Code, cont.):** Post-Phase-D backlog: built **grocery** (`grocery.py`
  + `/plans/{id}/grocery` + PWA sheet) and **.xlsx export** (`export.py` +
  `/plans/{id}/export.xlsx` + download button). Verified live (43-item list, 8.4 KB xlsx) →
  **pytest 14/14**. Added `food_id` to serialized plan ingredients so grocery aggregates by food.
- **2026-07-25 (Claude Code, cont.):** Built the **native Android app (Flutter)** in `mobile/`
  (main + theme + api client + Today/Plan/Health/Profile screens on the approved palette,
  consuming the same API). Flutter SDK is absent from the sandbox, so it is delivered as
  source (brace-balanced, M3-idiomatic) with run steps in `mobile/README.md` — not compiled here.
  **All agreed work (Phases A–D + Grocery + .xlsx export + Android scaffold) is now delivered.**
- **2026-07-25 (Claude Code, GitHub upload):** Prepared + pushed the repo to
  **github.com/ankitjha67/Rituva** (public). Added `.gitignore`; **GitHub Actions** — `tests.yml`
  (pytest) + `build-apk.yml` (builds the Flutter APK in CI → rolling `latest` prerelease + attaches
  versioned APKs to Releases; first run ~15–20 min, caches after). `api.dart` reads `RITUVA_API`
  via `--dart-define` (set a repo Variable to bake a backend URL). README badges + APK download
  section. **Genericized ALL personal data** for the public repo (seed profiles → Aarav/Diya with
  generic conditions; design mockups; PRD persona; demo id ankit→aarav / wife→diya) — pytest 14/14.
  The real household profile lives only in local `.claude/` memory (gitignored).
- **2026-07-25 (Claude Code, APK live):** CI green. Backend-tests ✅. Fixed the APK workflow
  (moved the Gradle cache to after `flutter create`, since no gradle files exist at `setup-java`
  time). **APK built successfully in GitHub Actions** → `Rituva-b3.apk` (~47 MB) attached to the
  **`latest`** prerelease and the **`v0.1.0`** release. Direct download:
  https://github.com/ankitjha67/Rituva/releases/latest . Future pushes/releases rebuild it
  automatically. **GitHub upload + APK task COMPLETE.** Next queued: Flutter Insights/Discover screens.
- **2026-07-25 (Claude Code, APK bugfix + icon):** User installed `Rituva-b3.apk` on a **physical
  phone** → error "Cannot reach the Rituva API … Operation not permitted, errno=1 @ 10.0.2.2:8000".
  Two bugs: (1) release APK lacked the **INTERNET permission** (Flutter injects it only into debug
  builds → EPERM on socket create) — now added in the CI manifest sed; (2) `10.0.2.2` is emulator-only
  and there was no backend. Fixed by making the client **offline-first**: bundled `mobile/assets/demo.json`
  (built by `scratchpad/generate_demo.py` via the real engine — Aarav+Diya, 7-day plans, grocery,
  all DB-grounded, exact API shapes), transparent fallback in `api.dart` on any network error,
  on-device context mirroring `context.py`, an **offline banner**, and an in-app **Server URL** setting
  (`shared_preferences`) in Profile; server-only actions (swap, save preference) show a clear message
  offline. Designed the **Rituva "My Plate ring" app icon** (`scratchpad/make_icons.py`, PIL) →
  adaptive Android launcher via **flutter_launcher_icons** (CI step) + PWA/website PNGs (192/512
  maskable, apple-touch) wired into `manifest.webmanifest` + `index.html`. Bumped app to 0.1.1+2.
  Pushed → CI building the fixed, icon'd APK (run 30148699269).
- **2026-07-25 (Claude Code, big phases):** Fixed **Plan-tab tap** (day→meals sheet), **snake_case UI
  labels** (root cause: citation carried the raw rule-id prefix — split search vs `display` text in
  `retrieval.py`; humanized slots/conditions/source), and a **planner determinism bug** (`hash()`→
  `zlib.crc32`, since str hash is PYTHONHASHSEED-salted → flaky tests + non-reproducible demo). Added
  **iOS** (platform-aware base URL, opaque icon, `build-ios.yml` on macOS, ATS; CI scaffolds both
  platforms so flutter_launcher_icons finds them). **IFCT 2017 ingested** (`C:\Users\ankit\Downloads\
  IFCT2017.pdf`, 585pp) via coordinate-aware fitz parser (`scratchpad/ifct_extract.py` +
  `generate_ifct_local.py`) → **518 foods → `rituva/ifct_local.py` (GITIGNORED, personal-use per IFCT
  licence — see [[nutrition-source-documents]]; NEVER commit)**; KB now **601 foods** locally.
  **680 recipes** generated from home-cooking templates (`generate_recipes_local.py`) →
  `rituva/recipes_local.py` (gitignored) → **774 recipes** locally; knowledge.py loads both if present
  (curated wins; CI/public falls back to 95 foods / 94 recipes). **GCP deploy assets**: `Dockerfile` +
  `.dockerignore` (keeps IFCT/secrets out of the image) + `deploy/README.md` (Cloud SQL + Cloud Run +
  Secret Manager runbook). **NVIDIA NIM wired**: `api.py` reads `RITUVA_LLM_PROVIDER`/`NVIDIA_API_KEY`
  → graph.run; `/health` reports foods/recipes/llm; `scripts/llm_smoketest.py`. **NIN permission email**
  drafted (`docs/NIN-IFCT-permission-request.md`, user to send). **Flutter Insights + Discover** screens
  (+ `GET /recipes`; 6-tab nav). CI: build-apk skips backend/docs paths. Tests 9/9 + 14 throughout.
  **Local-only data (ifct_local.py, recipes_local.py) is gitignored — verified never staged.**
