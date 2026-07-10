import re
from functools import lru_cache
from pathlib import Path
from threading import Lock
from typing import Any

from PIL import Image

from config import settings
from modules.risk_scoring import calculate_security_score, highest_risk
from schemas.models import Box, DetectResponse, PrivacyItem

from .mock_detector import detect_privacy_items as detect_demo_items


OCR_CONFIDENCE_THRESHOLD = 0.55
_OCR_LOCK = Lock()

PRIVACY_PATTERNS = [
    ("phone", "手机号", re.compile(r"(?<!\d)1[3-9](?:[ -]?\d){9}(?!\d)"), "high", "手机号属于高风险隐私信息，建议遮盖后再分享。"),
    ("id_card", "身份证号", re.compile(r"(?<!\d)\d{6}(?:[ -]?\d){11}[\dXx](?!\d)"), "high", "身份证号可直接关联个人身份，建议完整遮盖。"),
    ("bank_card", "银行卡号", re.compile(r"(?<!\d)(?:\d[ -]?){16,19}(?!\d)"), "high", "银行卡号属于金融敏感信息，建议完整遮盖。"),
    ("email", "电子邮箱", re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", re.IGNORECASE), "medium", "邮箱可能关联账号身份，公开分享前建议遮盖。"),
    ("student_id", "学号", re.compile(r"(?:学号|student\s*id)\s*[:：]?\s*[A-Z0-9_-]{6,}", re.IGNORECASE), "medium", "学号可关联校内身份，公开分享前建议遮盖。"),
    ("order_no", "订单号", re.compile(r"(?:订单号?|order(?:\s*id)?)\s*[:：#-]?\s*[A-Z0-9_-]{6,}", re.IGNORECASE), "medium", "订单号可能被用于查询交易信息，建议按分享对象决定是否隐藏。"),
    ("address", "详细地址", re.compile(r"(?:住址|地址|收货地址)\s*[:：]?[^\n]{4,}|[\u4e00-\u9fff]{2,}(?:省|市|区|县)[^\n]{2,}(?:路|街|巷|号|楼|室)"), "high", "详细地址可能暴露住址或活动范围，建议完整打码。"),
]


@lru_cache(maxsize=1)
def _ocr_engine() -> Any:
    from rapidocr import RapidOCR

    return RapidOCR()


def _box_from_points(points: Any, image_width: int, image_height: int, padding: int = 4) -> Box:
    xs = [float(point[0]) for point in points]
    ys = [float(point[1]) for point in points]
    left = max(0, int(min(xs)) - padding)
    top = max(0, int(min(ys)) - padding)
    right = min(image_width, int(max(xs)) + padding)
    bottom = min(image_height, int(max(ys)) + padding)
    return Box(x=left, y=top, width=max(1, right - left), height=max(1, bottom - top))


def _redact_text(value: str, finding_type: str) -> str:
    compact = re.sub(r"\s+", "", value)
    if finding_type == "phone" and len(compact) >= 7:
        return f"{compact[:3]}****{compact[-4:]}"
    if finding_type in {"id_card", "bank_card"} and len(compact) >= 8:
        return f"{compact[:4]}****{compact[-4:]}"
    if finding_type == "email" and "@" in compact:
        local, domain = compact.split("@", 1)
        return f"{local[:2]}***@{domain}"
    if finding_type == "address":
        return "已识别到详细地址"
    return compact[:4] + "****" if len(compact) > 4 else "****"


def findings_from_ocr(
    texts: list[str], boxes: list[Any], scores: list[float], image_width: int, image_height: int, image_id: str
) -> list[PrivacyItem]:
    items: list[PrivacyItem] = []
    for text, points, confidence in zip(texts, boxes, scores):
        if confidence < OCR_CONFIDENCE_THRESHOLD or not text.strip():
            continue
        for finding_type, label, pattern, risk_level, suggestion in PRIVACY_PATTERNS:
            match = pattern.search(text)
            if not match:
                continue
            items.append(
                PrivacyItem(
                    id=f"{image_id}_{finding_type}_{len(items) + 1}",
                    type=finding_type,
                    label=label,
                    text=_redact_text(match.group(0), finding_type),
                    riskLevel=risk_level,
                    box=_box_from_points(points, image_width, image_height),
                    suggestion=suggestion,
                )
            )
    return items


def _detect_qr_codes(image_path: str, image_width: int, image_height: int, image_id: str) -> list[PrivacyItem]:
    try:
        import cv2

        image = cv2.imread(image_path)
        if image is None:
            return []
        detector = cv2.QRCodeDetector()
        qr_points: list[Any] = []
        try:
            detected, _decoded, points, _straight = detector.detectAndDecodeMulti(image)
            if detected and points is not None:
                qr_points.extend(points)
        except (AttributeError, cv2.error):
            pass
        if not qr_points:
            _decoded, points, _straight = detector.detectAndDecode(image)
            if points is not None:
                qr_points.append(points[0] if len(points) == 1 else points)

        return [
            PrivacyItem(
                id=f"{image_id}_qr_{index}",
                type="qr_code",
                label="二维码",
                text="二维码内容已隐藏",
                riskLevel="high",
                box=_box_from_points(points, image_width, image_height, padding=8),
                suggestion="二维码可能包含账号、订单或跳转信息，建议遮挡或确认内容后再分享。",
            )
            for index, points in enumerate(qr_points, start=1)
        ]
    except (ImportError, RuntimeError):
        return []


def detect_privacy_items(image_path: str, image_id: str, original_url: str) -> DetectResponse:
    if settings.demo_mode:
        return detect_demo_items(image_path, image_id, original_url)

    with Image.open(image_path) as image:
        width, height = image.size

    items: list[PrivacyItem] = []
    detector_mode = "ocr"
    detector_message = "已使用本地 OCR 与二维码检测引擎分析图片。"
    try:
        with _OCR_LOCK:
            result = _ocr_engine()(str(Path(image_path)))
        if result is not None and result.boxes is not None:
            result_texts = list(result.txts) if result.txts is not None else []
            result_boxes = list(result.boxes) if result.boxes is not None else []
            result_scores = [float(score) for score in result.scores] if result.scores is not None else []
            items.extend(
                findings_from_ocr(
                    result_texts,
                    result_boxes,
                    result_scores,
                    width,
                    height,
                    image_id,
                )
            )
    except (ImportError, OSError, RuntimeError, ValueError) as exc:
        detector_mode = "unavailable"
        detector_message = f"OCR 引擎暂不可用，仅完成二维码检测：{type(exc).__name__}。"

    qr_items = _detect_qr_codes(image_path, width, height, image_id)
    items.extend(qr_items)
    if detector_mode == "unavailable" and qr_items:
        detector_message = "OCR 引擎暂不可用，已完成二维码检测。"

    levels = [item.riskLevel for item in items]
    risk_level = highest_risk(levels)
    score = calculate_security_score(levels)
    if items:
        labels = "、".join(dict.fromkeys(item.label for item in items))
        summary = f"真实检测到 {len(items)} 个敏感区域（{labels}），建议确认并处理后再分享。"
    elif detector_mode == "unavailable":
        summary = "检测引擎未完整就绪，不能据此确认图片安全，请人工复核。"
    else:
        summary = "未识别到典型手机号、证件号、银行卡号、地址或二维码，分享前仍建议人工复核。"

    return DetectResponse(
        imageId=image_id,
        originalImageUrl=original_url,
        riskLevel=risk_level,
        score=score,
        summary=summary,
        detectorMode=detector_mode,
        detectorMessage=detector_message,
        items=items,
    )
