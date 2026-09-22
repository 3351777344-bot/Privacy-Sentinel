"""Honesty contract for the privacy agent's user-facing engine messages.

The detector must never claim that Qwen VL analysed an image when the model was
not actually called. These messages are surfaced verbatim in the app, so a false
claim is a visible correctness problem, not just a wording nit.
"""
from types import SimpleNamespace

import pytest

from detector import privacy_agent
from schemas.models import Box, DetectResponse, PrivacyItem


def _settings(*, qwen_enabled: bool, qwen_api_key: str = "test-key") -> SimpleNamespace:
    return SimpleNamespace(
        qwen_enabled=qwen_enabled,
        qwen_api_key=qwen_api_key,
        qwen_model="qwen3-vl-flash",
        ocr_engine="rapidocr",
        qr_engine="opencv",
        face_engine="disabled",
        default_mask_type="mosaic",
        demo_mode=False,
    )


def _base_result() -> DetectResponse:
    item = PrivacyItem(
        id="img_test_phone_1",
        type="phone",
        label="手机号",
        text="138****5678",
        riskLevel="high",
        box=Box(x=10, y=20, width=80, height=20),
        suggestion="遮挡后再分享。",
        source="ocr",
        recommendedMaskType="black",
    )
    return DetectResponse(
        imageId="img_test",
        originalImageUrl="/static/uploads/img_test.png",
        riskLevel="high",
        score=72,
        summary="本地检测到 1 个隐私区域。",
        detectorMode="ocr",
        detectorMessage="已使用本地 OCR 与二维码检测引擎分析图片。",
        items=[item],
    )


@pytest.mark.parametrize(
    ("enabled", "api_key"),
    [(False, "test-key"), (True, ""), (False, "")],
)
def test_qwen_active_requires_flag_and_key(enabled: bool, api_key: str) -> None:
    assert privacy_agent._qwen_active() is False
    original = privacy_agent.settings
    try:
        privacy_agent.settings = _settings(qwen_enabled=enabled, qwen_api_key=api_key)
        assert privacy_agent._qwen_active() is False
        privacy_agent.settings = _settings(qwen_enabled=True, qwen_api_key="k")
        assert privacy_agent._qwen_active() is True
    finally:
        privacy_agent.settings = original


def test_hybrid_does_not_claim_qwen_when_disabled(monkeypatch) -> None:
    """Qwen off -> the message must state it never left the device."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(qwen_enabled=False)
    monkeypatch.setattr(
        privacy_agent, "_detect_faces", lambda *a, **k: []
    )
    try:
        response = privacy_agent._detect_hybrid(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    # No claim of a joint analysis, and no mention of the model being called.
    assert "联合分析" not in response.detectorMessage
    assert "Qwen VL 未启用" in response.detectorMessage
    assert "未联网" in response.detectorMessage
    assert "Qwen VL 新增" not in response.summary
    assert "Qwen VL 未启用" in response.summary
    assert "本地检测发现" in response.summary
    assert response.detectorMode == "hybrid"


def test_hybrid_reports_joint_analysis_when_qwen_active(monkeypatch) -> None:
    """Qwen on -> the joint-analysis wording is legitimate."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(qwen_enabled=True)
    monkeypatch.setattr(privacy_agent, "_detect_faces", lambda *a, **k: [])
    monkeypatch.setattr(
        privacy_agent, "enhance_with_qwen", lambda items, *a, **k: list(items), raising=False
    )
    try:
        response = privacy_agent._detect_hybrid(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    assert "联合分析" in response.detectorMessage
    assert "Qwen VL 新增" in response.summary


def test_vision_api_disabled_reports_disabled_not_failure(monkeypatch) -> None:
    """Disabled is not the same as broken: the message must not say 'failed'."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(qwen_enabled=False)
    monkeypatch.setattr(privacy_agent, "detect_with_qwen", lambda *a, **k: [], raising=False)
    try:
        response = privacy_agent._detect_vision_api(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    assert response.detectorMode == "ocr"
    assert "未启用" in response.detectorMessage
    assert "调用失败" not in response.detectorMessage


def test_vision_api_enabled_reports_real_failure(monkeypatch) -> None:
    """Enabled but returning nothing is a genuine failure and should say so."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(qwen_enabled=True)
    monkeypatch.setattr(privacy_agent, "detect_with_qwen", lambda *a, **k: [], raising=False)
    try:
        response = privacy_agent._detect_vision_api(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    assert "调用失败" in response.detectorMessage
    assert "未启用" not in response.detectorMessage
