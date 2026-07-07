RISK_PENALTY = {"high": 25, "medium": 15, "low": 5}


def calculate_score(vulnerabilities: list[dict]) -> int:
    penalty = sum(RISK_PENALTY.get(item["riskLevel"], 0) for item in vulnerabilities)
    return max(0, 100 - penalty)


def calculate_risk_level(vulnerabilities: list[dict]) -> str:
    levels = {item["riskLevel"] for item in vulnerabilities}
    if "high" in levels:
        return "high"
    if "medium" in levels:
        return "medium"
    return "low"


def build_report(language: str, vulnerabilities: list[dict]) -> dict:
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
        "language": language,
        "vulnerabilities": vulnerabilities,
        "suggestions": suggestions,
        "shouldSubmit": risk_level == "low",
    }

