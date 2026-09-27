"""Honesty contract for the privacy agent's user-facing engine messages.

The detector must never claim that DeepSeek vision analysed an image when the
model was not actually called. These messages are surfaced verbatim in the app,
so a false claim is a visible correctness problem, not just a wording nit.
"""
from types import SimpleNamespace

import pytest

from detector import privacy_agent, vision_detector
from schemas.models import Box, DetectResponse, PrivacyItem


def _settings(*, vision_enabled: bool, api_key: str = "test-key") -> SimpleNamespace:
    return SimpleNamespace(
        deepseek_enabled=vision_enabled,
        deepseek_api_key=api_key,
        deepseek_model="deepseek-flash",
        deepseek_vision_model="deepseek-flash",
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
def test_vision_active_requires_flag_and_key(enabled: bool, api_key: str) -> None:
    original = privacy_agent.settings
    try:
        privacy_agent.settings = _settings(vision_enabled=enabled, api_key=api_key)
        assert privacy_agent._vision_active() is False
        privacy_agent.settings = _settings(vision_enabled=True, api_key="k")
        assert privacy_agent._vision_active() is True
    finally:
        privacy_agent.settings = original


def test_hybrid_does_not_claim_vision_when_disabled(monkeypatch) -> None:
    """Vision off -> the message must state it never left the device."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(vision_enabled=False)
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
    assert "DeepSeek 未启用" in response.detectorMessage
    assert "已上传到后端" in response.detectorMessage
    assert "未发送给外部模型" in response.detectorMessage
    assert "DeepSeek 视觉新增" not in response.summary
    assert "DeepSeek 视觉未启用" in response.summary
    assert "本地检测发现" in response.summary
    assert response.detectorMode == "hybrid"


def test_hybrid_reports_joint_analysis_when_vision_active(monkeypatch) -> None:
    """Vision on -> the joint-analysis wording is legitimate."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(vision_enabled=True)
    monkeypatch.setattr(privacy_agent, "_detect_faces", lambda *a, **k: [])
    monkeypatch.setattr(
        vision_detector, "enhance_with_vision", lambda items, *a, **k: list(items)
    )
    try:
        response = privacy_agent._detect_hybrid(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    assert "联合分析" in response.detectorMessage
    assert "DeepSeek 视觉新增" in response.summary


def test_vision_api_disabled_reports_disabled_not_failure(monkeypatch) -> None:
    """Disabled is not the same as broken: the message must not say 'failed'."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(vision_enabled=False)
    monkeypatch.setattr(vision_detector, "detect_with_vision", lambda *a, **k: [])
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
    privacy_agent.settings = _settings(vision_enabled=True)
    monkeypatch.setattr(vision_detector, "detect_with_vision", lambda *a, **k: [])
    try:
        response = privacy_agent._detect_vision_api(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    assert "调用失败" in response.detectorMessage
    assert "未启用" not in response.detectorMessage
