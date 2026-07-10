from .language_detector import detect_language
from .report_generator import build_report
from .rules import iter_findings


def analyze_code(code: str, language: str | None = None, filename: str | None = None) -> dict:
    detection = detect_language(code or "", language, filename)
    vulnerabilities = iter_findings(code or "", detection.language)
    return build_report(detection, vulnerabilities)
