"""Per-user long-term memory (PRD §9.7) — the preferences and rejections that shape
future plans, persisted via `store`.

A 'never' or 'dislike' item is merged into the member's `excludes` before planning, so
a dish the user rejected stops recurring — the 'not this week / never' loop from the
Swap screen (§17.4 #11). Memory shapes *which* compliant dish is chosen; it never
changes a nutrient number.
"""
from __future__ import annotations

from dataclasses import replace

from .domain import Member

VALID_KINDS = ("never", "dislike", "like")


def apply_memory(conn, member: Member) -> Member:
    """Return the member with 'never'/'dislike' items folded into excludes."""
    from . import store
    excl = store.get_memory(conn, member.id, "never") | store.get_memory(conn, member.id, "dislike")
    if not excl:
        return member
    return replace(member, excludes=frozenset(member.excludes) | excl)
