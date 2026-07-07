from .language_detector import normalize_language
from .report_generator import build_report
from .rules import iter_findings


def analyze_code(code: str, language: str | None = None, filename: str | None = None) -> dict:
    detected_language = normalize_language(language, filename)
    vulnerabilities = iter_findings(code or "", detected_language)
    return build_report(detected_language, vulnerabilities)

