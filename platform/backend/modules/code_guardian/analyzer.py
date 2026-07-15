from config import settings

from .language_detector import detect_language
from .report_generator import build_report
from .rules import iter_findings


def _deepseek_analyze(code: str, language: str) -> tuple[list[dict], str | None]:
    from .llm_analyzer import analyze_with_deepseek

    try:
        findings = analyze_with_deepseek(code, language)
        if not findings and (settings.deepseek_enabled and settings.deepseek_api_key):
            # DeepSeek was configured but returned nothing (likely API error)
            return [], "DeepSeek AI 分析返回为空，仅显示本地规则检测结果。请检查 API 配置或网络连接。"
        return findings, None
    except Exception:
        return [], "DeepSeek AI 分析不可用，仅显示本地规则检测结果。"


def analyze_code(code: str, language: str | None = None, filename: str | None = None) -> dict:
    detection = detect_language(code or "", language, filename)
    detected_lang = detection.language

    local_findings = iter_findings(code or "", detected_lang)
    detector_source = "rule"
    deepseek_warning: str | None = None

    if settings.code_engine == "deepseek":
        deepseek_findings, deepseek_warning = _deepseek_analyze(code or "", detected_lang)
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
    if deepseek_warning:
        result["deepseekWarning"] = deepseek_warning
    return result
