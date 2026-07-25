"""System context detection — date, time-of-day, season and the 'current meal',
read from the device's own clock (mobile or desktop).

Rituva ('ritu' = season) auto-detects everything so the user never sets a date:
today's system date drives the plan, the local time highlights the meal that's next,
and the month maps to the region's season for seasonal produce selection. PRD §7.6.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time
from typing import Optional

from .domain import MealSlot, Season
from .planner import season_for_month

# Local-time windows → meal slot (used to highlight the current / next meal).
MEAL_WINDOWS = [
    (time(5, 0), time(10, 30), MealSlot.BREAKFAST),
    (time(10, 30), time(12, 30), MealSlot.SNACK1),
    (time(12, 30), time(15, 30), MealSlot.LUNCH),
    (time(15, 30), time(19, 0), MealSlot.SNACK2),
    (time(19, 0), time(23, 0), MealSlot.DINNER),
]


@dataclass
class SystemContext:
    today: date
    now: datetime
    season: Season
    current_slot: MealSlot
    greeting: str


def current_slot(t: time) -> MealSlot:
    for start, end, slot in MEAL_WINDOWS:
        if start <= t < end:
            return slot
    return MealSlot.BREAKFAST     # late night → the next meal is tomorrow's breakfast


def greeting_for(t: time) -> str:
    h = t.hour
    if h < 12:
        return "Good morning"
    if h < 17:
        return "Good afternoon"
    if h < 21:
        return "Good evening"
    return "Good night"


def detect(now: Optional[datetime] = None) -> SystemContext:
    """Detect date/time/season/current-meal from the system clock (or an injected `now`)."""
    now = now or datetime.now()
    return SystemContext(
        today=now.date(),
        now=now,
        season=season_for_month(now.month),
        current_slot=current_slot(now.time()),
        greeting=greeting_for(now.time()),
    )
