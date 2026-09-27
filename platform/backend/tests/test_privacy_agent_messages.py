"""Honesty contract for the privacy agent's user-facing engine messages.

Two rules are enforced here, because the app renders ``summary`` and
``detectorMessage`` verbatim:

1. The detector must never claim that an online model analysed an image when the
   model was not actually called. A false claim is a visible correctness
   problem, not just a wording nit.
2. The messages must never leak internal identifiers (engine, model, dependency
   or environment-variable names). Users read the result, not the stack.
"""
from types import SimpleNamespace

import pytest

from detector import deepseek_privacy, privacy_agent, vision_detector
from schemas.models import Box, DetectResponse, PrivacyItem


# Tokens that only exist inside the implementation. Derived from the configured
# engines/models below, so the assertion fails the moment a message starts
# echoing configuration back at the user.
INTERNAL_TOKENS = (
    "deepseek",
    "vision_api",
    "hybrid mode",
    "deepseek mode",
    "rapidocr",
    "opencv",
    "ocr",
    "agent",
    "api",
    "GUARDIANHUB_",
    "finish_reason",
    "payload",
    "items",
)


def _assert_no_internal_tokens(*messages: str) -> None:
    for message in messages:
        lowered = message.lower()
        for token in INTERNAL_TOKENS:
            assert token.lower() not in lowered, f"internal token {token!r} leaked into {message!r}"


def _settings(*, vision_enabled: bool, api_key: str = "test-key") -> SimpleNamespace:
    """Settings deliberately full of internal identifiers.

    These values are inputs to the detector; the tests below prove none of them
    is echoed into a user-facing message.
    """
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
        detectorMessage="已在本机完成图片文字与二维码检查。",
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


def test_agent_message_states_the_check_stayed_local(monkeypatch) -> None:
    """The local-only path must say the image was never sent out."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(vision_enabled=False)
    monkeypatch.setattr(privacy_agent, "_detect_faces", lambda *a, **k: [])
    try:
        response = privacy_agent._detect_agent(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
        unavailable = privacy_agent._detect_agent(
            _base_result().model_copy(update={"detectorMode": "unavailable"}),
            "unused.png",
            "img_test",
            "/static/x.png",
            400,
            200,
        )
    finally:
        privacy_agent.settings = original

    assert "本机" in response.detectorMessage
    assert "未发送给外部模型" in response.detectorMessage
    assert "检测到 1 个隐私区域" in response.summary
    assert "人工复核" in unavailable.detectorMessage
    _assert_no_internal_tokens(response.summary, response.detectorMessage)
    _assert_no_internal_tokens(unavailable.summary, unavailable.detectorMessage)


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
    assert "未启用" in response.detectorMessage
    assert "已上传到服务端" in response.detectorMessage
    assert "未发送给外部模型" in response.detectorMessage
    assert "联网分析新增" not in response.summary
    assert "联网图像分析未启用" in response.summary
    assert "未发送给外部模型" in response.summary
    assert "本地检测发现" in response.summary
    assert response.detectorMode == "hybrid"
    _assert_no_internal_tokens(response.summary, response.detectorMessage)


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

    assert "联网图像分析" in response.detectorMessage
    assert "未启用" not in response.detectorMessage
    assert "未发送给外部模型" not in response.detectorMessage
    assert "联网分析新增" in response.summary
    _assert_no_internal_tokens(response.summary, response.detectorMessage)


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
    assert "未发送给外部模型" in response.detectorMessage
    _assert_no_internal_tokens(response.summary, response.detectorMessage)


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
    assert "已保留本机识别结果" in response.detectorMessage
    _assert_no_internal_tokens(response.summary, response.detectorMessage)


def test_online_text_path_messages_are_user_facing(monkeypatch) -> None:
    """Every branch of the online text pipeline stays honest and jargon-free."""
    original = privacy_agent.settings
    privacy_agent.settings = _settings(vision_enabled=True)
    monkeypatch.setattr(
        privacy_agent, "_run_ocr", lambda *a, **k: (["13800138000"], [[[0, 0], [10, 0], [10, 10], [0, 10]]], [0.99])
    )
    try:
        analysed_item = PrivacyItem(
            id="img_test_ds_1",
            type="phone",
            label="手机号",
            text="13800138000",
            riskLevel="high",
            box=Box(x=0, y=0, width=10, height=10),
            suggestion="建议遮挡此区域后再分享。",
            source="deepseek",
        )
        monkeypatch.setattr(deepseek_privacy, "analyze_ocr_text", lambda *a, **k: ([analysed_item], None))
        analysed = privacy_agent._detect_deepseek(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )

        monkeypatch.setattr(deepseek_privacy, "analyze_ocr_text", lambda *a, **k: ([], None))
        no_hits = privacy_agent._detect_deepseek(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )

        monkeypatch.setattr(
            deepseek_privacy,
            "analyze_ocr_text",
            lambda *a, **k: ([], "联网语义分析未启用，已保留本机检测结果。"),
        )
        failed = privacy_agent._detect_deepseek(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )

        monkeypatch.setattr(privacy_agent, "_run_ocr", lambda *a, **k: ([], [], []))
        monkeypatch.setattr(deepseek_privacy, "analyze_ocr_text", lambda *a, **k: ([], None))
        nothing_read = privacy_agent._detect_deepseek(
            _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
        )
    finally:
        privacy_agent.settings = original

    assert "联网语义分析" in analysed.summary
    assert "本机" in analysed.detectorMessage
    assert "联网语义分析" in analysed.detectorMessage

    assert "本机" in no_hits.detectorMessage
    assert "未发现额外隐私项" in no_hits.summary

    # Failure keeps the contract: no claim that the model ran, and the local
    # result is explicitly preserved.
    assert "未启用" in failed.summary
    assert "已保留本机检测结果" in failed.summary
    assert "本机" in failed.detectorMessage

    # Nothing readable -> fall back to whatever the local pass already reported.
    assert nothing_read.summary == "本地检测到 1 个隐私区域。"

    for response in (analysed, no_hits, failed, nothing_read):
        _assert_no_internal_tokens(response.summary, response.detectorMessage)
