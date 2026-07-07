import re

from .file_extractor import ExtractedFile


PRIVACY_RULES = [
    ("手机号", r"(?<!\d)1[3-9]\d{9}(?!\d)", "high"),
    ("身份证号", r"(?<!\d)\d{17}[\dXx](?!\d)", "high"),
    ("银行卡号", r"(?<!\d)(?:\d[ -]?){16,19}(?!\d)", "high"),
    ("地址关键词", r"(?:身份证住址|家庭住址|现住址|详细地址|宿舍|小区|街道|门牌号|[省市区县路街巷弄]\d{1,4}号)", "medium"),
    ("过度暴露的个人信息", r"(?:身份证|学号|手机号|电话|邮箱|QQ|微信|家庭住址|父母|紧急联系人)", "medium"),
]


def _excerpt(text: str, match: re.Match[str]) -> str:
    start = max(match.start() - 12, 0)
    end = min(match.end() + 12, len(text))
    return text[start:end].replace("\n", " ")


def check_privacy(files: list[ExtractedFile]) -> list[dict[str, str]]:
    checks: list[dict[str, str]] = []

    for file in files:
        if not file.text.strip():
            continue

        for label, pattern, level in PRIVACY_RULES:
            match = re.search(pattern, file.text, flags=re.IGNORECASE)
            if match:
                checks.append(
                    {
                        "category": "privacy",
                        "label": f"{label}风险",
                        "evidence": f"{file.fileName}：{_excerpt(file.text, match)}",
                        "riskLevel": level,
                        "status": "warning" if level == "medium" else "fail",
                    }
                )

    if not checks:
        checks.append(
            {
                "category": "privacy",
                "label": "未发现典型隐私风险",
                "evidence": "已检查可解析文本中的手机号、身份证号、银行卡号和地址关键词。",
                "riskLevel": "low",
                "status": "pass",
            }
        )

    return checks
