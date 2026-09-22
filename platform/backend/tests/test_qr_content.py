"""QR payload classification: the label and risk must reflect the real content.

The previous behaviour reported every detected QR code as `high` with the text
"二维码内容已隐藏", even though the payload was decoded and then discarded. That
flags a university event poster and a live payment code identically, which both
hides the real risk and trains users to ignore the finding.
"""
import pytest

from detector.qr_content import classify_qr_payload


@pytest.mark.parametrize(
    "payload",
    [
        "wxp://f2f0abcdef123456",
        "https://qr.alipay.com/abc123def",
        "2847591029384756",
        "1234567890123456789012",
    ],
)
def test_payment_credentials_are_high_risk(payload: str) -> None:
    result = classify_qr_payload(payload)
    assert result["riskLevel"] == "high"
    assert result["label"] == "收款码/付款码"
    assert "支付凭证" in result["suggestion"]


def test_payment_code_payload_is_not_echoed_in_full() -> None:
    """A payment credential must never be printed back to the user."""
    payload = "2847591029384756"
    result = classify_qr_payload(payload)
    assert payload not in result["text"]


def test_wifi_code_is_high_risk() -> None:
    result = classify_qr_payload("WIFI:T:WPA;S:Campus;P:hunter2;;")
    assert result["riskLevel"] == "high"
    assert result["label"] == "Wi-Fi 连接码"


def test_vcard_is_medium_risk() -> None:
    result = classify_qr_payload("BEGIN:VCARD\nFN:Zhang\nTEL:13812345678")
    assert result["riskLevel"] == "medium"
    assert result["label"] == "名片二维码"


def test_plain_text_payload_is_not_reported_as_high() -> None:
    """The old code called every code high; ordinary text must not be."""
    result = classify_qr_payload("GuardianHub 校园活动 2026")
    assert result["riskLevel"] == "low"
    assert result["label"] == "二维码（文本）"


def test_short_digit_payload_is_not_a_payment_code() -> None:
    """Length gating keeps order numbers / ids out of the payment bucket."""
    result = classify_qr_payload("2024001")
    assert result["label"] != "收款码/付款码"
    assert result["riskLevel"] != "high"


def test_clean_school_link_is_low_risk() -> None:
    result = classify_qr_payload("https://www.example.edu.cn/notice")
    assert result["riskLevel"] == "low"
    assert result["label"] == "链接二维码"


def test_shortener_link_is_medium_and_labels_the_shortener() -> None:
    """The label should describe the destination, not just say 'HTTPS 检查'."""
    result = classify_qr_payload("http://bit.ly/x7k2p")
    assert result["riskLevel"] in {"medium", "high"}
    assert "短链接" in result["label"]


def test_punycode_link_is_flagged() -> None:
    result = classify_qr_payload("https://xn--80ak6aa92e.com/verify")
    assert result["riskLevel"] in {"medium", "high"}
    assert "国际化域名" in result["label"] or "可疑关键词" in result["label"]


def test_ip_literal_link_is_high_risk() -> None:
    result = classify_qr_payload("http://10.0.0.1/login?token=abc")
    assert result["riskLevel"] == "high"


def test_text_payload_containing_phone_is_medium() -> None:
    result = classify_qr_payload("联系电话 13812345678")
    assert result["riskLevel"] == "medium"
    assert result["label"] == "含隐私信息的二维码"


def test_link_payload_redacts_credentials_in_query() -> None:
    result = classify_qr_payload("https://host.example/x?token=abcdef123456")
    assert "abcdef123456" not in result["text"]


def test_empty_payload_is_medium_and_explains_why() -> None:
    result = classify_qr_payload("")
    assert result["riskLevel"] == "medium"
    assert "无法" in result["text"] or "为空" in result["text"]
