from modules.risk_scoring import calculate_security_score, highest_risk

from .language_detector import LanguageDetection


def calculate_score(vulnerabilities: list[dict]) -> int:
    return calculate_security_score([item["riskLevel"] for item in vulnerabilities])


def calculate_risk_level(vulnerabilities: list[dict]) -> str:
    return highest_risk([item["riskLevel"] for item in vulnerabilities])


def build_report(detection: LanguageDetection, vulnerabilities: list[dict]) -> dict:
    risk_level = calculate_risk_level(vulnerabilities)
    score = calculate_score(vulnerabilities)
    suggestions = list(dict.fromkeys(item["suggestion"] for item in vulnerabilities))

    if not suggestions:
        suggestions = [
            "当前未命中高危本地规则，提交前仍建议复核依赖、配置文件和测试数据。",
            "不要把真实账号、密钥、证书或个人信息提交到代码仓库。",
        ]

    if vulnerabilities:
        high_count = sum(1 for item in vulnerabilities if item["riskLevel"] == "high")
        medium_count = sum(1 for item in vulnerabilities if item["riskLevel"] == "medium")
        summary = f"检测到 {len(vulnerabilities)} 项代码安全风险，其中 high {high_count} 项、medium {medium_count} 项，建议修复后再提交。"
    else:
        summary = "当前代码未命中本地高危规则，整体风险较低。"

    return {
        "riskLevel": risk_level,
        "score": score,
        "summary": summary,
        "language": detection.language,
        "languageSource": detection.source,
        "languageConfidence": detection.confidence,
        "vulnerabilities": vulnerabilities,
        "suggestions": suggestions,
        "shouldSubmit": risk_level == "low",
    }
