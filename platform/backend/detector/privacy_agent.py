from pathlib import Path
from typing import Any

from PIL import Image

from config import settings
from modules.risk_scoring import calculate_security_score, highest_risk
from schemas.models import Box, DetectResponse, PrivacyItem

from .privacy_detector import detect_privacy_items as detect_with_local_rules


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


def _default_item_source(item: PrivacyItem) -> str:
    if item.type == "qr_code":
        return "qr"
    if item.type == "face":
        return "face"
    if settings.demo_mode:
        return "demo"
    return "ocr"


def _enrich_item(item: PrivacyItem) -> PrivacyItem:
    recommended_mask = MASK_BY_TYPE.get(item.type, settings.default_mask_type)
    if recommended_mask not in {"black", "blur", "mosaic"}:
        recommended_mask = "mosaic"
    return item.model_copy(
        update={
            "source": _default_item_source(item),
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


def detect_privacy_items(image_path: str, image_id: str, original_url: str) -> DetectResponse:
    base_result = detect_with_local_rules(image_path, image_id, original_url)
    if settings.privacy_engine != "agent" or settings.demo_mode:
        return base_result.model_copy(update={"items": [_enrich_item(item) for item in base_result.items]})

    with Image.open(image_path) as image:
        width, height = image.size

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
