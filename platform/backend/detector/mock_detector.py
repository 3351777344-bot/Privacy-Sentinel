from pathlib import Path
from typing import List

from PIL import Image

from detector.risk_classifier import classify_overall_risk
from modules.risk_scoring import calculate_security_score
from schemas.models import Box, DetectResponse, PrivacyItem


def _box(width: int, height: int, x: float, y: float, w: float, h: float) -> Box:
    return Box(
        x=round(width * x),
        y=round(height * y),
        width=max(24, round(width * w)),
        height=max(20, round(height * h)),
    )


def detect_privacy_items(image_path: str, image_id: str, original_url: str) -> DetectResponse:
    """Generate proportional mock privacy boxes so the demo works on varied image sizes."""
    Path(image_path)
    with Image.open(image_path) as image:
        width, height = image.size

    items: List[PrivacyItem] = [
        PrivacyItem(
            id=f"{image_id}_phone",
            type="phone",
            label="手机号",
            text="138****1234",
            riskLevel="high",
            box=_box(width, height, 0.16, 0.23, 0.34, 0.07),
            suggestion="手机号属于高风险隐私信息，建议遮盖后再分享。",
        ),
        PrivacyItem(
            id=f"{image_id}_address",
            type="address",
            label="收货地址",
            text="北京市海淀区某科技园 8 号楼",
            riskLevel="high",
            box=_box(width, height, 0.14, 0.39, 0.62, 0.08),
            suggestion="详细地址可能暴露个人住址或活动范围，建议完整打码。",
        ),
        PrivacyItem(
            id=f"{image_id}_qr",
            type="qr_code",
            label="二维码",
            text="二维码区域",
            riskLevel="high",
            box=_box(width, height, 0.72, 0.58, 0.18, 0.18),
            suggestion="二维码可能包含订单、账号或跳转信息，分享前建议遮挡。",
        ),
        PrivacyItem(
            id=f"{image_id}_order",
            type="order_no",
            label="订单号",
            text="ORDER-20260706-8848",
            riskLevel="medium",
            box=_box(width, height, 0.17, 0.55, 0.45, 0.06),
            suggestion="订单号可能被用于查询交易信息，建议根据分享对象决定是否隐藏。",
        ),
        PrivacyItem(
            id=f"{image_id}_nickname",
            type="nickname",
            label="聊天昵称",
            text="小夏同学",
            riskLevel="medium",
            box=_box(width, height, 0.12, 0.12, 0.22, 0.06),
            suggestion="昵称可能暴露身份关系，公开分享时建议谨慎处理。",
        ),
    ]

    risk_level = classify_overall_risk(items)
    summary = "检测到手机号、地址、二维码等高风险隐私信息，建议打码后再分享。"
    return DetectResponse(
        imageId=image_id,
        originalImageUrl=original_url,
        riskLevel=risk_level,
        score=calculate_security_score([item.riskLevel for item in items]),
        summary=summary,
        detectorMode="demo",
        detectorMessage="当前由 GUARDIANHUB_DEMO_MODE 显式启用演示检测框。",
        items=items,
    )
