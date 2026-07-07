from typing import Iterable

from schemas.models import PrivacyItem


RISK_ORDER = {"low": 1, "medium": 2, "high": 3}


def classify_overall_risk(items: Iterable[PrivacyItem]) -> str:
    highest = "low"
    for item in items:
        if RISK_ORDER.get(item.riskLevel, 0) > RISK_ORDER[highest]:
            highest = item.riskLevel
    return highest
