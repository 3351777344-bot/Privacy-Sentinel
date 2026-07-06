from typing import List, Optional

from pydantic import BaseModel


class Box(BaseModel):
    x: int
    y: int
    width: int
    height: int


class PrivacyItem(BaseModel):
    id: str
    type: str
    label: str
    text: str
    riskLevel: str
    box: Box
    suggestion: str


class DetectResponse(BaseModel):
    imageId: str
    originalImageUrl: str
    riskLevel: str
    summary: str
    items: List[PrivacyItem]


class MaskRequest(BaseModel):
    imageId: str
    maskType: str
    items: List[Box]


class MaskResponse(BaseModel):
    processedImageUrl: str
    message: str


class HistoryRecord(BaseModel):
    imageId: str
    originalImageUrl: str
    processedImageUrl: Optional[str] = None
    riskLevel: str
    summary: str
    createdAt: str
    status: str
