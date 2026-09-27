import base64
import json
import logging
import re
from pathlib import Path

from config import settings
from schemas.models import Box, PrivacyItem

logger = logging.getLogger(__name__)

# Vision detection runs on the same DeepSeek V4.1 Flash model as the rest of the
# backend. The legacy `deepseek-v4-flash-vision-exp` name is retired and served by
# this model, so there is no separate vision endpoint or key to configure.
_DEEPSEEK_VISION_MODEL = "deepseek-flash"

_TYPE_MAPPING = {
    "phone": "phone",
    "手机号": "phone",
    "手机号码": "phone",
    "电话号码": "phone",
    "id_card": "id_card",
    "身份证": "id_card",
    "身份证号": "id_card",
    "身份证号码": "id_card",
    "bank_card": "bank_card",
    "银行卡": "bank_card",
    "银行卡号": "bank_card",
    "银行卡号码": "bank_card",
    "email": "email",
    "邮箱": "email",
    "电子邮箱": "email",
    "邮件": "email",
    "student_id": "student_id",
    "学号": "student_id",
    "order_no": "order_no",
    "订单号": "order_no",
    "订单编号": "order_no",
    "address": "address",
    "地址": "address",
    "详细地址": "address",
    "住址": "address",
    "qr_code": "qr_code",
    "二维码": "qr_code",
    "face": "face",
    "人脸": "face",
    "other": "other",
}


def _normalize_type(raw_type: str) -> str:
    normalized = _TYPE_MAPPING.get(str(raw_type).strip(), None)
    if normalized:
        return normalized
    raw_lower = str(raw_type).strip().lower()
    if raw_lower in _TYPE_MAPPING:
        return _TYPE_MAPPING[raw_lower]
    return "other"

_PRIVACY_DETECTION_PROMPT = """Analyze this image for privacy-sensitive information. Identify ALL items that could leak personal data.

Return a JSON object with this exact structure:
{
  "items": [
    {
      "type": "phone|id_card|bank_card|email|student_id|order_no|address|qr_code|face|other",
      "label": "short Chinese label",
      "text": "the actual text found (redacted if sensitive)",
      "riskLevel": "high|medium|low",
      "suggestion": "actionable masking advice in Chinese",
      "bbox_2d": [x1, y1, x2, y2]
    }
  ]
}

Rules:
- type MUST be one of: phone, id_card, bank_card, email, student_id, order_no, address, qr_code, face, other. DO NOT use Chinese for type field.
- bbox_2d uses normalized coordinates 0-1000, where (0,0)=top-left, (1000,1000)=bottom-right
- riskLevel: "high" for IDs, cards, phone numbers, passwords, addresses; "medium" for emails, student IDs; "low" for ambiguous items
- Include QR codes if present
- Include visible faces if any
- If the image has NO privacy-sensitive information, return {"items": []}
- Only return the JSON, no markdown or explanation"""


def _image_to_base64(image_path: str) -> str:
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def _encode_image_for_vision(image_path: str) -> tuple[str, str]:
    """Compress/resize image for vision API to cut upload and inference latency.

    Returns ``(base64_payload, mime_type)``. Falls back to the original file bytes
    when Pillow cannot open the image.
    """
    max_side = max(256, int(getattr(settings, "vision_image_max_side", 1280) or 1280))
    try:
        from io import BytesIO

        from PIL import Image

        with Image.open(image_path) as image:
            rgb = image.convert("RGB")
            width, height = rgb.size
            longest = max(width, height)
            if longest > max_side:
                scale = max_side / float(longest)
                rgb = rgb.resize(
                    (max(1, int(width * scale)), max(1, int(height * scale))),
                    Image.Resampling.LANCZOS,
                )
            buffer = BytesIO()
            rgb.save(buffer, format="JPEG", quality=80, optimize=True)
            return base64.b64encode(buffer.getvalue()).decode("utf-8"), "image/jpeg"
    except Exception as exc:
        logger.warning("Vision image compress failed, using original bytes: %s", exc)
        ext = Path(image_path).suffix.lower().lstrip(".")
        mime_map = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}
        return _image_to_base64(image_path), mime_map.get(ext, "image/png")


def _vision_client():
    from openai import OpenAI

    timeout = max(5, int(getattr(settings, "deepseek_timeout_seconds", 60) or 60))
    return OpenAI(
        api_key=settings.deepseek_api_key,
        base_url=settings.deepseek_api_base,
        timeout=timeout,
    )


def _vision_max_tokens() -> int:
    return max(256, int(getattr(settings, "deepseek_max_tokens", 2048) or 2048))


def _vision_model() -> str:
    return getattr(settings, "deepseek_vision_model", "") or _DEEPSEEK_VISION_MODEL


def _extract_json_payload(content: str):
    """Parse model JSON that may be wrapped in markdown fences."""
    text = (content or "").strip()
    if not text:
        return None
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text, count=1, flags=re.IGNORECASE)
        text = re.sub(r"\s*```$", "", text)
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        for open_ch, close_ch in (("[", "]"), ("{", "}")):
            start = text.find(open_ch)
            end = text.rfind(close_ch)
            if start >= 0 and end > start:
                try:
                    return json.loads(text[start : end + 1])
                except json.JSONDecodeError:
                    continue
    return None


def _box_from_rotate_rect(rotate_rect: list[float], img_w: int, img_h: int) -> Box:
    cx, cy, rw, rh = [float(value) for value in rotate_rect[:4]]
    angle = float(rotate_rect[4]) if len(rotate_rect) > 4 else 0.0
    # Near-vertical text: swap extents for an axis-aligned mask box.
    if 45.0 <= abs(angle) % 180.0 <= 135.0:
        rw, rh = rh, rw
    left = max(0, int((cx - rw / 2.0) / 1000.0 * img_w))
    top = max(0, int((cy - rh / 2.0) / 1000.0 * img_h))
    width = max(1, int(rw / 1000.0 * img_w))
    height = max(1, int(rh / 1000.0 * img_h))
    if left + width > img_w:
        width = max(1, img_w - left)
    if top + height > img_h:
        height = max(1, img_h - top)
    return Box(x=left, y=top, width=width, height=height)


def _normalized_to_pixel(bbox_2d: list[float], img_w: int, img_h: int) -> Box:
    x1, y1, x2, y2 = bbox_2d[:4]
    left = max(0, int(x1 / 1000 * img_w))
    top = max(0, int(y1 / 1000 * img_h))
    right = min(img_w, int(x2 / 1000 * img_w))
    bottom = min(img_h, int(y2 / 1000 * img_h))
    w = max(1, right - left)
    h = max(1, bottom - top)
    return Box(x=left, y=top, width=w, height=h)


def _call_deepseek_vision(image_path: str) -> list[dict]:
    if not settings.deepseek_enabled or not settings.deepseek_api_key:
        logger.warning("DeepSeek vision API disabled or missing API key")
        return []

    try:
        from openai import OpenAI  # noqa: F401
    except ImportError:
        logger.warning("openai package not installed, DeepSeek vision API unavailable")
        return []

    try:
        base64_image, mime_type = _encode_image_for_vision(image_path)
        client = _vision_client()
        request: dict = {
            "model": _vision_model(),
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{mime_type};base64,{base64_image}"},
                        },
                        {"type": "text", "text": _PRIVACY_DETECTION_PROMPT},
                    ],
                },
            ],
            "max_tokens": _vision_max_tokens(),
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
        }

        response = client.chat.completions.create(**request)
        content = response.choices[0].message.content
        payload = _extract_json_payload(content or "")
        if payload is None:
            return []
        if isinstance(payload, dict):
            return payload.get("items", [])
        return []
    except Exception as exc:
        logger.error("DeepSeek vision API call failed: %s", exc)
        return []


def _parse_vision_items(raw_items: list[dict], image_id: str, img_w: int, img_h: int) -> list[PrivacyItem]:
    parsed: list[PrivacyItem] = []
    for idx, item in enumerate(raw_items, start=1):
        try:
            item_type = _normalize_type(item.get("type", "other"))

            risk = str(item.get("riskLevel", "medium")).strip().lower()
            if risk not in {"high", "medium", "low"}:
                risk = "medium"

            bbox_raw = item.get("bbox_2d")
            rotate_raw = item.get("rotate_rect")
            if isinstance(bbox_raw, list) and len(bbox_raw) >= 4:
                box = _normalized_to_pixel(bbox_raw, img_w, img_h)
            elif isinstance(rotate_raw, list) and len(rotate_raw) >= 4:
                box = _box_from_rotate_rect(rotate_raw, img_w, img_h)
            else:
                box = Box(x=0, y=0, width=img_w, height=img_h)

            parsed.append(
                PrivacyItem(
                    id=f"{image_id}_vision_{idx}",
                    type=item_type,
                    label=str(item.get("label", "敏感信息")).strip(),
                    text=str(item.get("text", "检测到敏感内容")).strip(),
                    riskLevel=risk,
                    box=box,
                    suggestion=str(item.get("suggestion", "建议遮挡此区域后再分享。")).strip(),
                    confidence=max(0.0, min(1.0, float(item.get("confidence", 0.85)))),
                    source="vision_api",
                    recommendedMaskType="mosaic"
                    if item_type in {"qr_code", "address", "face"}
                    else "black",
                )
            )
        except Exception as exc:
            logger.warning("Failed to parse DeepSeek vision item %d: %s", idx, exc)
    return parsed


def detect_with_vision(image_path: str, image_id: str, img_w: int, img_h: int) -> list[PrivacyItem]:
    """Run DeepSeek vision detection on the image and return parsed privacy items."""
    raw_items = _call_deepseek_vision(image_path)
    if not raw_items:
        return []
    return _parse_vision_items(raw_items, image_id, img_w, img_h)


def _build_ocr_context(items: list[PrivacyItem]) -> str:
    if not items:
        return "Local OCR found no text."
    lines = []
    for item in items:
        lines.append(
            f"- [{item.type}] label={item.label}, text={item.text}, risk={item.riskLevel}, "
            f"bbox=({item.box.x},{item.box.y},{item.box.width}x{item.box.height})"
        )
    return "Local OCR detections:\n" + "\n".join(lines)


def _merge_vision_items(local_items: list[PrivacyItem], vision_items: list[PrivacyItem]) -> list[PrivacyItem]:
    merged = list(local_items)
    existing = {(item.type, re.sub(r"\s+", "", item.text.lower())) for item in local_items}
    for item in vision_items:
        key = (item.type, re.sub(r"\s+", "", item.text.lower()))
        if key in existing:
            continue
        merged.append(item)
        existing.add(key)
    return merged


def enhance_with_vision(
    local_items: list[PrivacyItem],
    image_path: str,
    image_id: str,
    img_w: int,
    img_h: int,
) -> list[PrivacyItem]:
    """Hybrid mode: send the image to DeepSeek vision alongside local OCR results."""
    if not settings.deepseek_enabled or not settings.deepseek_api_key:
        return local_items

    try:
        from openai import OpenAI  # noqa: F401
    except ImportError:
        return local_items

    try:
        base64_image, mime_type = _encode_image_for_vision(image_path)
        client = _vision_client()

        ocr_context = _build_ocr_context(local_items)
        prompt = f"""Check this image for privacy risks. Local OCR already found:
{ocr_context}

Return ONLY JSON:
{{
  "verified": [{{"id": "ocr_item_id", "riskLevel": "high|medium|low"}}],
  "new_items": [{{
    "type": "phone|id_card|bank_card|email|student_id|order_no|address|qr_code|face|other",
    "label": "short Chinese label",
    "text": "text found",
    "riskLevel": "high|medium|low",
    "suggestion": "Chinese masking advice",
    "bbox_2d": [x1, y1, x2, y2]
  }}]
}}
Verify OCR hits, add missed risks only. Empty arrays if nothing new. JSON only."""

        request: dict = {
            "model": _vision_model(),
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{mime_type};base64,{base64_image}"},
                        },
                        {"type": "text", "text": prompt},
                    ],
                },
            ],
            "max_tokens": _vision_max_tokens(),
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
        }

        response = client.chat.completions.create(**request)
        content = response.choices[0].message.content
        payload = _extract_json_payload(content or "")
        if payload is None:
            logger.error("Failed to parse hybrid DeepSeek vision response: empty or invalid JSON")
            return local_items

        if not isinstance(payload, dict):
            return local_items

        verified_map: dict[str, str] = {}
        for verified in payload.get("verified", []):
            vid = verified.get("id", "")
            new_risk = verified.get("riskLevel")
            if vid and new_risk in {"high", "medium", "low"}:
                verified_map[vid] = new_risk

        updated_items: list[PrivacyItem] = []
        for item in local_items:
            if item.id in verified_map:
                updated_items.append(
                    item.model_copy(
                        update={
                            "riskLevel": verified_map[item.id],
                            "source": "vision_api",
                        }
                    )
                )
            else:
                updated_items.append(item)

        new_items = _parse_vision_items(payload.get("new_items", []), image_id, img_w, img_h)
        return _merge_vision_items(updated_items, new_items)
    except Exception as exc:
        logger.error("Hybrid DeepSeek vision call failed: %s", exc)
        return local_items
