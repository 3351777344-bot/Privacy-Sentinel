"""DeepSeek text analyzer for image privacy detection.

Mirrors the pattern in ``modules/code_guardian/llm_analyzer.py``: DeepSeek is a
text-only LLM, so we feed it the OCR'd text from a local RapidOCR pass and ask
it to flag privacy risks. Bounding boxes come from OCR coordinates, not from
DeepSeek.
"""

from __future__ import annotations

import json
import logging
from difflib import SequenceMatcher
from typing import Any

from config import settings
from schemas.models import Box, PrivacyItem

logger = logging.getLogger(__name__)


PRIVACY_ANALYSIS_PROMPT = """You are a privacy auditor. Text below is OCR'd from a screenshot.
Return ONLY this compact JSON (no markdown, no prose):
{{"items":[{{"t":"matched_text_from_list","y":"phone|public_ip|server_path|db_password|software_version|phpinfo_link|other","l":"Chinese label 2-6 chars","r":"high|medium|low","s":"Chinese suggestion 1 short sentence"}}],"summary":"Chinese 1-sentence summary"}}

Rules:
- t MUST be copied verbatim from the OCR list below
- only flag text actually present in the OCR list
- r=high: credentials, IPs+port, phpinfo/admin links, server paths
- r=medium: emails, student IDs, public IP, software version+platform
- r=low: ambiguous matches
- keep l,s concise (<10 chars / <30 chars Chinese)
- empty items array if nothing matches
- Do NOT include matched_text or riskLevel fields not in the schema
- Do NOT add fields beyond t/y/l/r/s

OCR list:
{ocr_text}"""


_TYPE_LABEL_HINTS = {
    "phone": "手机号",
    "id_card": "身份证号",
    "bank_card": "银行卡号",
    "email": "电子邮箱",
    "student_id": "学号",
    "order_no": "订单号",
    "address": "详细地址",
    "qr_code": "二维码",
    "public_ip": "公网 IP 地址",
    "server_path": "服务器路径",
    "phpinfo_link": "管理入口",
    "db_password": "数据库凭据",
    "software_version": "软件版本信息",
    "other": "敏感内容",
}


def _normalize(value: str) -> str:
    return value.replace("\u3000", " ").strip()


def _best_match(target: str, texts: list[str]) -> tuple[int, float]:
    """Return (index, similarity) for the OCR text closest to ``target``.

    ``target`` is the matched_text the LLM returned; we need to map it back
    to a concrete OCR segment so we can attach a bounding box. OCR often adds
    extra spaces or drops punctuation, so we use fuzzy matching.
    """
    if not target or not texts:
        return -1, 0.0
    target_norm = _normalize(target).lower()
    best_idx = -1
    best_score = 0.0
    for idx, text in enumerate(texts):
        text_norm = _normalize(text).lower()
        if target_norm == text_norm:
            return idx, 1.0
        if target_norm and (target_norm in text_norm or text_norm in target_norm):
            score = min(len(target_norm), len(text_norm)) / max(len(target_norm), len(text_norm))
        else:
            score = SequenceMatcher(None, target_norm, text_norm).ratio()
        if score > best_score:
            best_score = score
            best_idx = idx
    if best_score < 0.5:
        return -1, best_score
    return best_idx, best_score


def _box_from_ocr_points(points: Any, image_width: int, image_height: int, padding: int = 4) -> Box:
    xs = [float(p[0]) for p in points]
    ys = [float(p[1]) for p in points]
    left = max(0, int(min(xs)) - padding)
    top = max(0, int(min(ys)) - padding)
    right = min(image_width, int(max(xs)) + padding)
    bottom = min(image_height, int(max(ys)) + padding)
    return Box(x=left, y=top, width=max(1, right - left), height=max(1, bottom - top))


def _call_deepseek(texts: list[str]) -> tuple[list[dict], str | None]:
    """Call DeepSeek chat completions on the OCR text corpus."""
    empty = {"items": [], "summary": ""}
    if not settings.deepseek_enabled or not settings.deepseek_api_key:
        return [], "DeepSeek 未启用或缺少 API Key，已回退本地规则检测结果。"

    try:
        from openai import OpenAI
    except ImportError:
        return [], "服务器缺少 openai 依赖，无法调用 DeepSeek。"

    ocr_text = "\n".join(f"[{idx}] {t}" for idx, t in enumerate(texts))
    prompt = PRIVACY_ANALYSIS_PROMPT.format(ocr_text=ocr_text[:6000])

    try:
        client = OpenAI(
            api_key=settings.deepseek_api_key,
            base_url=settings.deepseek_api_base,
        )
        response = client.chat.completions.create(
            model=settings.deepseek_model,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=8192,
            temperature=0.1,
        )
        content = response.choices[0].message.content
        if not content:
            finish_reason = getattr(response.choices[0], "finish_reason", None)
            return [], f"DeepSeek 未返回有效内容（finish_reason={finish_reason}）。"

        result = json.loads(content)
        items = result.get("items") if isinstance(result, dict) else None
        if not isinstance(items, list):
            return [], "DeepSeek 返回结构不包含 items 数组。"
        return items, None
    except json.JSONDecodeError:
        logger.error("Failed to parse DeepSeek privacy response as JSON")
        return [], "DeepSeek 返回结果解析失败。"
    except Exception as exc:
        logger.error("DeepSeek privacy call failed: %s", exc)
        return [], f"DeepSeek API 调用失败：{type(exc).__name__}。"


def analyze_ocr_text(
    texts: list[str],
    boxes: list[Any],
    scores: list[float],
    image_width: int,
    image_height: int,
    image_id: str,
) -> tuple[list[PrivacyItem], str | None]:
    """Run DeepSeek on the OCR text and map each finding back to a bbox.

    Returns ``(items, error)``. ``error`` is a user-facing Chinese message that
    is ``None`` on a successful DeepSeek call (even when zero items found).
    """
    raw_items, error = _call_deepseek(texts)
    items: list[PrivacyItem] = []
    used_indices: set[int] = set()

    for idx, raw in enumerate(raw_items, start=1):
        if not isinstance(raw, dict):
            continue
        # Compact schema uses single-letter keys; fall back to full names too.
        matched = _normalize(str(raw.get("t") or raw.get("matched_text", "")))
        item_type = str(raw.get("y") or raw.get("type", "other")).strip().lower()
        if item_type not in _TYPE_LABEL_HINTS:
            item_type = "other"
        risk = str(raw.get("r") or raw.get("riskLevel", "medium")).strip().lower()
        if risk not in {"high", "medium", "low"}:
            risk = "medium"
        label = str(raw.get("l") or raw.get("label", "")).strip() or _TYPE_LABEL_HINTS[item_type]
        suggestion = str(raw.get("s") or raw.get("suggestion", "建议遮盖此区域后再分享。")).strip() or "建议遮盖此区域后再分享。"

        match_idx, similarity = _best_match(matched, texts)
        if match_idx < 0:
            # Nothing matched in OCR. Skip rather than hallucinate a box.
            logger.warning(
                "DeepSeek item %d matched_text=%r did not match any OCR segment",
                idx, matched,
            )
            continue
        if match_idx in used_indices:
            # Same OCR line claimed twice. Skip the duplicate to avoid double-masking.
            continue
        used_indices.add(match_idx)

        if scores[match_idx] < 0.4:
            # OCR confidence too low to draw a box reliably.
            continue

        box = _box_from_ocr_points(boxes[match_idx], image_width, image_height)
        display_text = matched or texts[match_idx]
        items.append(
            PrivacyItem(
                id=f"{image_id}_ds_{idx}",
                type=item_type,
                label=label,
                text=display_text,
                riskLevel=risk,
                box=box,
                suggestion=suggestion,
                confidence=min(1.0, max(0.5, similarity)),
                source="deepseek",
                recommendedMaskType="mosaic" if item_type in {"qr_code", "address", "face"} else "black",
            )
        )

    return items, error