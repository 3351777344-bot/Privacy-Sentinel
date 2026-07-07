SOURCE_RISK_MAP = {
    "陌生人私信": ("high", "陌生人私信中的链接常见于钓鱼、中奖、兼职或账号验证场景。"),
    "短信": ("medium", "陌生短信中的链接常见于快递异常、账号验证、补贴领取等风险场景。"),
    "客服": ("medium", "客服身份需要核实，冒充客服常用于诱导退款、转账或下载应用。"),
    "二手交易": ("medium", "二手交易场景中跳转链接可能诱导脱离平台付款或泄露账号信息。"),
    "学校通知": ("medium", "学校通知类链接需要核实来源，优先通过学校官网或官方 App 访问。"),
    "群聊": ("medium", "群聊链接来源复杂，建议确认发送者身份和上下文。"),
    "邮件": ("medium", "邮件链接可能伪装为系统通知、奖学金或账号验证邮件。"),
    "二维码": ("medium", "二维码会隐藏真实 URL，打开前建议先解析并核对域名。"),
    "其他": ("low", "未提供高风险来源，但仍建议核对域名和页面内容。"),
}


def evaluate_source(source: str | None) -> dict:
    normalized = (source or "其他").strip() or "其他"
    risk_level, reason = SOURCE_RISK_MAP.get(normalized, SOURCE_RISK_MAP["其他"])
    return {"source": normalized, "riskLevel": risk_level, "reason": reason}

