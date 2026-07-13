import base64
import json
from types import SimpleNamespace

import openai

from detector import vision_detector
from schemas.models import Box, PrivacyItem


def _settings(*, enabled: bool = True, api_key: str = "test-key") -> SimpleNamespace:
    return SimpleNamespace(
        qwen_enabled=enabled,
        qwen_api_key=api_key,
        qwen_api_base="https://example.invalid/v1",
        qwen_model="test-vision-model",
    )


def _item(item_id: str = "img_test_phone_1") -> PrivacyItem:
    return PrivacyItem(
        id=item_id,
        type="phone",
        label="手机号",
        text="138****5678",
        riskLevel="high",
        box=Box(x=10, y=20, width=80, height=20),
        suggestion="遮挡后再分享。",
        source="ocr",
        recommendedMaskType="black",
    )


class _FakeCompletions:
    def __init__(self, content: str | None) -> None:
        self.content = content
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=self.content))]
        )


class _FakeOpenAI:
    def __init__(self, completions: _FakeCompletions) -> None:
        self.chat = SimpleNamespace(completions=completions)


def test_type_and_box_normalization() -> None:
    assert vision_detector._normalize_type("手机号") == "phone"
    assert vision_detector._normalize_type(" EMAIL ") == "email"
    assert vision_detector._normalize_type("未知类型") == "other"

    box = vision_detector._normalized_to_pixel([-20, 100, 1200, 900], 200, 100)
    assert box == Box(x=0, y=10, width=200, height=80)


def test_image_encoding_and_qwen_item_parsing(tmp_path) -> None:
    image_path = tmp_path / "sample.webp"
    image_path.write_bytes(b"guardianhub-image")
    assert base64.b64decode(vision_detector._image_to_base64(str(image_path))) == b"guardianhub-image"

    parsed = vision_detector._parse_qwen_items(
        [
            {
                "type": "phone",
                "label": "手机号",
                "text": "138****5678",
                "riskLevel": "high",
                "bbox_2d": [100, 200, 600, 400],
                "suggestion": "请遮挡",
                "confidence": 2,
            },
            {"type": "地址", "riskLevel": "unexpected"},
            {"type": "email", "confidence": "not-a-number"},
        ],
        "img_123",
        400,
        200,
    )

    assert len(parsed) == 2
    assert parsed[0].type == "phone"
    assert parsed[0].box == Box(x=40, y=40, width=200, height=40)
    assert parsed[0].confidence == 1
    assert parsed[1].type == "address"
    assert parsed[1].riskLevel == "medium"
    assert parsed[1].box == Box(x=0, y=0, width=400, height=200)
    assert parsed[1].recommendedMaskType == "mosaic"


def test_qwen_api_disabled_and_success_paths(tmp_path, monkeypatch) -> None:
    image_path = tmp_path / "sample.png"
    image_path.write_bytes(b"png-bytes")

    monkeypatch.setattr(vision_detector, "settings", _settings(enabled=False))
    assert vision_detector._call_qwen_api(str(image_path)) == []

    raw_items = [{"type": "二维码", "bbox_2d": [0, 0, 1000, 1000]}]
    completions = _FakeCompletions(json.dumps({"items": raw_items}, ensure_ascii=False))
    monkeypatch.setattr(vision_detector, "settings", _settings())
    monkeypatch.setattr(openai, "OpenAI", lambda **_kwargs: _FakeOpenAI(completions))

    assert vision_detector._call_qwen_api(str(image_path)) == raw_items
    request = completions.calls[0]
    assert request["model"] == "test-vision-model"
    image_url = request["messages"][0]["content"][0]["image_url"]["url"]
    assert image_url.startswith("data:image/png;base64,")

    detected = vision_detector.detect_with_qwen(str(image_path), "img_123", 120, 80)
    assert len(detected) == 1
    assert detected[0].type == "qr_code"
    assert detected[0].source == "vision_api"


def test_qwen_api_handles_empty_and_invalid_responses(tmp_path, monkeypatch) -> None:
    image_path = tmp_path / "sample.unknown"
    image_path.write_bytes(b"image")
    monkeypatch.setattr(vision_detector, "settings", _settings())

    completions = _FakeCompletions(None)
    monkeypatch.setattr(openai, "OpenAI", lambda **_kwargs: _FakeOpenAI(completions))
    assert vision_detector._call_qwen_api(str(image_path)) == []

    completions.content = "not-json"
    assert vision_detector._call_qwen_api(str(image_path)) == []


def test_hybrid_context_and_disabled_fallback(monkeypatch) -> None:
    local_items = [_item()]
    assert vision_detector._build_ocr_context([]) == "Local OCR found no text."
    context = vision_detector._build_ocr_context(local_items)
    assert "138****5678" in context
    assert "bbox=(10,20,80x20)" in context

    monkeypatch.setattr(vision_detector, "settings", _settings(enabled=False))
    assert vision_detector.enhance_with_qwen(local_items, "unused.png", "img_123", 200, 100) is local_items


def test_hybrid_response_verifies_and_adds_items(tmp_path, monkeypatch) -> None:
    image_path = tmp_path / "sample.jpg"
    image_path.write_bytes(b"jpg-bytes")
    local = _item()
    response = {
        "verified": [
            {"id": local.id, "riskLevel": "medium"},
            {"id": "ignored", "riskLevel": "invalid"},
        ],
        "new_items": [
            {
                "type": "face",
                "label": "人脸",
                "text": "检测到人脸",
                "riskLevel": "medium",
                "bbox_2d": [100, 100, 500, 700],
            }
        ],
    }
    completions = _FakeCompletions(json.dumps(response, ensure_ascii=False))
    monkeypatch.setattr(vision_detector, "settings", _settings())
    monkeypatch.setattr(openai, "OpenAI", lambda **_kwargs: _FakeOpenAI(completions))

    enhanced = vision_detector.enhance_with_qwen(
        [local], str(image_path), "img_123", 200, 100
    )
    assert len(enhanced) == 2
    assert enhanced[0].riskLevel == "medium"
    assert enhanced[0].source == "vision_api"
    assert enhanced[1].type == "face"
    assert enhanced[1].recommendedMaskType == "mosaic"

    completions.content = "invalid-json"
    fallback = vision_detector.enhance_with_qwen(
        [local], str(image_path), "img_123", 200, 100
    )
    assert fallback == [local]
