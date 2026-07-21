from config import settings

from .language_detector import detect_language
from .report_generator import build_report
from .rules import iter_findings


def _deepseek_analyze(code: str, language: str) -> tuple[list[dict], str | None, bool]:
    """Return (findings, warning, used_deepseek).

    ``used_deepseek`` is True only when DeepSeek was actually reached, so the
    caller can tell a genuine "no extra issues found" result apart from an API
    failure and avoid showing a misleading "check your API config" warning.
    """
    from .llm_analyzer import analyze_with_deepseek

    if not (settings.deepseek_enabled and settings.deepseek_api_key):
        return [], "DeepSeek 联网增强未启用，当前仅显示本地规则检测结果。", False

    try:
        findings, error = analyze_with_deepseek(code, language)
    except Exception:
        return [], "DeepSeek AI 调用异常，已回退本地规则检测结果。", False

    if error:
        return findings, error, False
    return findings, None, True


def analyze_code(
    code: str,
    language: str | None = None,
    filename: str | None = None,
    processing_mode: str | None = None,
) -> dict:
    detection = detect_language(code or "", language, filename)
    detected_lang = detection.language

    local_findings = iter_findings(code or "", detected_lang)
    detector_source = "rule"
    deepseek_warning: str | None = None

    engine = "rule" if processing_mode == "local" else settings.code_engine
    if processing_mode == "online":
        engine = "deepseek"

    if engine == "deepseek":
        deepseek_findings, deepseek_warning, used_deepseek = _deepseek_analyze(code or "", detected_lang)
        if used_deepseek:
            detector_source = "deepseek"
        if deepseek_findings:
            seen = {(f.get("type"), f.get("line")) for f in local_findings}
            for df in deepseek_findings:
                key = (df.get("type"), df.get("line"))
                if key not in seen:
                    local_findings.append(df)
                    seen.add(key)

    result = build_report(detection, local_findings)
    result["detectorSource"] = detector_source
    if deepseek_warning:
        result["deepseekWarning"] = deepseek_warning
    return result
