import re
from typing import Dict, List


PATTERNS: Dict[str, re.Pattern[str]] = {
    "phone": re.compile(r"1[3-9]\d{9}"),
    "order": re.compile(r"(?:订单|order)[\s:：-]*[A-Za-z0-9]{8,}", re.IGNORECASE),
    "id_card": re.compile(r"\d{17}[\dXx]"),
}


def detect_text_patterns(text: str) -> List[Dict[str, str]]:
    """Reserved for the later OCR stage: classify text snippets with regex rules."""
    hits: List[Dict[str, str]] = []
    for pattern_type, pattern in PATTERNS.items():
        for match in pattern.finditer(text):
            hits.append({"type": pattern_type, "text": match.group(0)})
    return hits
