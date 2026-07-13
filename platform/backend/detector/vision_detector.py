import base64
import json
import logging
from pathlib import Path

from config import settings
from schemas.models import Box, PrivacyItem

logger = logging.getLogger(__name__)

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


def _normalized_to_pixel(bbox_2d: list[float], img_w: int, img_h: int) -> Box:
    x1, y1, x2, y2 = bbox_2d[:4]
    left = max(0, int(x1 / 1000 * img_w))
    top = max(0, int(y1 / 1000 * img_h))
    right = min(img_w, int(x2 / 1000 * img_w))
    bottom = min(img_h, int(y2 / 1000 * img_h))
    w = max(1, right - left)
    h = max(1, bottom - top)
    return Box(x=left, y=top, width=w, height=h)


def _call_qwen_api(image_path: str) -> list[dict]:
    if not settings.qwen_enabled or not settings.qwen_api_key:
        logger.warning("Qwen VL API disabled or missing API key")
        return []

    try:
        from openai import OpenAI
    except ImportError:
        logger.warning("openai package not installed, Qwen VL API unavailable")
        return []

    try:
        base64_image = _image_to_base64(image_path)
        ext = Path(image_path).suffix.lower().lstrip(".")
        mime_map = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}
        mime_type = mime_map.get(ext, "image/png")

        client = OpenAI(api_key=settings.qwen_api_key, base_url=settings.qwen_api_base)

        response = client.chat.completions.create(
            model=settings.qwen_model,
            messages=[
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
            response_format={"type": "json_object"},
            max_tokens=4096,
            temperature=0.1,
        )

        content = response.choices[0].message.content
        if not content:
            return []

        result = json.loads(content)
        return result.get("items", [])
    except json.JSONDecodeError as exc:
        logger.error("Failed to parse Qwen VL response as JSON: %s", exc)
        return []
    except Exception as exc:
        logger.error("Qwen VL API call failed: %s", exc)
        return []


def _parse_qwen_items(raw_items: list[dict], image_id: str, img_w: int, img_h: int) -> list[PrivacyItem]:
    parsed: list[PrivacyItem] = []
    for idx, item in enumerate(raw_items, start=1):
        try:
            item_type = _normalize_type(item.get("type", "other"))

            risk = str(item.get("riskLevel", "medium")).strip().lower()
            if risk not in {"high", "medium", "low"}:
                risk = "medium"

            bbox_raw = item.get("bbox_2d")
            if isinstance(bbox_raw, list) and len(bbox_raw) >= 4:
                box = _normalized_to_pixel(bbox_raw, img_w, img_h)
            else:
                box = Box(x=0, y=0, width=img_w, height=img_h)

            parsed.append(
                PrivacyItem(
                    id=f"{image_id}_qwen_{idx}",
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
            logger.warning("Failed to parse Qwen VL item %d: %s", idx, exc)
    return parsed


def detect_with_qwen(image_path: str, image_id: str, img_w: int, img_h: int) -> list[PrivacyItem]:
    raw_items = _call_qwen_api(image_path)
    if not raw_items:
        return []
    return _parse_qwen_items(raw_items, image_id, img_w, img_h)


def _build_ocr_context(items: list[PrivacyItem]) -> str:
    if not items:
        return "Local OCR found no text."
    lines = []
    for item in items:
        lines.append(f"- [{item.type}] label={item.label}, text={item.text}, risk={item.riskLevel}, bbox=({item.box.x},{item.box.y},{item.box.width}x{item.box.height})")
    return "Local OCR detections:\n" + "\n".join(lines)


def enhance_with_qwen(
    local_items: list[PrivacyItem],
    image_path: str,
    image_id: str,
    img_w: int,
    img_h: int,
) -> list[PrivacyItem]:
    """Hybrid mode: send image to Qwen VL alongside local OCR results for enhanced analysis."""
    if not settings.qwen_enabled or not settings.qwen_api_key:
        return local_items

    ocr_context = _build_ocr_context(local_items)

    hybrid_prompt = f"""Analyze this image for privacy risks. The local OCR already found some items, listed below. Your task is to:

1. Verify each local OCR finding - confirm if it's truly a privacy risk
2. Identify any ADDITIONAL privacy risks the OCR might have missed (handwritten text, complex layouts, visual patterns like ID cards, faces)
3. Assess the overall risk accurately

Local OCR findings:
{ocr_context}

Return ONLY a JSON object:
{{
  "verified": [
    {{"id": "original_ocr_item_id_1", "riskLevel": "high|medium|low", "note": "brief reason in Chinese"}}
  ],
  "new_items": [
    {{
      "type": "phone|id_card|bank_card|email|student_id|order_no|address|qr_code|face|other",
      "label": "short Chinese label",
      "text": "actual text found",
      "riskLevel": "high|medium|low",
      "suggestion": "masking advice in Chinese",
      "bbox_2d": [x1, y1, x2, y2]
    }}
  ],
  "overall_assessment": "brief Chinese summary"
}}

If no additional items found, return empty arrays. No markdown, just JSON."""

    try:
        from openai import OpenAI
    except ImportError:
        return local_items

    try:
        base64_image = _image_to_base64(image_path)
        ext = Path(image_path).suffix.lower().lstrip(".")
        mime_map = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}
        mime_type = mime_map.get(ext, "image/png")

        client = OpenAI(api_key=settings.qwen_api_key, base_url=settings.qwen_api_base)

        response = client.chat.completions.create(
            model=settings.qwen_model,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{mime_type};base64,{base64_image}"},
                        },
                        {"type": "text", "text": hybrid_prompt},
                    ],
                },
            ],
            response_format={"type": "json_object"},
            max_tokens=4096,
            temperature=0.1,
        )

        content = response.choices[0].message.content
        if not content:
            return local_items

        result = json.loads(content)

        verified_map: dict[str, str] = {}
        for v in result.get("verified", []):
            vid = v.get("id", "")
            new_risk = v.get("riskLevel")
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

        new_raw = result.get("new_items", [])
        new_items = _parse_qwen_items(new_raw, image_id, img_w, img_h)
        updated_items.extend(new_items)

        return updated_items
    except json.JSONDecodeError as exc:
        logger.error("Failed to parse hybrid Qwen VL response: %s", exc)
        return local_items
    except Exception as exc:
        logger.error("Hybrid Qwen VL call failed: %s", exc)
        return local_items
