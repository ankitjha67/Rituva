"""Persistence — SQLite by default, Postgres behind an env flag (PRD §12.3/§12.4).

Members and generated plans are stored as JSON blobs; memory and intake rows are
plain columns. Backend selection:

    RITUVA_DB=rituva.db                       → SQLite (default, offline/local-first)
    RITUVA_DB=postgresql://user:pw@host/db    → Postgres (requires `psycopg[binary]`)

The public API of this module is identical for both backends, so the engine and the
REST layer never care which one is active. The SQLite path is the tested default in
this repo; the Postgres path is exercised in deployments that run a server
(no Postgres in the dev sandbox — see CONTEXT.md).
"""
from __future__ import annotations

import json
import os
import sqlite3
from typing import List, Optional

from .domain import DietType, Goal, Member, NutrientTargets, Region, Sex

DB_PATH = os.environ.get("RITUVA_DB", "rituva.db")

_SCHEMA_SQLITE = """
CREATE TABLE IF NOT EXISTS members (id TEXT PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS plans (
    id TEXT PRIMARY KEY, member_id TEXT NOT NULL, created TEXT, data TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS user_memory (
    member_id TEXT NOT NULL, kind TEXT NOT NULL, value TEXT NOT NULL,
    UNIQUE(member_id, kind, value)
);
CREATE TABLE IF NOT EXISTS intake (
    id INTEGER PRIMARY KEY AUTOINCREMENT, member_id TEXT NOT NULL, date TEXT NOT NULL,
    food_id TEXT NOT NULL, qty_g REAL NOT NULL, slot TEXT, logged_at TEXT
);
"""

_SCHEMA_PG = """
CREATE TABLE IF NOT EXISTS members (id TEXT PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS plans (
    id TEXT PRIMARY KEY, member_id TEXT NOT NULL, created TEXT, data TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS user_memory (
    member_id TEXT NOT NULL, kind TEXT NOT NULL, value TEXT NOT NULL,
    UNIQUE(member_id, kind, value)
);
CREATE TABLE IF NOT EXISTS intake (
    id SERIAL PRIMARY KEY, member_id TEXT NOT NULL, date TEXT NOT NULL,
    food_id TEXT NOT NULL, qty_g REAL NOT NULL, slot TEXT, logged_at TEXT
);
"""


class _DB:
    """Thin uniform wrapper over a sqlite3 or psycopg connection.

    `execute()` always returns a list of plain dicts, so callers are backend-agnostic.
    """

    def __init__(self, raw, backend: str):
        self.raw = raw
        self.backend = backend          # "sqlite" | "pg"

    def execute(self, sql: str, params: tuple = ()) -> list:
        if self.backend == "pg":
            cur = self.raw.cursor()
            cur.execute(sql.replace("?", "%s"), params)
            if cur.description:
                cols = [c.name for c in cur.description]
                return [dict(zip(cols, row)) for row in cur.fetchall()]
            return []
        cur = self.raw.execute(sql, params)
        return [dict(r) for r in cur.fetchall()]

    def executescript(self, sql: str) -> None:
        if self.backend == "pg":
            cur = self.raw.cursor()
            for stmt in sql.split(";"):
                if stmt.strip():
                    cur.execute(stmt)
        else:
            self.raw.executescript(sql)

    def commit(self) -> None:
        self.raw.commit()

    def close(self) -> None:
        self.raw.close()


def connect(path: Optional[str] = None) -> _DB:
    dsn = path or DB_PATH
    if isinstance(dsn, str) and dsn.startswith(("postgresql://", "postgres://")):
        try:
            import psycopg  # type: ignore
        except ImportError as e:  # pragma: no cover - depends on deployment env
            raise RuntimeError(
                "RITUVA_DB points at Postgres but psycopg is not installed. "
                "Run: pip install 'psycopg[binary]'  (or use a SQLite path)."
            ) from e
        db = _DB(psycopg.connect(dsn), "pg")   # pragma: no cover
        db.executescript(_SCHEMA_PG)           # pragma: no cover
        return db
    raw = sqlite3.connect(dsn)
    raw.row_factory = sqlite3.Row
    db = _DB(raw, "sqlite")
    db.executescript(_SCHEMA_SQLITE)
    return db


# ---- (de)serialization -----------------------------------------------------
def member_to_dict(m: Member) -> dict:
    return {
        "id": m.id, "name": m.name, "sex": m.sex.value, "age": m.age,
        "weight_kg": m.weight_kg, "height_cm": m.height_cm, "pal": m.pal,
        "goal": m.goal.value, "diet_type": m.diet_type.value,
        "region_prefs": [r.value for r in m.region_prefs],
        "conditions": list(m.conditions), "excludes": sorted(m.excludes),
        "known_targets": m.known_targets, "doctor_diet": m.doctor_diet,
    }


def member_from_dict(d: dict) -> Member:
    return Member(
        id=d["id"], name=d["name"], sex=Sex(d["sex"]), age=int(d["age"]),
        weight_kg=float(d["weight_kg"]), height_cm=float(d["height_cm"]),
        pal=float(d.get("pal", 1.4)), goal=Goal(d.get("goal", "maintain")),
        diet_type=DietType(d.get("diet_type", "lacto_veg")),
        region_prefs=tuple(Region(x) for x in d.get("region_prefs", [])),
        conditions=tuple(d.get("conditions", [])),
        excludes=frozenset(d.get("excludes", [])),
        known_targets=d.get("known_targets"), doctor_diet=d.get("doctor_diet"),
    )


def targets_to_dict(t: NutrientTargets) -> dict:
    return {
        "kcal": t.kcal, "protein_g": t.protein_g, "fat_g": t.fat_g, "carb_g": t.carb_g,
        "fibre_g": t.fibre_g, "sodium_mg_max": t.sodium_mg_max,
        "added_sugar_g_max": t.added_sugar_g_max,
        "iron_mg": t.iron_mg, "calcium_mg": t.calcium_mg, "b12_ug": t.b12_ug,
        "source": t.source, "citations": list(t.citations),
    }


def _round(d: dict) -> dict:
    return {k: round(v, 1) for k, v in d.items()}


def day_to_dict(dp, rep) -> dict:
    return {
        "date": dp.date, "member_id": dp.member_id, "season": dp.season,
        "totals": _round(dp.totals),
        "entries": [{
            "slot": e.slot.value, "nutrients": _round(e.nutrients),
            "components": [{
                "recipe_id": c.recipe_id, "name": c.name, "region": c.region,
                "nutrients": _round(c.nutrients),
                "ingredients": [{
                    "food_id": ib.food_id, "name": ib.name, "qty_g": ib.qty_g,
                    "nutrients": _round(ib.nutrients), "source": ib.source,
                } for ib in c.ingredients],
            } for c in e.components],
        } for e in dp.entries],
        "validation": {
            "in_tolerance": rep.in_tolerance, "dqs": rep.dqs,
            "checks": {k: list(v) for k, v in rep.checks.items()},
            "hard_violations": rep.hard_violations, "warnings": rep.warnings,
        },
        "notes": dp.notes,
    }


# ---- CRUD ------------------------------------------------------------------
def save_member(conn: _DB, m: Member) -> None:
    if conn.backend == "pg":   # pragma: no cover
        conn.execute("INSERT INTO members(id, data) VALUES (?, ?) "
                     "ON CONFLICT (id) DO UPDATE SET data=EXCLUDED.data",
                     (m.id, json.dumps(member_to_dict(m))))
    else:
        conn.execute("INSERT OR REPLACE INTO members(id, data) VALUES (?, ?)",
                     (m.id, json.dumps(member_to_dict(m))))
    conn.commit()


def get_member(conn: _DB, member_id: str) -> Optional[Member]:
    rows = conn.execute("SELECT data FROM members WHERE id=?", (member_id,))
    return member_from_dict(json.loads(rows[0]["data"])) if rows else None


def list_members(conn: _DB) -> List[Member]:
    return [member_from_dict(json.loads(r["data"]))
            for r in conn.execute("SELECT data FROM members ORDER BY id")]


def save_plan(conn: _DB, plan_id: str, member_id: str,
              payload: dict, created: str) -> None:
    if conn.backend == "pg":   # pragma: no cover
        conn.execute("INSERT INTO plans(id, member_id, created, data) VALUES (?, ?, ?, ?) "
                     "ON CONFLICT (id) DO UPDATE SET member_id=EXCLUDED.member_id, "
                     "created=EXCLUDED.created, data=EXCLUDED.data",
                     (plan_id, member_id, created, json.dumps(payload)))
    else:
        conn.execute("INSERT OR REPLACE INTO plans(id, member_id, created, data) VALUES (?, ?, ?, ?)",
                     (plan_id, member_id, created, json.dumps(payload)))
    conn.commit()


def get_plan(conn: _DB, plan_id: str) -> Optional[dict]:
    rows = conn.execute("SELECT data FROM plans WHERE id=?", (plan_id,))
    return json.loads(rows[0]["data"]) if rows else None


# ---- memory (preferences / rejections) ----
def add_memory(conn: _DB, member_id: str, kind: str, value: str) -> None:
    if conn.backend == "pg":   # pragma: no cover
        conn.execute("INSERT INTO user_memory(member_id, kind, value) VALUES (?, ?, ?) "
                     "ON CONFLICT DO NOTHING", (member_id, kind, value))
    else:
        conn.execute("INSERT OR IGNORE INTO user_memory(member_id, kind, value) VALUES (?, ?, ?)",
                     (member_id, kind, value))
    conn.commit()


def delete_memory(conn: _DB, member_id: str, kind: str, value: str) -> None:
    conn.execute("DELETE FROM user_memory WHERE member_id=? AND kind=? AND value=?",
                 (member_id, kind, value))
    conn.commit()


def get_memory(conn: _DB, member_id: str, kind: str) -> set:
    return {r["value"] for r in conn.execute(
        "SELECT value FROM user_memory WHERE member_id=? AND kind=?", (member_id, kind))}


def list_memory(conn: _DB, member_id: str) -> dict:
    out: dict = {}
    for r in conn.execute("SELECT kind, value FROM user_memory WHERE member_id=?", (member_id,)):
        out.setdefault(r["kind"], []).append(r["value"])
    return out


# ---- intake logging (Phase C feedback loop) ----
def add_intake(conn: _DB, member_id: str, day: str, food_id: str,
               qty_g: float, slot: Optional[str], logged_at: Optional[str]) -> None:
    conn.execute("INSERT INTO intake(member_id, date, food_id, qty_g, slot, logged_at) "
                 "VALUES (?, ?, ?, ?, ?, ?)", (member_id, day, food_id, qty_g, slot, logged_at))
    conn.commit()


def get_intake(conn: _DB, member_id: str, day: str) -> list:
    return conn.execute(
        "SELECT food_id, qty_g, slot, logged_at FROM intake WHERE member_id=? AND date=?",
        (member_id, day))
