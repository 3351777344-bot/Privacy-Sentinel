from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any

from PIL import Image

from config import settings
from modules.risk_scoring import calculate_security_score, highest_risk
from schemas.models import Box, DetectResponse, PrivacyItem

from .privacy_detector import detect_privacy_items as detect_with_local_rules, _run_ocr

logger = logging.getLogger(__name__)


MASK_BY_TYPE = {
    "phone": "black",
    "id_card": "black",
    "bank_card": "black",
    "email": "black",
    "student_id": "black",
    "order_no": "black",
    "address": "mosaic",
    "qr_code": "mosaic",
    "face": "blur",
}


def _default_item_source(item: PrivacyItem, engine: str | None = None) -> str:
    if item.type == "qr_code":
        return "qr"
    if item.type == "face":
        return "face"
    if settings.demo_mode:
        return "demo"
    return "ocr"


def _enrich_item(item: PrivacyItem, engine: str | None = None) -> PrivacyItem:
    recommended_mask = MASK_BY_TYPE.get(item.type, settings.default_mask_type)
    if recommended_mask not in {"black", "blur", "mosaic"}:
        recommended_mask = "mosaic"
    return item.model_copy(
        update={
            "source": _default_item_source(item, engine),
            "recommendedMaskType": recommended_mask,
            "confidence": item.confidence if item.confidence is not None else 1.0,
        }
    )


def _box_from_face(face: Any, image_width: int, image_height: int, padding: int = 8) -> Box:
    left = max(0, int(face[0]) - padding)
    top = max(0, int(face[1]) - padding)
    right = min(image_width, int(face[0] + face[2]) + padding)
    bottom = min(image_height, int(face[1] + face[3]) + padding)
    return Box(x=left, y=top, width=max(1, right - left), height=max(1, bottom - top))


def _detect_faces(image_path: str, image_width: int, image_height: int, image_id: str) -> list[PrivacyItem]:
    if settings.face_engine != "opencv_yunet" or not settings.face_model_path:
        return []

    model_path = Path(settings.face_model_path)
    if not model_path.is_absolute():
        model_path = Path(__file__).resolve().parents[1] / model_path
    if not model_path.exists():
        return []

    try:
        import cv2
        import numpy as np

        image_bytes = np.fromfile(image_path, dtype=np.uint8)
        image = cv2.imdecode(image_bytes, cv2.IMREAD_COLOR)
        if image is None:
            return []
        detector = cv2.FaceDetectorYN.create(str(model_path), "", (image_width, image_height), score_threshold=0.8)
        _retval, faces = detector.detect(image)
        if faces is None:
            return []
        items: list[PrivacyItem] = []
        for index, face in enumerate(faces, start=1):
            confidence = float(face[-1]) if len(face) else 1.0
            items.append(
                PrivacyItem(
                    id=f"{image_id}_face_{index}",
                    type="face",
                    label="Face",
                    text="Face area detected locally",
                    riskLevel="medium",
                    box=_box_from_face(face, image_width, image_height),
                    suggestion="Blur or mosaic faces before sharing the image.",
                    confidence=max(0.0, min(1.0, confidence)),
                    source="face",
                    recommendedMaskType="blur",
                )
            )
        return items
    except (ImportError, RuntimeError, ValueError):
        return []


def detect_privacy_items(
    image_path: str,
    image_id: str,
    original_url: str,
    processing_mode: str | None = None,
) -> DetectResponse:
    base_result = detect_with_local_rules(image_path, image_id, original_url)
    engine = settings.privacy_engine
    if processing_mode == "local":
        engine = "agent"
    elif processing_mode == "online":
        engine = "deepseek" if settings.deepseek_enabled else "hybrid"

    if engine not in {"agent", "deepseek", "hybrid", "vision_api"} or settings.demo_mode:
        return base_result.model_copy(update={"items": [_enrich_item(item, engine) for item in base_result.items]})

    with Image.open(image_path) as image:
        width, height = image.size

    if engine == "vision_api":
        return _detect_vision_api(base_result, image_path, image_id, original_url, width, height)

    if engine == "deepseek":
        return _detect_deepseek(base_result, image_path, image_id, original_url, width, height)

    if engine == "hybrid":
        return _detect_hybrid(base_result, image_path, image_id, original_url, width, height)

    return _detect_agent(base_result, image_path, image_id, original_url, width, height)


def _detect_agent(
    base_result: DetectResponse,
    image_path: str,
    image_id: str,
    original_url: str,
    width: int,
    height: int,
) -> DetectResponse:
    items = [_enrich_item(item) for item in base_result.items]
    items.extend(_detect_faces(image_path, width, height, image_id))

    levels = [item.riskLevel for item in items]
    detector_message = (
        f"Local Privacy Agent completed analysis with OCR={settings.ocr_engine}, "
        f"QR={settings.qr_engine}, face={settings.face_engine}. External image API is disabled."
    )
    if base_result.detectorMode == "unavailable":
        detector_message = f"{detector_message} OCR was unavailable; partial local checks were used."
    summary = base_result.summary
    if items:
        labels = ", ".join(dict.fromkeys(item.label for item in items))
        summary = f"Local Privacy Agent found {len(items)} privacy area(s): {labels}. Review and process before sharing."

    return base_result.model_copy(
        update={
            "detectorMode": "agent",
            "detectorMessage": detector_message,
            "items": items,
            "riskLevel": highest_risk(levels),
            "score": calculate_security_score(levels),
            "summary": summary,
        }
    )


def _detect_deepseek(
    base_result: DetectResponse,
    image_path: str,
    image_id: str,
    original_url: str,
    width: int,
    height: int,
) -> DetectResponse:
    """OCR locally, then send the OCR text to DeepSeek for privacy analysis.

    This is the text-only-LLM-friendly path. DeepSeek gets structured text
    rather than raw pixels; bounding boxes come from the local OCR pass.
    """
    from .deepseek_privacy import analyze_ocr_text

    local_items = [_enrich_item(item) for item in base_result.items]

    try:
        texts, boxes, scores = _run_ocr(image_path, width, height)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("OCR pass failed before DeepSeek: %s", exc)
        texts, boxes, scores = [], [], []

    deepseek_items, deepseek_error = analyze_ocr_text(
        texts, boxes, scores, width, height, image_id,
    )

    seen = {(item.type, re.sub(r"\s+", "", item.text.lower())) for item in local_items}
    merged = list(local_items)
    for item in deepseek_items:
        key = (item.type, re.sub(r"\s+", "", item.text.lower()))
        if key in seen:
            continue
        merged.append(item)
        seen.add(key)

    levels = [item.riskLevel for item in merged]
    labels = ", ".join(dict.fromkeys(item.label for item in merged))
    if deepseek_items:
        summary = (
            f"DeepSeek 文本分析在 {len(texts)} 段 OCR 文字中发现 {len(deepseek_items)} 个隐私项"
            f"（{labels}），结合本地 OCR 共 {len(merged)} 个区域。"
        )
        detector_message = (
            f"DeepSeek mode: 本地 OCR ({settings.ocr_engine}) 提取文字 → "
            f"DeepSeek ({settings.deepseek_model}) 文本分析。"
        )
    elif deepseek_error:
        summary = (
            f"DeepSeek 分析失败：{deepseek_error}仅依赖本地 OCR 结果。"
        )
        detector_message = (
            f"DeepSeek mode: 本地 OCR 正常 ({settings.ocr_engine})，"
            f"DeepSeek ({settings.deepseek_model}) 调用失败。"
        )
    elif texts:
        summary = (
            f"DeepSeek 在 {len(texts)} 段 OCR 文字中未识别到额外隐私项，"
            f"本地 OCR 命中 {len(local_items)} 项。"
        )
        detector_message = (
            f"DeepSeek mode: 本地 OCR ({settings.ocr_engine}) + "
            f"DeepSeek ({settings.deepseek_model}) 文本分析。"
        )
    else:
        summary = base_result.summary
        detector_message = base_result.detectorMessage

    return DetectResponse(
        imageId=image_id,
        originalUrl=original_url,
        originalImageUrl=original_url,
        riskLevel=highest_risk(levels) if merged else base_result.riskLevel,
        score=calculate_security_score(levels) if merged else base_result.score,
        summary=summary,
        detectorMode="deepseek",
        detectorMessage=detector_message,
        items=merged,
    )


def _detect_vision_api(
    base_result: DetectResponse,
    image_path: str,
    image_id: str,
    original_url: str,
    width: int,
    height: int,
) -> DetectResponse:
    from .vision_detector import detect_with_qwen

    qwen_items = detect_with_qwen(image_path, image_id, width, height)
    if not qwen_items:
        items = [_enrich_item(item) for item in base_result.items]
        if _qwen_active():
            # The model was reachable but unusable: genuine failure, so say so.
            fallback_message = "Qwen VL API 调用失败，已回退到本地 OCR 检测。"
        else:
            fallback_message = (
                "Qwen VL 未启用（默认关闭），本次为纯本机 OCR 检测，图像未离开设备。"
            )
        return base_result.model_copy(
            update={
                "detectorMode": "ocr",
                "detectorMessage": fallback_message,
                "items": items,
                "riskLevel": highest_risk([i.riskLevel for i in items]),
                "score": calculate_security_score([i.riskLevel for i in items]),
            }
        )

    items = qwen_items + [_enrich_item(item) for item in base_result.items]
    seen_ids = set()
    deduped: list[PrivacyItem] = []
    for item in items:
        if item.id not in seen_ids:
            seen_ids.add(item.id)
            deduped.append(item)

    levels = [item.riskLevel for item in deduped]
    labels = ", ".join(dict.fromkeys(item.label for item in deduped))
    return DetectResponse(
        imageId=image_id,
        originalImageUrl=original_url,
        riskLevel=highest_risk(levels),
        score=calculate_security_score(levels),
        summary=f"Qwen VL 视觉分析检测到 {len(deduped)} 个隐私区域（{labels}）。请确认并处理后再分享。",
        detectorMode="vision_api",
        detectorMessage=f"Qwen VL ({settings.qwen_model}) 直接分析图片，已结合本地 OCR 结果。",
        items=deduped,
    )


def _qwen_active() -> bool:
    """True only when Qwen VL will really be called.

    Every user-facing message is derived from this check instead of from the
    configured engine name alone, so the UI never claims an external model
    analysed the image when it never ran.
    """
    return bool(settings.qwen_enabled and settings.qwen_api_key)


def _detect_hybrid(
    base_result: DetectResponse,
    image_path: str,
    image_id: str,
    original_url: str,
    width: int,
    height: int,
) -> DetectResponse:
    from .vision_detector import enhance_with_qwen

    local_items = [_enrich_item(item) for item in base_result.items]
    local_items.extend(_detect_faces(image_path, width, height, image_id))

    enhanced_items = enhance_with_qwen(local_items, image_path, image_id, width, height)

    qwen_new_count = max(0, len(enhanced_items) - len(local_items))
    qwen_verified_count = sum(1 for item in enhanced_items if item.source == "vision_api")

    levels = [item.riskLevel for item in enhanced_items]
    labels = ", ".join(dict.fromkeys(item.label for item in enhanced_items))
    if _qwen_active():
        summary = (
            f"混合检测发现 {len(enhanced_items)} 个隐私区域（{labels}），"
            f"其中 Qwen VL 新增 {qwen_new_count} 项、验证 {qwen_verified_count} 项。"
        )
        detector_message = (
            f"Hybrid mode: 本地 OCR ({settings.ocr_engine}) + "
            f"Qwen VL ({settings.qwen_model}) 联合分析。"
        )
    else:
        summary = (
            f"本地检测发现 {len(enhanced_items)} 个隐私区域（{labels}）。"
            "Qwen VL 未启用，未进行联网图像分析。"
        )
        detector_message = (
            f"纯本机分析（未联网）：OCR={settings.ocr_engine}，QR={settings.qr_engine}，"
            f"face={settings.face_engine}。Qwen VL 未启用（默认关闭），图像未离开设备。"
        )
    return DetectResponse(
        imageId=image_id,
        originalImageUrl=original_url,
        riskLevel=highest_risk(levels),
        score=calculate_security_score(levels),
        summary=summary,
        detectorMode="hybrid",
        detectorMessage=detector_message,
        items=enhanced_items,
    )
