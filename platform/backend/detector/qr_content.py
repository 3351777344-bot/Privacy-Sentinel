"""Classify a decoded QR payload so the report states the real risk.

A QR code is not a risk by itself — the payload decides. Sharing a university
event poster is harmless; sharing a payment code leaks a live payment credential.
Reporting every code as "high" hides that distinction and trains users to ignore
the finding, so this module derives the label, level and user-facing advice from
the decoded value.

The payload never leaves the process: classification is local string work.
"""
from __future__ import annotations

import re

# Alipay/WeChat payment and collection codes are long pure-digit payloads.
# Deliberately length-gated so an order number or student id is not mistaken
# for a payment credential.
_PAYMENT_CODE = re.compile(r"^(?:\d{16,32})$")
_PAYMENT_URL = re.compile(
    r"(?:qr\.alipay\.com|render\.alipay\.com|wxp://|weixin://wxpay|payapp|"
    r"h5\.alipay|alipays://platformapi/startapp.*?(?:pay|qrpay))",
    re.IGNORECASE,
)
_WIFI = re.compile(r"^WIFI:", re.IGNORECASE)
_VCARD = re.compile(r"^BEGIN:VCARD", re.IGNORECASE)
_URL = re.compile(r"^https?://", re.IGNORECASE)
_EMAIL = re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", re.IGNORECASE)
_PHONE = re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")
_LONG_DIGITS = re.compile(r"^\d{11,}$")
# Secret-bearing query parameters must not be echoed back, otherwise the report
# itself leaks the credential the user was being warned about.
_SECRET_QUERY = re.compile(
    r"((?:token|key|api[_-]?key|access[_-]?key|secret|password|passwd|pwd|"
    r"sign|signature|session|auth|code)=)[^&#\s]+",
    re.IGNORECASE,
)


def _preview(value: str, keep: int = 4) -> str:
    """Short, non-reversible hint. Never echoes the full payload."""
    compact = re.sub(r"\s+", "", value)
    if len(compact) <= keep * 2:
        return "内容已隐藏"
    return f"{compact[:keep]}…{compact[-keep:]}"


def _redact(value: str) -> str:
    redacted = _SECRET_QUERY.sub(r"\1***", value)
    redacted = _EMAIL.sub("***@***", redacted)
    redacted = _PHONE.sub("1**********", redacted)
    return redacted[:60]


def classify_qr_payload(value: str) -> dict:
    """Map a decoded QR payload to label / risk / advice.

    Returns a dict with ``label``, ``riskLevel``, ``text`` and ``suggestion``.
    """
    payload = (value or "").strip()
    if not payload:
        return {
            "label": "二维码",
            "riskLevel": "medium",
            "text": "二维码内容为空或无法解码",
            "suggestion": "未解出内容时无法判断风险，建议遮挡或向发送者确认。",
        }

    # --- live payment / collection credentials: the one case worth shouting about
    if _PAYMENT_CODE.match(payload) or _PAYMENT_URL.search(payload):
        return {
            "label": "收款码/付款码",
            "riskLevel": "high",
            "text": _preview(payload),
            "suggestion": (
                "这是支付凭证，他人可凭此向你收款或发起付款，"
                "请勿公开分享；确需收款请改用平台内的临时收款链接。"
            ),
        }

    # --- linked destination: reuse the Link Guard rules instead of guessing
    if _URL.match(payload):
        try:
            from modules.link_guard.analyzer import analyze_link

            report = analyze_link(payload, "二维码")
            risk = str(report.get("riskLevel") or "low")
            findings = report.get("checks") or []
            risky = [c for c in findings if c.get("riskLevel") in {"medium", "high"}]
            if risky:
                # Prefer the most severe check, but among equals prefer the one
                # that actually describes the destination — a bare "HTTPS 检查"
                # is less informative than "短链接检查". Matched on label because
                # url_rules uses opaque ids (link_002) for these checks.
                order = {"high": 0, "medium": 1, "low": 2}
                informative_labels = (
                    "短链接",
                    "IP 地址",
                    "内网",
                    "国际化域名",
                    "域名结构",
                    "域名信誉",
                    "可疑关键词",
                    "可疑参数",
                    "URL 长度",
                )
                risky.sort(
                    key=lambda c: (
                        order.get(str(c.get("riskLevel")), 3),
                        0
                        if any(tag in str(c.get("label")) for tag in informative_labels)
                        else 1,
                    )
                )
                top = risky[0]
                return {
                    "label": f"链接二维码（{top.get('label')}）",
                    "riskLevel": risk if risk in {"low", "medium", "high"} else "medium",
                    "text": _redact(payload),
                    "suggestion": str(
                        top.get("message")
                        or "二维码指向的链接存在可疑特征，访问前请通过官方入口核实。"
                    ),
                }
            return {
                "label": "链接二维码",
                "riskLevel": "low",
                "text": _redact(payload),
                "suggestion": "链接未命中已知风险特征，但二维码可被替换，访问前请确认来源。",
            }
        except Exception:  # noqa: BLE001 - classification must never break detection
            return {
                "label": "链接二维码",
                "riskLevel": "medium",
                "text": _redact(payload),
                "suggestion": "二维码指向外部链接，建议确认来源后再访问。",
            }

    # --- Wi-Fi credentials: contains a password when generated by the system
    if _WIFI.match(payload):
        return {
            "label": "Wi-Fi 连接码",
            "riskLevel": "high",
            "text": "内容已隐藏（含网络口令）",
            "suggestion": "该码包含 Wi-Fi 名称与口令，分享后会泄露网络访问权限，建议遮挡。",
        }

    # --- contact card
    if _VCARD.match(payload):
        return {
            "label": "名片二维码",
            "riskLevel": "medium",
            "text": "内容已隐藏（含联系方式）",
            "suggestion": "名片码包含姓名与联系方式，会暴露个人账号信息，建议确认后再分享。",
        }

    # --- plain text payload that itself carries private data
    if _PHONE.search(payload) or _EMAIL.search(payload):
        return {
            "label": "含隐私信息的二维码",
            "riskLevel": "medium",
            "text": _preview(payload),
            "suggestion": "二维码内容包含联系方式等个人信息，建议遮挡。",
        }

    # --- long pure-digit payloads: could be an account or order identifier
    if _LONG_DIGITS.match(payload):
        return {
            "label": "数字编码二维码",
            "riskLevel": "medium",
            "text": _preview(payload),
            "suggestion": "该码是一串数字编码，可能是账号或订单标识，建议确认用途后再分享。",
        }

    # --- anything else: report presence without inventing risk
    return {
        "label": "二维码（文本）",
        "riskLevel": "low",
        "text": _preview(payload),
        "suggestion": "检出的二维码为普通文本内容，未发现敏感信息；如非本人预期请遮挡。",
    }
