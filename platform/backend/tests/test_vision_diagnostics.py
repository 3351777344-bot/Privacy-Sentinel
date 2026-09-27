"""Vision failures must be diagnosable, retried once, and never silent.

The hosted backend is operated from the outside, so "online analysis failed"
without a reason was an unfixable report: the provider's answer (status, body,
truncated completion) only ever reached the server log. These tests pin the
diagnostics contract:

* every vision-first call records why it produced nothing,
* the recorded reason is copied into the response's internal detail field,
* an empty answer is reported as exactly that, not as a failure,
* a transient transport failure is retried before giving up.
"""
from __future__ import annotations

import time as time_module
from types import SimpleNamespace

import pytest

from detector import privacy_agent, vision_detector
from model_retry import ModelCallResult
from schemas.models import Box, DetectResponse, PrivacyItem


def _settings(*, enabled: bool = True, api_key: str = "test-key") -> SimpleNamespace:
    return SimpleNamespace(
        deepseek_enabled=enabled,
        deepseek_api_key=api_key,
        deepseek_api_base="https://example.invalid/v1",
        deepseek_model="deepseek-flash",
        deepseek_vision_model="deepseek-flash",
        deepseek_timeout_seconds=60,
        vision_image_max_side=1280,
        deepseek_max_tokens=2048,
        default_mask_type="mosaic",
        demo_mode=False,
    )


def _base_result(items: list[PrivacyItem] | None = None) -> DetectResponse:
    return DetectResponse(
        imageId="img_test",
        originalImageUrl="/static/uploads/img_test.png",
        riskLevel="low",
        score=100,
        summary="未识别到典型手机号、证件号、银行卡号、地址或二维码，分享前仍建议人工复核。",
        detectorMode="ocr",
        detectorMessage="已在本机完成图片文字与二维码检查。",
        items=items or [],
    )


def _item() -> PrivacyItem:
    return PrivacyItem(
        id="img_test_ocr_1",
        type="phone",
        label="手机号",
        text="138****5678",
        riskLevel="high",
        box=Box(x=10, y=20, width=80, height=20),
        suggestion="遮挡后再分享。",
    )


class _ProviderFailure(Exception):
    """Carries an HTTP verdict the way the SDK does."""

    def __init__(self, status_code: int, body: str = "model rejected image input") -> None:
        super().__init__(body)
        self.status_code = status_code
        self.response = SimpleNamespace(status_code=status_code, text=body)


def _install_transport(monkeypatch, outcomes: list[object]) -> list[int]:
    """Fake one vision request per entry; each entry is a result or an exception."""
    calls: list[int] = []

    def fake_request(image_path: str, prompt: str) -> tuple[str, str | None]:
        calls.append(len(calls) + 1)
        outcome = outcomes[min(len(calls) - 1, len(outcomes) - 1)]
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome  # type: ignore[return-value]

    monkeypatch.setattr(vision_detector, "_vision_request", fake_request)
    monkeypatch.setattr(vision_detector, "settings", _settings())
    # The backoff is real in production; here it only slows the suite down.
    monkeypatch.setattr(time_module, "sleep", lambda _seconds: None)
    return calls


def test_vision_first_failure_records_the_provider_reason(monkeypatch) -> None:
    monkeypatch.setattr(vision_detector, "settings", _settings())
    calls = _install_transport(monkeypatch, [_ProviderFailure(401, "invalid api key")])

    assert vision_detector._call_deepseek_vision("unused.png") == []

    detail = vision_detector._last_call_error()
    assert "401" in detail
    assert "invalid api key" in detail
    # 401 is permanent: retrying would only spend quota twice.
    assert len(calls) == 1


def test_transient_vision_failure_is_retried_once(monkeypatch) -> None:
    monkeypatch.setattr(vision_detector, "settings", _settings())
    calls = _install_transport(
        monkeypatch,
        [_ProviderFailure(503, "provider unavailable"), ('{"items": []}', "stop")],
    )

    assert vision_detector._call_deepseek_vision("unused.png") == []

    # The retry succeeded, so the failure left no error behind: from the
    # response's point of view this run was a normal empty verdict.
    assert len(calls) == 2
    assert vision_detector._last_call_error() == ""


def test_unparseable_answer_records_the_finish_reason(monkeypatch) -> None:
    monkeypatch.setattr(vision_detector, "settings", _settings())
    _install_transport(monkeypatch, [("抱歉，我无法分析这张图片。", "length")])

    assert vision_detector._call_deepseek_vision("unused.png") == []

    detail = vision_detector._last_call_error()
    assert "unparseable_response" in detail
    assert "finish_reason=length" in detail


def test_successful_call_clears_a_previous_failure(monkeypatch) -> None:
    monkeypatch.setattr(vision_detector, "settings", _settings())
    _install_transport(monkeypatch, [_ProviderFailure(500, "boom")])
    vision_detector._call_deepseek_vision("unused.png")
    assert vision_detector._last_call_error() != ""

    _install_transport(monkeypatch, [('{"items": [{"type": "phone"}]}', "stop")])
    assert vision_detector._call_deepseek_vision("unused.png") == [{"type": "phone"}]
    assert vision_detector._last_call_error() == ""


@pytest.mark.parametrize(("error", "expected"), [
    ("", "empty_result"),
    ("APIConnectionError | timeout", "APIConnectionError"),
])
def test_detector_detail_says_what_actually_happened(error: str, expected: str) -> None:
    assert expected in privacy_agent.vision_detector_detail(error)


def test_vision_api_response_carries_diagnostics_but_no_internals(monkeypatch) -> None:
    """The detail field explains the failure; the messages stay user-facing."""
    monkeypatch.setattr(privacy_agent, "settings", _settings())
    monkeypatch.setattr(
        vision_detector,
        "detect_with_vision",
        lambda *a, **k: [],
    )
    monkeypatch.setattr(
        vision_detector,
        "_last_call_error",
        lambda: "APITimeoutError | HTTP 504 | body=upstream timeout",
    )

    failed = privacy_agent._detect_vision_api(
        _base_result([_item()]), "unused.png", "img_test", "/static/x.png", 400, 200
    )

    assert failed.detectorMode == "ocr"
    assert "调用失败" in failed.detectorMessage
    assert "APITimeoutError" in (failed.detectorDetail or "")
    assert "APITimeoutError" not in failed.detectorMessage
    assert "APITimeoutError" not in failed.summary
    # The local findings survive the failed enhancement.
    assert [item.id for item in failed.items] == ["img_test_ocr_1"]


def test_vision_api_success_marks_the_detail_ok(monkeypatch) -> None:
    monkeypatch.setattr(privacy_agent, "settings", _settings())
    vision_item = PrivacyItem(
        id="img_test_vision_1",
        type="qr_code",
        label="二维码",
        text="二维码内容已隐藏",
        riskLevel="high",
        box=Box(x=1, y=2, width=30, height=30),
        suggestion="遮挡后再分享。",
        source="vision_api",
    )
    monkeypatch.setattr(vision_detector, "detect_with_vision", lambda *a, **k: [vision_item])

    ok = privacy_agent._detect_vision_api(
        _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
    )

    assert ok.detectorMode == "vision_api"
    assert ok.detectorDetail == "ok"


def test_disabled_vision_is_distinct_from_a_failure(monkeypatch) -> None:
    monkeypatch.setattr(privacy_agent, "settings", _settings(enabled=False, api_key=""))
    monkeypatch.setattr(vision_detector, "detect_with_vision", lambda *a, **k: [])

    response = privacy_agent._detect_vision_api(
        _base_result(), "unused.png", "img_test", "/static/x.png", 400, 200
    )

    assert response.detectorDetail == "vision_disabled"
    assert "调用失败" not in response.detectorMessage


def test_hybrid_failure_records_a_reason_and_keeps_local_items(monkeypatch) -> None:
    monkeypatch.setattr(vision_detector, "settings", _settings())
    _install_transport(monkeypatch, [_ProviderFailure(400, "image too large")])

    local = [_item()]
    assert vision_detector.enhance_with_vision(local, "unused.png", "img_test", 400, 200) == local
    assert "image too large" in vision_detector._last_call_error()


def test_retry_helper_result_type_is_stable() -> None:
    from model_retry import call_with_retry

    assert call_with_retry(lambda: 1, label="inline") == ModelCallResult(value=1)
