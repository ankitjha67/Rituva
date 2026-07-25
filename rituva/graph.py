"""Orchestration pipeline (PRD §9.1 / §9.7).

Implemented as a LangGraph state graph when `langgraph` is installed, and as an
equivalent plain-Python sequential runner otherwise — so the project runs with zero
extra dependencies. Either way the shape is:

    compute_targets -> retrieve (cited rules) -> plan (deterministic) -> explain (optional LLM)

`retrieve` is the grounded-RAG node: it pulls the *cited* guideline rules relevant to
the member into the run's context (provenance + explanation grounding). `plan` and
`compute_targets` never call an LLM; `explain` may, but only for prose — all numbers
come from the deterministic nodes. If the LLM path fails, `explain` degrades to a
deterministic note.

When a store connection is passed to `run()`, the member's long-term memory
(never/dislike items, §9.7) is folded into their exclusions before planning.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import List, Optional, Tuple

from . import KB_VERSION
from .domain import DayPlan, Member, NutrientTargets, ValidationReport
from .gateway import FallbackRouter, build_gateway
from .planner import DeterministicPlanner
from .retrieval import rules_for
from .targets import targets_report


@dataclass
class PipelineState:
    member: Member
    start: date
    days: int
    gateway: Optional[FallbackRouter] = None
    targets: Optional[NutrientTargets] = None
    info: dict = field(default_factory=dict)
    citations: List[dict] = field(default_factory=list)   # grounded context (cited rules)
    plan: List[Tuple[DayPlan, ValidationReport]] = field(default_factory=list)
    explanation: str = ""
    provenance: dict = field(default_factory=dict)


# ---- nodes -----------------------------------------------------------------
def node_compute_targets(s: PipelineState) -> PipelineState:
    s.targets, s.info = targets_report(s.member)
    return s


def node_retrieve(s: PipelineState) -> PipelineState:
    """Grounded retrieval: the cited rules that justify this run's targets/limits.

    Deterministic (BM25 + TF-IDF over the KB) — it selects *which cited rules* the
    explanation may reference; it never supplies a nutrient number (PRD §9.7).
    """
    m = s.member
    query = " ".join([
        m.goal.value, "protein energy targets limits",
        " ".join(m.conditions),
        " ".join(r.value for r in m.region_prefs),
    ]).strip()
    s.citations = [
        {"rule": d.id, "text": d.display or d.text, "source": d.source}
        for d in rules_for(query, top=4)
    ]
    return s


def node_plan(s: PipelineState) -> PipelineState:
    s.plan = DeterministicPlanner().plan(s.member, s.targets, s.start, s.days)
    return s


def node_explain(s: PipelineState) -> PipelineState:
    ok_days = sum(1 for _, r in s.plan if r.in_tolerance)
    det = (f"Planned {len(s.plan)} unique days for {s.member.name}: "
           f"{ok_days}/{len(s.plan)} on target, avg score "
           f"{round(sum(r.dqs for _, r in s.plan)/max(len(s.plan),1))}. "
           f"All nutrient values are from the Knowledge DB (IFCT 2017); none invented.")
    gw = s.gateway
    if gw is not None:
        prompt = ("Write one friendly sentence encouraging the user about this vegetarian "
                  "meal plan. Do NOT state any nutrient numbers.\nFacts: " + det)
        res = gw.generate(prompt, prefer_fast=True)
        s.explanation = (res.text.strip() or det) if res.ok else det
        s.provenance["llm_provider"] = res.provider
        s.provenance["llm_model"] = res.model
    else:
        s.explanation = det
        s.provenance["llm_provider"] = "none"
    s.provenance["kb_version"] = KB_VERSION
    s.provenance["rules_cited"] = [c["rule"] for c in s.citations]
    return s


# ---- runner ----------------------------------------------------------------
def _run_sequential(s: PipelineState) -> PipelineState:
    return node_explain(node_plan(node_retrieve(node_compute_targets(s))))


def _run_langgraph(s: PipelineState) -> PipelineState:
    try:
        from langgraph.graph import END, START, StateGraph  # type: ignore
    except Exception:
        return _run_sequential(s)
    g = StateGraph(PipelineState)
    g.add_node("targets", node_compute_targets)
    g.add_node("retrieve", node_retrieve)
    g.add_node("plan", node_plan)
    g.add_node("explain", node_explain)
    g.add_edge(START, "targets")
    g.add_edge("targets", "retrieve")
    g.add_edge("retrieve", "plan")
    g.add_edge("plan", "explain")
    g.add_edge("explain", END)
    return g.compile().invoke(s)


def run(member: Member, start: date, days: int,
        provider: str = "none", api_key: str = "", conn=None) -> PipelineState:
    """Run the pipeline. Pass a store connection as `conn` to fold the member's
    long-term memory (never/dislike) into their exclusions first (PRD §9.7)."""
    if conn is not None:
        from .memory import apply_memory
        member = apply_memory(conn, member)
    gateway = build_gateway(provider, api_key) if provider not in ("none", "", None) else None
    state = PipelineState(member=member, start=start, days=days, gateway=gateway)
    result = _run_langgraph(state)
    # StateGraph.invoke may return a dict-like; normalise back to PipelineState
    if isinstance(result, dict):
        for k, v in result.items():
            setattr(state, k, v)
        return state
    return result
