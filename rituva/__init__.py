"""Rituva — guideline-grounded, seasonal, LLM-agnostic nutrition & menu planner.

The deterministic core (targets, nutrition math, planner, validator) never depends
on an LLM and never invents a number: every nutrient value is computed from the
Knowledge DB (see `rituva.knowledge`). See PRD.md §9 for the anti-hallucination
contract this package implements.
"""
__version__ = "0.1.0"
KB_VERSION = "dgi2024-ifct2017-v1"
