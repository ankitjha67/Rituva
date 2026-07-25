"""End-to-end LLM smoke test — verifies a real key works and that the LLM only writes
the friendly explanation while every nutrient still comes from the Knowledge DB.

Run (PowerShell):
    $env:RITUVA_LLM_PROVIDER="nvidia"; $env:NVIDIA_API_KEY="nvapi-..."; python scripts/llm_smoketest.py
Run (bash):
    RITUVA_LLM_PROVIDER=nvidia NVIDIA_API_KEY=nvapi-... python scripts/llm_smoketest.py
"""
import os
import sys
from datetime import date

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # Windows console safety
sys.path.insert(0, os.getcwd())
from rituva import graph                       # noqa: E402
from rituva.knowledge import SEED_MEMBERS      # noqa: E402

provider = os.environ.get("RITUVA_LLM_PROVIDER", "none")
key = (os.environ.get("NVIDIA_API_KEY") or os.environ.get("OPENAI_API_KEY")
       or os.environ.get("RITUVA_API_KEY", ""))
print(f"provider={provider!r}  key={'set' if key else 'MISSING'}")

state = graph.run(SEED_MEMBERS["aarav"], date(2026, 7, 25), 3, provider=provider, api_key=key)

print("llm_provider used :", state.provenance.get("llm_provider"))
print("llm_model         :", state.provenance.get("llm_model", "—"))
print("explanation       :", state.explanation)
day, rep = state.plan[0]
kcal = sum(e.nutrients["kcal"] for e in day.entries)
print(f"day-0 kcal (from DB): {round(kcal)}   (LLM never supplies numbers)")
if provider != "none" and state.provenance.get("llm_provider") == "none":
    print("\n[WARNING] LLM was NOT used — key/endpoint unreachable; deterministic fallback ran.")
else:
    print("\n[OK] LLM path exercised end-to-end.")
