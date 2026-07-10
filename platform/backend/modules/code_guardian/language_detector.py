import re
from dataclasses import dataclass
from pathlib import Path


EXTENSION_LANGUAGE_MAP = {
    ".py": "python",
    ".java": "java",
    ".js": "javascript",
    ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".sql": "sql",
    ".txt": "other",
}

SUPPORTED_LANGUAGES = {"python", "java", "javascript", "typescript", "sql", "other"}


@dataclass(frozen=True)
class LanguageDetection:
    language: str
    source: str
    confidence: float


def _normalize_selected(language: str | None) -> str:
    selected = (language or "").strip().lower()
    aliases = {
        "js": "javascript",
        "javascript / typescript": "javascript",
        "javascript/typescript": "javascript",
        "ts": "typescript",
        "auto": "",
        "自动识别": "",
    }
    return aliases.get(selected, selected)


def _infer_from_content(code: str) -> LanguageDetection:
    scores = {language: 0 for language in SUPPORTED_LANGUAGES if language != "other"}
    indicators = {
        "python": [
            (r"(?m)^\s*(?:from\s+\w[\w.]*\s+import|import\s+\w[\w.]*)", 3),
            (r"(?m)^\s*(?:async\s+)?def\s+\w+\s*\(", 4),
            (r"(?m)^\s*class\s+\w+(?:\([^)]*\))?\s*:", 3),
            (r"\b(?:None|True|False|self)\b", 1),
            (r"\b(?:input|print)\s*\(", 2),
            (r"\b(?:os|subprocess|pathlib|json|re)\.", 2),
        ],
        "java": [
            (r"\bpublic\s+(?:static\s+)?(?:class|interface|enum)\b", 5),
            (r"\bSystem\.out\.print(?:ln)?\s*\(", 3),
            (r"\b(?:private|protected|public)\s+(?:static\s+)?[A-Z\w<>\[\]]+\s+\w+", 2),
            (r"\bpackage\s+[\w.]+\s*;", 3),
        ],
        "typescript": [
            (r"\b(?:interface|type|enum|namespace)\s+\w+", 4),
            (r"\b(?:const|let|var)\s+\w+\s*:\s*[A-Za-z_{[]", 3),
            (r"\([^)]*\w+\s*:\s*[A-Za-z_{[]", 3),
            (r"\bas\s+(?:const|[A-Z]\w*)\b", 2),
        ],
        "javascript": [
            (r"\b(?:const|let|var)\s+\w+\s*=", 2),
            (r"\b(?:function\s+\w+|=>)\b", 3),
            (r"\b(?:console\.log|document\.|require\s*\(|module\.exports)\b", 2),
        ],
        "sql": [
            (r"(?i)\bSELECT\b[\s\S]+\bFROM\b", 5),
            (r"(?i)\b(?:INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|CREATE\s+TABLE)\b", 5),
            (r"(?i)\b(?:JOIN|GROUP\s+BY|ORDER\s+BY|WHERE)\b", 2),
        ],
    }
    for language, patterns in indicators.items():
        scores[language] = sum(weight for pattern, weight in patterns if re.search(pattern, code))

    language, score = max(scores.items(), key=lambda item: item[1])
    if score == 0:
        return LanguageDetection("other", "fallback", 0.2)
    sorted_scores = sorted(scores.values(), reverse=True)
    margin = score - sorted_scores[1]
    confidence = min(0.98, 0.55 + score * 0.04 + margin * 0.03)
    return LanguageDetection(language, "content", round(confidence, 2))


def detect_language(code: str, language: str | None = None, filename: str | None = None) -> LanguageDetection:
    selected = _normalize_selected(language)
    if selected in SUPPORTED_LANGUAGES:
        return LanguageDetection(selected, "explicit", 1.0)

    suffix = Path(filename or "").suffix.lower()
    by_extension = EXTENSION_LANGUAGE_MAP.get(suffix)
    if by_extension and by_extension != "other":
        return LanguageDetection(by_extension, "filename", 0.98)

    return _infer_from_content(code)


def normalize_language(language: str | None, filename: str | None = None, code: str = "") -> str:
    """Backward-compatible helper returning only the normalized language name."""
    return detect_language(code, language, filename).language
