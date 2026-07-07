from typing import List, Literal, Optional

from pydantic import BaseModel


RiskLevel = Literal["high", "medium", "low"]


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
    riskLevel: RiskLevel
    box: Box
    suggestion: str


class DetectResponse(BaseModel):
    imageId: str
    originalImageUrl: str
    riskLevel: RiskLevel
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
    riskLevel: RiskLevel
    summary: str
    createdAt: str
    status: str


class TextFinding(BaseModel):
    label: str
    evidence: str
    riskLevel: RiskLevel


class ScamAnalyzeRequest(BaseModel):
    text: str


class ScamAnalyzeResponse(BaseModel):
    riskLevel: RiskLevel
    score: int
    reasons: List[TextFinding]
    suggestions: List[str]


class LinkCheckRequest(BaseModel):
    url: str


class LinkCheckResponse(BaseModel):
    riskLevel: RiskLevel
    normalizedUrl: str
    checks: List[TextFinding]
    suggestions: List[str]


class DocCheckRequest(BaseModel):
    fileName: Optional[str] = None


class ChecklistItem(BaseModel):
    item: str
    status: Literal["pass", "warning", "pending"]


class DocCheckResponse(BaseModel):
    riskLevel: RiskLevel
    checks: List[TextFinding]
    checklist: List[ChecklistItem]
    suggestions: List[str]
