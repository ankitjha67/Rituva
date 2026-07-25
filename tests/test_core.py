"""Core guarantees for the deterministic engine.

Runs under pytest *or* standalone (`python tests/test_core.py`). These tests encode
the promises the product must never break: numbers come from the DB (not invented),
doctor diets take precedence, mains don't over-repeat, and frequency caps hold.
"""
import os
import sys
import tempfile
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from rituva.adherence import adherence, expand_recipe_items  # noqa: E402
from rituva.domain import DietType, Goal, Member, Region, Role, Sex          # noqa: E402
from rituva.knowledge import FREQUENCY_POLICY, RECIPES, SEED_MEMBERS          # noqa: E402
from rituva.memory import apply_memory                                        # noqa: E402
from rituva.nutrition import UnknownFoodError, food_nutrients, recipe_breakdown  # noqa: E402
from rituva.planner import DeterministicPlanner                               # noqa: E402
from rituva.retrieval import retrieve, rules_for                              # noqa: E402
from rituva import graph, store                                               # noqa: E402
from rituva.targets import bmi, bmr_mifflin, effective_targets, targets_report  # noqa: E402


def _test_db(path):
    if os.path.exists(path):
        os.remove(path)
    return store.connect(path)


def test_bmi_and_bmr_match_reference():
    assert round(bmi(72, 173), 1) == 24.1
    assert round(bmr_mifflin(Sex.M, 72, 173, 32)) == 1646     # Mifflin–St Jeor


def test_nutrients_come_from_db_never_invented():
    n = food_nutrients("toor_dal", 200)          # 22.3 g protein/100 g × 2
    assert round(n["protein"], 1) == 44.6
    assert round(n["carb"], 1) == 115.2
    try:
        food_nutrients("unicorn_meat", 100)
        assert False, "unknown food must raise, not invent"
    except UnknownFoodError:
        pass


def test_recipe_breakdown_is_sum_of_ingredients():
    total, rows = recipe_breakdown(RECIPES["chole"])       # kabuli 55 + tomato 40 + oil 5
    expected_protein = 19.3 * 0.55 + 0.9 * 0.40
    assert abs(total["protein"] - expected_protein) < 0.05
    assert len(rows) == 3
    assert all(r.source for r in rows)                      # every row is sourced


def test_doctor_diet_takes_precedence():
    m = Member(id="x", name="X", sex=Sex.M, age=40, weight_kg=70, height_cm=170,
               doctor_diet={"kcal": 1800, "sodium_mg_max": 1500, "source": "Dr. Rao renal plan"})
    t = effective_targets(m)
    assert t.kcal == 1800 and t.sodium_mg_max == 1500
    assert t.source == "doctor_prescription"


def test_energy_on_target_and_no_hard_violations():
    m = SEED_MEMBERS["aarav"]
    tg, _ = targets_report(m)
    plan = DeterministicPlanner().plan(m, tg, date(2026, 7, 1), 14)
    assert all(not rep.hard_violations for _, rep in plan)
    assert all(rep.in_tolerance for _, rep in plan)


def test_mains_dont_repeat_within_gap_and_caps_hold():
    m = SEED_MEMBERS["aarav"]
    tg, _ = targets_report(m)
    plan = DeterministicPlanner().plan(m, tg, date(2026, 1, 1), 28)
    gap = FREQUENCY_POLICY["dish_min_gap_days"]

    last, hero_days = {}, {}
    for di, (dp, _rep) in enumerate(plan):
        mains = [e.components[1].recipe_id for e in dp.entries if e.slot.value in ("lunch", "dinner")]
        assert mains[0] != mains[1]                          # lunch/dinner mains differ same day
        for rid in mains:
            r = RECIPES[rid]
            if r.role == Role.MAIN and "staple" not in r.tags:
                if rid in last:
                    assert di - last[rid] >= gap, f"{rid} repeated within {gap} days"
                last[rid] = di
            if r.hero:
                hero_days.setdefault(r.hero, []).append(di)

    for hero, cap in FREQUENCY_POLICY["ingredient_per_week"].items():
        days = hero_days.get(hero, [])
        for di in range(28):
            wk = sum(1 for d in days if di - 7 < d <= di)
            assert wk <= cap, f"{hero} exceeded {cap}/week"


def test_hybrid_retrieval_returns_cited_rules():
    hits = retrieve("salt sodium limit", kind="rule", top=3)
    assert any(h.kind == "rule" for h in hits)
    assert any("DGI" in h.source for h in hits)
    hits2 = retrieve("high protein breakfast south", kind="recipe", top=5)
    assert all(h.kind == "recipe" for h in hits2)
    # every rule hit carries a source citation
    for h in rules_for("protein rda limit", top=2):
        assert h.source and h.kind == "rule"


def test_memory_folds_never_into_excludes_and_shapes_plan():
    dbp = os.path.join(tempfile.gettempdir(), "rituva_mem_test.db")
    conn = _test_db(dbp)
    try:
        m = SEED_MEMBERS["aarav"]
        store.add_memory(conn, m.id, "never", "mushroom")
        mm = apply_memory(conn, m)
        assert "mushroom" in mm.excludes

        state = graph.run(m, date(2026, 7, 1), 21, conn=conn)
        rids = [c.recipe_id for dp, _ in state.plan for e in dp.entries for c in e.components]
        assert not any(RECIPES[r].hero == "mushroom" or "mushroom" in r for r in rids)
        # grounded-RAG node populated cited rules
        assert state.citations
        assert all(c["source"] for c in state.citations)
        assert state.provenance.get("rules_cited")
    finally:
        conn.close()
        if os.path.exists(dbp):
            os.remove(dbp)


def test_adherence_actuals_vs_targets_vs_plan():
    dbp = os.path.join(tempfile.gettempdir(), "rituva_adh_test.db")
    conn = _test_db(dbp)
    try:
        m = SEED_MEMBERS["aarav"]
        store.save_member(conn, m)
        t, _ = targets_report(m)
        plan = DeterministicPlanner().plan(m, t, date(2026, 7, 25), 3)
        plan_id = "adh_demo"
        days = [store.day_to_dict(dp, rep) for dp, rep in plan]
        store.save_plan(conn, plan_id, m.id, {
            "plan_id": plan_id, "member_id": m.id, "start": "2026-07-25",
            "days_count": 3, "days": days,
        }, "2026-07-25T00:00:00")

        # Log two known foods as actual intake
        store.add_intake(conn, m.id, "2026-07-25", "rice", 200, "lunch", "2026-07-25T12:00:00")
        store.add_intake(conn, m.id, "2026-07-25", "curd", 100, "snack", "2026-07-25T16:00:00")

        rep = adherence(conn, m.id, "2026-07-25", plan_id=plan_id)
        expected_rice_kcal = 200 / 100 * 356
        expected_curd_kcal = 100 / 100 * 60
        assert abs(rep["actuals"]["kcal"] - (expected_rice_kcal + expected_curd_kcal)) < 1
        kcal_row = next(r for r in rep["per_nutrient"] if r["nutrient"] == "kcal")
        assert kcal_row["planned"] is not None
        assert kcal_row["target"] > 0
        assert 0 < rep["score"] <= 150

        # Recipe expansion should decompose a known recipe into its ingredient rows
        ings = expand_recipe_items("chole", 1.0)
        assert any(i["food_id"] == "kabuli_chana" for i in ings)
    finally:
        conn.close()
        if os.path.exists(dbp):
            os.remove(dbp)


def _run_standalone():
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        try:
            fn()
            print(f"PASS  {fn.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL  {fn.__name__}: {e}")
        except Exception as e:  # noqa: BLE001
            print(f"ERROR {fn.__name__}: {type(e).__name__}: {e}")
    print(f"\n{passed}/{len(fns)} passed")
    return 0 if passed == len(fns) else 1


if __name__ == "__main__":
    raise SystemExit(_run_standalone())
