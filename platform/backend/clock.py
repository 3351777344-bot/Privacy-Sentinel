"""The one clock this backend reasons about dates with.

Deadline handling has two halves that must agree: the relative-expression
resolver turns "下周之前" into a calendar date, and the completeness check then
compares that date against "now". If the two halves consult different clocks —
or the same clock in a timezone the user is not in — a brief submitted on time
can be reported as overdue (or the reverse) for the hours either side of
midnight.

The deployment serves Chinese university submissions, so the reference zone is
China Standard Time. It is written as a fixed +08:00 offset rather than a
`ZoneInfo("Asia/Shanghai")` lookup because China has observed no daylight saving
since 1991: the offset is a constant, and a constant cannot fail on a host whose
tzdata is missing or stale — which is exactly the kind of host a hand-deployed
service runs on.

Naive local datetimes are returned on purpose: every other datetime in this
module tree (parsed deadlines, stored timestamps) is naive, and mixing aware and
naive values raises on comparison.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

#: China Standard Time as a constant offset (see the module docstring).
CHINA_TZ = timezone(timedelta(hours=8), name="CST+08:00")

#: Explicit labels so a produced date is never confused with the host's local day.
DISPLAY_LABEL = "北京时间"


def china_now() -> datetime:
    """Current wall-clock time in China, as a naive datetime."""
    return datetime.now(CHINA_TZ).replace(tzinfo=None)


def china_today() -> date:
    """Current calendar day in China."""
    return china_now().date()


def describe_now() -> str:
    """The reference moment in user-facing words, e.g. ``2026-09-28（北京时间）``."""
    return f"{china_today().isoformat()}（{DISPLAY_LABEL}）"
