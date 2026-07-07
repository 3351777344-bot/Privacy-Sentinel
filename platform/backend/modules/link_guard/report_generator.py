PENALTY = {"high": 30, "medium": 15, "low": 0}


def build_link_report(normalized_url: str, checks: list[dict], suspicious_params: list[dict], source_risk: dict) -> dict:
    risk_items = [item["riskLevel"] for item in checks if item["status"] != "pass"]
    if source_risk["riskLevel"] in {"high", "medium"}:
        risk_items.append(source_risk["riskLevel"])

    score = max(0, 100 - sum(PENALTY.get(level, 0) for level in risk_items))
    if "high" in risk_items:
        risk_level = "high"
    elif "medium" in risk_items:
        risk_level = "medium"
    else:
        risk_level = "low"

    warnings = [item["label"] for item in checks if item["status"] != "pass"]
    if source_risk["riskLevel"] != "low":
        warnings.append(f"来源：{source_risk['source']}")

    if warnings:
        summary = f"该链接命中 {'、'.join(warnings[:4])} 等风险点，建议核实来源后再决定是否打开。"
    else:
        summary = "该链接未命中明显高风险规则，但打开前仍建议确认来源和域名。"

    suggestions = [
        "不要直接在该链接中输入账号密码、验证码、身份证号或银行卡号。",
        "涉及缴费、退款、奖学金、账号验证时，优先通过官方 App 或官网重新访问。",
        "如果链接来自聊天、短信或二维码，先向可信渠道核实发送者身份。",
    ]
    if risk_level == "low":
        suggestions = [
            "打开前确认域名与预期服务一致。",
            "不要在陌生页面填写敏感个人信息。",
        ]

    return {
        "riskLevel": risk_level,
        "score": score,
        "summary": summary,
        "normalizedUrl": normalized_url,
        "checks": checks,
        "suspiciousParams": suspicious_params,
        "sourceRisk": source_risk,
        "suggestions": suggestions,
        "shouldOpen": risk_level == "low",
    }

