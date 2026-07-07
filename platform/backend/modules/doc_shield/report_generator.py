from typing import Any

from .file_extractor import ExtractedFile


def _score_for_checks(checks: list[dict[str, Any]]) -> int:
    score = 100
    for check in checks:
        if check.get("status") == "fail":
            score -= 18
        elif check.get("status") == "warning":
            score -= 9

        if check.get("riskLevel") == "high":
            score -= 8
        elif check.get("riskLevel") == "medium":
            score -= 4
    return max(0, min(100, score))


def _risk_level(score: int, checks: list[dict[str, Any]]) -> str:
    if any(check.get("riskLevel") == "high" for check in checks) or score < 60:
        return "high"
    if any(check.get("riskLevel") == "medium" for check in checks) or score < 85:
        return "medium"
    return "low"


def _suggestions(checks: list[dict[str, Any]]) -> list[str]:
    suggestions: list[str] = []
    if any(check.get("category") == "format" and check.get("status") != "pass" for check in checks):
        suggestions.append("按提交要求重新核对文件后缀、文件名分隔符、学号姓名和材料类型，避免使用“最终版”“未命名”等临时文件名。")
    if any(check.get("category") == "completeness" and check.get("status") != "pass" for check in checks):
        suggestions.append("补齐缺失的封面、摘要、正文、参考文献、源码、截图或 PPT 等必要材料，并在文件名或正文标题中保留清晰关键词。")
    if any(check.get("category") == "privacy" and check.get("riskLevel") in {"high", "medium"} for check in checks):
        suggestions.append("提交前删除或遮盖无关手机号、身份证号、银行卡号、家庭住址、紧急联系人等个人敏感信息。")
    if not suggestions:
        suggestions.append("当前材料基础检查通过，正式提交前仍建议人工复核学校通知、截止时间和附件清单。")
    suggestions.append("将最终提交包另存为一份确认版，避免覆盖原始材料。")
    return suggestions


def generate_report(
    parsed_requirements: dict[str, Any],
    files: list[ExtractedFile],
    checks: list[dict[str, Any]],
) -> dict[str, Any]:
    score = _score_for_checks(checks)
    risk_level = _risk_level(score, checks)
    failed = sum(1 for check in checks if check.get("status") == "fail")
    warnings = sum(1 for check in checks if check.get("status") == "warning")

    if risk_level == "high":
        summary = f"发现 {failed} 项高优先级问题，建议修正后再提交。"
    elif risk_level == "medium":
        summary = f"材料基本可检查，但仍有 {warnings} 项需要复核。"
    else:
        summary = "材料格式、清单和隐私风险未发现明显问题，可进入人工最终确认。"

    return {
        "riskLevel": risk_level,
        "score": score,
        "summary": summary,
        "parsedRequirements": parsed_requirements,
        "files": [
            {
                "fileName": file.fileName,
                "extension": file.extension,
                "contentType": file.contentType,
                "size": file.size,
                "status": file.status,
                "wordCount": file.wordCount,
                "pageCount": file.pageCount,
            }
            for file in files
        ],
        "checks": checks,
        "suggestions": _suggestions(checks),
    }
