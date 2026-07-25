"""REST API (FastAPI) — PRD §12.5. Reuses the deterministic engine and persists to
SQLite via `store`. Nutrient numbers in every response come from the Knowledge DB.

Run:   uvicorn rituva.api:app --reload
Docs:  http://localhost:8000/docs
"""
from __future__ import annotations

import os
import uuid
from datetime import date
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from . import KB_VERSION, __version__, graph, memory, store
from .adherence import adherence, expand_recipe_items
from .context import detect
from .knowledge import FOODS, GUIDELINE_RULES, RECIPES, SEED_MEMBERS
from .nutrition import make_component, recipe_breakdown, UnknownFoodError
from .planner import DeterministicPlanner, Ledger, season_for_month
from .retrieval import retrieve
from .targets import targets_report
from .grocery import aggregate as grocery_aggregate
from .export import plan_to_xlsx
from fastapi.responses import Response

# LLM config from the environment (optional). Only the friendly explanation uses the
# LLM; every nutrient number is computed from the Knowledge DB regardless of provider.
_LLM_PROVIDER = os.environ.get("RITUVA_LLM_PROVIDER", "none")
_LLM_KEY = (os.environ.get("NVIDIA_API_KEY") or os.environ.get("OPENAI_API_KEY")
            or os.environ.get("RITUVA_API_KEY", ""))

app = FastAPI(title="Rituva API",
              description="Guideline-grounded, seasonal, LLM-agnostic menu planner. "
                          "All nutrient values are computed from the Knowledge DB, never an LLM.",
              version=__version__)


def _conn():
    return store.connect()


@app.on_event("startup")
def _seed_members():
    conn = _conn()
    try:
        if not store.list_members(conn):
            for m in SEED_MEMBERS.values():
                store.save_member(conn, m)
    finally:
        conn.close()


# ---- schemas ----
class MemberIn(BaseModel):
    id: str
    name: str
    sex: str
    age: int
    weight_kg: float
    height_cm: float
    pal: float = 1.4
    goal: str = "maintain"
    diet_type: str = "lacto_veg"
    region_prefs: list = []
    conditions: list = []
    excludes: list = []
    known_targets: Optional[dict] = None
    doctor_diet: Optional[dict] = None


class PlanIn(BaseModel):
    member_id: str
    days: int = 7
    start: Optional[str] = None


class MemoryIn(BaseModel):
    kind: str                      # never | dislike | like
    value: str                     # food_id / hero / tag the user rejected or loved


class IntakeItem(BaseModel):
    food_id: Optional[str] = None
    recipe_id: Optional[str] = None
    qty_g: Optional[float] = None
    scale: Optional[float] = 1.0


class IntakeIn(BaseModel):
    date: str
    slot: Optional[str] = None
    items: List[IntakeItem]


# ---- routes ----
@app.get("/health")
def health():
    return {"status": "ok", "version": __version__, "kb": KB_VERSION,
            "foods": len(FOODS), "recipes": len(RECIPES), "llm": _LLM_PROVIDER}


@app.get("/context")
def context():
    """Date / time / season / current-meal auto-detected from the system clock (PRD §7.6)."""
    c = detect()
    return {"today": c.today.isoformat(), "time": c.now.strftime("%H:%M"),
            "season": c.season.value, "current_slot": c.current_slot.value,
            "greeting": c.greeting}


@app.get("/members")
def members():
    conn = _conn()
    try:
        return [store.member_to_dict(m) for m in store.list_members(conn)]
    finally:
        conn.close()


@app.post("/members")
def create_member(m: MemberIn):
    conn = _conn()
    try:
        mem = store.member_from_dict(m.model_dump())
        store.save_member(conn, mem)
        return store.member_to_dict(mem)
    finally:
        conn.close()


@app.get("/members/{member_id}")
def read_member(member_id: str):
    conn = _conn()
    try:
        m = store.get_member(conn, member_id)
    finally:
        conn.close()
    if not m:
        raise HTTPException(404, "member not found")
    return store.member_to_dict(m)


@app.get("/members/{member_id}/targets")
def read_targets(member_id: str):
    conn = _conn()
    try:
        m = store.get_member(conn, member_id)
    finally:
        conn.close()
    if not m:
        raise HTTPException(404, "member not found")
    t, info = targets_report(m)
    return {"anthropometry": info, "targets": store.targets_to_dict(t)}


@app.post("/plans")
def create_plan(p: PlanIn):
    conn = _conn()
    try:
        m = store.get_member(conn, p.member_id)
        if not m:
            raise HTTPException(404, "member not found")
        start = date.fromisoformat(p.start) if p.start else detect().today
        # graph.run folds long-term memory into exclusions, retrieves the cited
        # rules for provenance, plans deterministically, then explains (PRD §9.7).
        state = graph.run(m, start, p.days, provider=_LLM_PROVIDER, api_key=_LLM_KEY, conn=conn)
        t = state.targets
        plan = state.plan
        days = [store.day_to_dict(dp, rep) for dp, rep in plan]
        plan_id = uuid.uuid4().hex[:12]
        payload = {
            "plan_id": plan_id, "member_id": m.id, "start": start.isoformat(),
            "days_count": p.days, "targets": store.targets_to_dict(t), "days": days,
            "summary": {"on_target": sum(1 for _, r in plan if r.in_tolerance),
                        "avg_dqs": round(sum(r.dqs for _, r in plan) / len(plan))},
            "provenance": {"kb": KB_VERSION, **state.provenance,
                           "citations": state.citations},
        }
        store.save_plan(conn, plan_id, m.id, payload, detect().now.isoformat())
        return payload
    finally:
        conn.close()


@app.get("/plans/{plan_id}")
def read_plan(plan_id: str):
    conn = _conn()
    try:
        pl = store.get_plan(conn, plan_id)
    finally:
        conn.close()
    if not pl:
        raise HTTPException(404, "plan not found")
    return pl


@app.get("/plans/{plan_id}/day/{day}")
def read_day(plan_id: str, day: str):
    conn = _conn()
    try:
        pl = store.get_plan(conn, plan_id)
    finally:
        conn.close()
    if not pl:
        raise HTTPException(404, "plan not found")
    for d in pl["days"]:
        if d["date"] == day:
            return d
    raise HTTPException(404, "day not in plan")


@app.get("/members/{member_id}/alternatives")
def alternatives(member_id: str, recipe_id: str, day: Optional[str] = None):
    """Iso-nutrient alternatives for a dish, each with a per-ingredient DB breakdown (PRD §11.6)."""
    conn = _conn()
    try:
        m = store.get_member(conn, member_id)
    finally:
        conn.close()
    if not m:
        raise HTTPException(404, "member not found")
    if recipe_id not in RECIPES:
        raise HTTPException(404, "recipe not found")
    d = date.fromisoformat(day) if day else detect().today
    season = season_for_month(d.month)
    orig = make_component(RECIPES[recipe_id]).nutrients
    alts = DeterministicPlanner().alternatives(m, recipe_id, season, Ledger(), 0, n=3)

    def _alt(a):
        _, rows = recipe_breakdown(a["recipe"])
        return {
            "recipe_id": a["recipe"].id, "name": a["recipe"].name,
            "region": a["recipe"].region.value if a["recipe"].region else None,
            "nutrients": {k: round(v, 1) for k, v in a["nutrients"].items()},
            "delta": a["delta"],
            "ingredients": [{"name": ib.name, "qty_g": ib.qty_g,
                             "nutrients": {k: round(v, 1) for k, v in ib.nutrients.items()},
                             "source": ib.source} for ib in rows],
        }

    return {
        "declined": {"recipe_id": recipe_id, "name": RECIPES[recipe_id].name,
                     "nutrients": {k: round(v, 1) for k, v in orig.items()}},
        "alternatives": [_alt(a) for a in alts],
    }


@app.get("/recipes")
def list_recipes(region: Optional[str] = None, role: Optional[str] = None, limit: int = 800):
    """Browse the dish library (Discover). Every kcal is computed from the Knowledge DB."""
    out = []
    for r in RECIPES.values():
        if region and (r.region.value if r.region else "") != region:
            continue
        if role and r.role.value != role:
            continue
        n = make_component(r).nutrients
        out.append({"id": r.id, "name": r.name,
                    "region": r.region.value if r.region else None,
                    "role": r.role.value, "tags": sorted(r.tags),
                    "kcal": round(n["kcal"]), "protein": round(n["protein"], 1)})
        if len(out) >= limit:
            break
    return {"count": len(out), "recipes": out}


# ---- long-term memory: never / dislike / like (PRD §9.7, §17.4) ----
@app.get("/members/{member_id}/memory")
def read_memory(member_id: str):
    conn = _conn()
    try:
        if not store.get_member(conn, member_id):
            raise HTTPException(404, "member not found")
        return {"member_id": member_id, "memory": store.list_memory(conn, member_id)}
    finally:
        conn.close()


@app.post("/members/{member_id}/memory")
def add_memory(member_id: str, body: MemoryIn):
    """Remember a rejection/preference. 'never' and 'dislike' items are folded into
    the member's exclusions and stop shaping future plans immediately (§9.7)."""
    if body.kind not in memory.VALID_KINDS:
        raise HTTPException(422, f"kind must be one of {memory.VALID_KINDS}")
    conn = _conn()
    try:
        if not store.get_member(conn, member_id):
            raise HTTPException(404, "member not found")
        store.add_memory(conn, member_id, body.kind, body.value)
        return {"member_id": member_id, "memory": store.list_memory(conn, member_id)}
    finally:
        conn.close()


@app.delete("/members/{member_id}/memory")
def remove_memory(member_id: str, kind: str, value: str):
    conn = _conn()
    try:
        if not store.get_member(conn, member_id):
            raise HTTPException(404, "member not found")
        store.delete_memory(conn, member_id, kind, value)
        return {"member_id": member_id, "memory": store.list_memory(conn, member_id)}
    finally:
        conn.close()


# ---- grounded retrieval (hybrid RAG, PRD §9.7) ----
@app.get("/retrieval")
def search(q: str, kind: Optional[str] = None, top: int = 5):
    """Hybrid (BM25 + TF-IDF, RRF-fused) search over cited rules and recipes.
    Every hit carries its source — context fed to any LLM is always attributable."""
    if kind not in (None, "rule", "recipe"):
        raise HTTPException(422, "kind must be 'rule' or 'recipe'")
    return {"query": q,
            "hits": [{"id": d.id, "kind": d.kind, "text": d.text,
                      "source": d.source, "meta": d.meta}
                     for d in retrieve(q, kind=kind, top=top)]}


@app.get("/guideline-rules")
def guideline_rules(topic: Optional[str] = None):
    """The cited rule base (PRD §12.5) — every value traceable to doc + page."""
    rules = [g for g in GUIDELINE_RULES if topic is None or topic.lower() in g["topic"].lower()]
    return {"rules": rules, "count": len(rules)}


# ---- intake logging + adherence feedback loop (PRD §19.2 P0) ----
@app.post("/members/{member_id}/intake")
def log_intake(member_id: str, body: IntakeIn):
    """Log foods or a recipe (expanded to its ingredient BOM) for a given day.
    Unknown foods are rejected, never invented."""
    conn = _conn()
    try:
        if not store.get_member(conn, member_id):
            raise HTTPException(404, "member not found")
        logged = []
        for item in body.items:
            if item.food_id and item.recipe_id:
                raise HTTPException(422, "item must have food_id OR recipe_id, not both")
            if item.recipe_id:
                if item.recipe_id not in RECIPES:
                    raise HTTPException(404, f"recipe {item.recipe_id} not found")
                for ing in expand_recipe_items(item.recipe_id, item.scale or 1.0):
                    store.add_intake(conn, member_id, body.date, ing["food_id"],
                                     ing["qty_g"], body.slot, detect().now.isoformat())
                    logged.append(ing)
            elif item.food_id:
                if item.food_id not in FOODS:
                    raise HTTPException(400, f"unknown food '{item.food_id}' — not in Knowledge DB")
                store.add_intake(conn, member_id, body.date, item.food_id,
                                 item.qty_g or 0.0, body.slot, detect().now.isoformat())
                logged.append({"food_id": item.food_id, "qty_g": item.qty_g})
            else:
                raise HTTPException(422, "item must have food_id or recipe_id")
        return {"member_id": member_id, "date": body.date, "logged": logged}
    except UnknownFoodError as e:
        raise HTTPException(400, f"unknown food logged: {e}") from e
    finally:
        conn.close()


@app.get("/members/{member_id}/intake")
def read_intake(member_id: str, date: str):
    conn = _conn()
    try:
        if not store.get_member(conn, member_id):
            raise HTTPException(404, "member not found")
        return {"member_id": member_id, "date": date, "items": store.get_intake(conn, member_id, date)}
    finally:
        conn.close()


@app.get("/members/{member_id}/adherence")
def read_adherence(member_id: str, date: str, plan_id: Optional[str] = None):
    """Actual intake vs planned day (if plan_id provided) vs member targets.
    All numbers come from the Knowledge DB."""
    conn = _conn()
    try:
        if not store.get_member(conn, member_id):
            raise HTTPException(404, "member not found")
        return adherence(conn, member_id, date, plan_id=plan_id)
    except KeyError as e:
        raise HTTPException(404, str(e)) from e
    finally:
        conn.close()


# ---- grocery list + .xlsx export (PRD §11.3 / §11.4) ----
@app.get("/plans/{plan_id}/grocery")
def plan_grocery(plan_id: str, people: int = 1):
    """Aggregate a plan's ingredient BOM into a categorized, household-scaled list."""
    conn = _conn()
    try:
        pl = store.get_plan(conn, plan_id)
    finally:
        conn.close()
    if not pl:
        raise HTTPException(404, "plan not found")
    return grocery_aggregate(pl, people=people)


@app.get("/plans/{plan_id}/export.xlsx")
def plan_export_xlsx(plan_id: str, people: int = 1):
    """Download the plan as .xlsx (Week + Grocery + Targets) — Excel parity (§11.3, G7)."""
    conn = _conn()
    try:
        pl = store.get_plan(conn, plan_id)
        member = store.get_member(conn, pl["member_id"]) if pl else None
    finally:
        conn.close()
    if not pl:
        raise HTTPException(404, "plan not found")
    data = plan_to_xlsx(pl, member_name=member.name if member else "", people=people)
    return Response(content=data,
                    media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": f'attachment; filename="rituva_plan_{plan_id}.xlsx"'})


# ---- static PWA frontend (Phase D, PRD §17) ----
# Serves the approved design as an installable web app at /app, from the same origin
# as the API (so the client's fetch calls need no CORS). `uvicorn rituva.api:app`
# therefore serves BOTH the API and the PWA. CORS is still opened for dev when the
# page is opened from a different port/host.
from pathlib import Path  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.responses import RedirectResponse  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

_WEB = Path(__file__).resolve().parent.parent / "web"
if _WEB.is_dir():
    app.mount("/app", StaticFiles(directory=str(_WEB), html=True), name="app")

    @app.get("/", include_in_schema=False)
    def _root():
        return RedirectResponse("/app/")
