RISK_PENALTY = {"high": 25, "medium": 12, "low": 3}
RISK_ORDER = {"low": 1, "medium": 2, "high": 3}


def calculate_security_score(levels: list[str]) -> int:
    """Return a comparable 0-100 score with capped repeated penalties."""
    counts = {level: min(levels.count(level), 4) for level in RISK_PENALTY}
    penalty = sum(RISK_PENALTY[level] * count for level, count in counts.items())
    return max(0, 100 - penalty)


def highest_risk(levels: list[str]) -> str:
    return max(levels, key=lambda level: RISK_ORDER.get(level, 0), default="low")
