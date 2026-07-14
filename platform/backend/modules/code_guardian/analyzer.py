from config import settings

from .language_detector import detect_language
from .report_generator import build_report
from .rules import iter_findings


def _deepseek_analyze(code: str, language: str) -> list[dict]:
    from .llm_analyzer import analyze_with_deepseek

    try:
        return analyze_with_deepseek(code, language)
    except Exception:
        return []


def analyze_code(code: str, language: str | None = None, filename: str | None = None) -> dict:
    detection = detect_language(code or "", language, filename)
    detected_lang = detection.language

    local_findings = iter_findings(code or "", detected_lang)
    detector_source = "rule"

    if settings.code_engine == "deepseek":
        deepseek_findings = _deepseek_analyze(code or "", detected_lang)
        if deepseek_findings:
            seen = {(f.get("type"), f.get("line")) for f in local_findings}
            for df in deepseek_findings:
                key = (df.get("type"), df.get("line"))
                if key not in seen:
                    local_findings.append(df)
                    seen.add(key)
            detector_source = "deepseek"

    result = build_report(detection, local_findings)
    result["detectorSource"] = detector_source
    return result
