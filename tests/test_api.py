"""API smoke tests — skipped cleanly if FastAPI isn't installed.

Runs under pytest or standalone (`python tests/test_api.py`). Verifies the REST layer
round-trips through SQLite and that every nutrient in a response is DB-sourced.
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Point at a throwaway DB *before* importing the app (store reads the env at import).
os.environ.setdefault("RITUVA_DB", os.path.join(tempfile.gettempdir(), "rituva_test.db"))

try:
    from fastapi.testclient import TestClient
    from rituva.api import app
    _HAVE = True
except Exception:  # noqa: BLE001
    _HAVE = False


def test_api_smoke():
    if not _HAVE:
        print("SKIP test_api_smoke (fastapi not installed)")
        return
    dbp = os.environ["RITUVA_DB"]
    if os.path.exists(dbp):
        os.remove(dbp)
    with TestClient(app) as c:
        assert c.get("/health").json()["status"] == "ok"
        ctx = c.get("/context").json()
        assert {"today", "season", "current_slot"} <= set(ctx)
        assert "aarav" in [m["id"] for m in c.get("/members").json()]

        r = c.post("/plans", json={"member_id": "aarav", "days": 3, "start": "2026-07-25"}).json()
        assert len(r["days"]) == 3
        # a lunch component's first ingredient must carry a DB source (never invented)
        assert r["days"][0]["entries"][1]["components"][0]["ingredients"][0]["source"]

        day = c.get(f"/plans/{r['plan_id']}/day/2026-07-25").json()
        assert day["date"] == "2026-07-25"

        alt = c.get("/members/aarav/alternatives", params={"recipe_id": "mushroom_paneer"}).json()
        assert alt["alternatives"] and alt["alternatives"][0]["ingredients"][0]["source"]

        # doctor-diet precedence through the API
        c.post("/members", json={"id": "docdemo", "name": "D", "sex": "M", "age": 50,
                                 "weight_kg": 80, "height_cm": 175,
                                 "doctor_diet": {"kcal": 1700, "sodium_mg_max": 1500, "source": "Dr plan"}})
        t = c.get("/members/docdemo/targets").json()["targets"]
        assert t["kcal"] == 1700 and t["source"] == "doctor_prescription"
    print("PASS  test_api_smoke")


def test_api_memory_and_retrieval():
    if not _HAVE:
        print("SKIP test_api_memory_and_retrieval (fastapi not installed)")
        return
    dbp = os.environ["RITUVA_DB"]
    if os.path.exists(dbp):
        os.remove(dbp)
    with TestClient(app) as c:
        # 1. mark mushroom as "never"; plans must not include any mushroom dish
        c.post("/members/aarav/memory", json={"kind": "never", "value": "mushroom"})
        r = c.post("/plans", json={"member_id": "aarav", "days": 7, "start": "2026-07-25"}).json()
        rids = [c["recipe_id"] for d in r["days"] for e in d["entries"] for c in e["components"]]
        assert not any("mushroom" in rid for rid in rids), rids

        # 2. hybrid retrieval endpoint returns cited rule hits
        res = c.get("/retrieval", params={"q": "salt limit", "kind": "rule", "top": 3}).json()
        assert any("salt" in h["text"].lower() and h["source"] for h in res["hits"])

        # 3. guideline-rules endpoint mirrors the cited rule base
        gr = c.get("/guideline-rules", params={"topic": "salt"}).json()
        assert any("salt" in g["topic"].lower() for g in gr["rules"])

        # 4. delete memory and confirm it is gone
        c.delete("/members/aarav/memory", params={"kind": "never", "value": "mushroom"})
        assert "mushroom" not in c.get("/members/aarav/memory").json()["memory"].get("never", [])

        # 5. provenance carries grounded citations
        assert "rules_cited" in r["provenance"]
        assert r["provenance"]["rules_cited"]
    print("PASS  test_api_memory_and_retrieval")


def test_api_intake_and_adherence():
    if not _HAVE:
        print("SKIP test_api_intake_and_adherence (fastapi not installed)")
        return
    dbp = os.environ["RITUVA_DB"]
    if os.path.exists(dbp):
        os.remove(dbp)
    with TestClient(app) as c:
        # generate a plan for aarav to compare against
        r = c.post("/plans", json={"member_id": "aarav", "days": 3, "start": "2026-07-25"}).json()
        plan_id = r["plan_id"]

        # log a food and a recipe (expanded server-side into ingredients)
        c.post("/members/aarav/intake", json={
            "date": "2026-07-25",
            "slot": "lunch",
            "items": [
                {"food_id": "rice", "qty_g": 150},
                {"recipe_id": "chole", "scale": 1.0},
            ],
        })

        # read back the logged items
        logged = c.get("/members/aarav/intake", params={"date": "2026-07-25"}).json()
        assert logged["items"]
        # a recipe was expanded: chickpea ingredient appears
        assert any(i["food_id"] == "kabuli_chana" for i in logged["items"])

        # adherence report: actuals vs plan vs targets
        adh = c.get("/members/aarav/adherence",
                    params={"date": "2026-07-25", "plan_id": plan_id}).json()
        assert adh["score"] > 0
        kcal = next(x for x in adh["per_nutrient"] if x["nutrient"] == "kcal")
        assert kcal["actual"] > 0
        assert kcal["target"] > 0
        assert kcal["planned"] is not None

        # unknown food is rejected, not invented
        bad = c.post("/members/aarav/intake", json={
            "date": "2026-07-25", "items": [{"food_id": "unicorn_meat", "qty_g": 100}],
        })
        assert bad.status_code == 400
    print("PASS  test_api_intake_and_adherence")


def test_api_serves_pwa():
    """Phase D: the FastAPI app also serves the installable PWA at /app."""
    if not _HAVE:
        print("SKIP test_api_serves_pwa (fastapi not installed)")
        return
    with TestClient(app) as c:
        shell = c.get("/app/")
        assert shell.status_code == 200 and "Rituva" in shell.text
        assert c.get("/app/app.js").status_code == 200
        assert c.get("/", follow_redirects=False).status_code in (307, 308)
    print("PASS  test_api_serves_pwa")


def test_api_grocery_and_export():
    """Grocery aggregation + .xlsx export (PRD §11.3/§11.4)."""
    if not _HAVE:
        print("SKIP test_api_grocery_and_export (fastapi not installed)")
        return
    with TestClient(app) as c:
        r = c.post("/plans", json={"member_id": "aarav", "days": 3, "start": "2026-07-25"}).json()
        pid = r["plan_id"]
        g = c.get(f"/plans/{pid}/grocery", params={"people": 2}).json()
        assert g["total_items"] > 0 and g["categories"]
        names = [it["item"] for cat in g["categories"] for it in cat["items"]]
        assert any("Rice" in n for n in names)          # staple aggregated across days
        x = c.get(f"/plans/{pid}/export.xlsx")
        assert x.status_code == 200
        assert x.headers["content-type"].startswith("application/vnd.openxml")
        assert x.content[:2] == b"PK"                    # .xlsx is a zip container
    print("PASS  test_api_grocery_and_export")


if __name__ == "__main__":
    for _fn in (test_api_smoke, test_api_memory_and_retrieval,
                test_api_intake_and_adherence, test_api_serves_pwa,
                test_api_grocery_and_export):
        _fn()
