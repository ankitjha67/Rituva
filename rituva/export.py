"""Export a plan to .xlsx — Excel parity with the reference Eastern Diet Planner
(PRD §11.3 / goal G7). Uses openpyxl (optional dep). Sheets: Week · Grocery · Targets.

Returns raw bytes so the API can stream it as a download. Values come from the plan
payload (all DB-computed); this module formats, it does not compute nutrition.
"""
from __future__ import annotations

import io

from .grocery import aggregate


def plan_to_xlsx(plan: dict, member_name: str = "", people: int = 1) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill

    head = Font(bold=True, color="241300")
    fill = PatternFill("solid", fgColor="FFB020")
    wb = Workbook()

    # --- Week ---
    ws = wb.active
    ws.title = "Week"
    ws.append(["Date", "Season", "Breakfast", "Lunch", "Dinner", "Snack 1", "Snack 2", "kcal", "DQS"])
    for c in ws[1]:
        c.font, c.fill = head, fill
    slot_col = {"breakfast": 2, "lunch": 3, "dinner": 4, "snack1": 5, "snack2": 6}
    for d in plan.get("days", []):
        row = [d["date"], d.get("season", "")] + [""] * 5 + [
            round(d["totals"]["kcal"]), d["validation"]["dqs"]]
        for e in d["entries"]:
            idx = slot_col.get(e["slot"])
            if idx is not None:
                row[idx] = " + ".join(c["name"] for c in e["components"])
        ws.append(row)
    for i, w in enumerate([12, 10, 26, 32, 26, 18, 18, 7, 6], 1):
        ws.column_dimensions[chr(64 + i)].width = w

    # --- Grocery ---
    gs = wb.create_sheet("Grocery")
    gs.append(["Item", "Category", "Quantity", "Unit"])
    for c in gs[1]:
        c.font, c.fill = head, fill
    for cat in aggregate(plan, people=people)["categories"]:
        for it in cat["items"]:
            gs.append([it["item"], it["category"], it["quantity"], it["unit"]])
    for i, w in enumerate([28, 14, 10, 8], 1):
        gs.column_dimensions[chr(64 + i)].width = w

    # --- Targets ---
    tsh = wb.create_sheet("Targets")
    t = plan.get("targets", {})
    tsh.append(["Rituva plan for", member_name])
    tsh.append(["Metric", "Value"])
    for c in tsh[2]:
        c.font, c.fill = head, fill
    for k in ("kcal", "protein_g", "fat_g", "carb_g", "fibre_g",
              "sodium_mg_max", "added_sugar_g_max", "source"):
        tsh.append([k, t.get(k, "")])
    tsh.append(["citations", ", ".join(t.get("citations", []))])
    tsh.column_dimensions["A"].width = 20
    tsh.column_dimensions["B"].width = 44

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
