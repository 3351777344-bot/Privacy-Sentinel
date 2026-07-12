from typing import List, Literal, Optional

from pydantic import BaseModel, Field


RiskLevel = Literal["high", "medium", "low"]
MaskType = Literal["black", "blur", "mosaic"]
DetectorMode = Literal["agent", "hybrid", "vision_api", "ocr", "demo", "unavailable"]


class Box(BaseModel):
    x: int = Field(ge=-100_000, le=100_000)
    y: int = Field(ge=-100_000, le=100_000)
    width: int = Field(gt=0, le=100_000)
    height: int = Field(gt=0, le=100_000)


class PrivacyItem(BaseModel):
    id: str
    type: str
    label: str
    text: str
    riskLevel: RiskLevel
    box: Box
    suggestion: str
    confidence: float = Field(default=1.0, ge=0, le=1)
    source: Literal["ocr", "qr", "face", "rule", "vision_api", "demo"] = "rule"
    recommendedMaskType: MaskType = "mosaic"


class DetectResponse(BaseModel):
    imageId: str
    originalImageUrl: str
    riskLevel: RiskLevel
    score: int = Field(ge=0, le=100)
    summary: str
    detectorMode: DetectorMode
    detectorMessage: str
    items: List[PrivacyItem]


class MaskRequest(BaseModel):
    imageId: str = Field(pattern=r"^img_[a-f0-9]{12}$")
    maskType: MaskType
    items: List[Box] = Field(min_length=1, max_length=100)


class MaskResponse(BaseModel):
    processedImageUrl: str
    message: str


class PrivacyProcessRequest(BaseModel):
    imageId: str = Field(pattern=r"^img_[a-f0-9]{12}$")
    scope: Literal["high", "all", "custom"] = "high"
    maskType: Optional[MaskType] = None
    itemIds: List[str] = Field(default_factory=list, max_length=100)


class HistoryRecord(BaseModel):
    recordId: str = ""
    module: Literal["privacy", "code", "link", "doc"] = "privacy"
    imageId: str = ""
    originalImageUrl: str = ""
    processedImageUrl: Optional[str] = None
    riskLevel: RiskLevel
    score: Optional[int] = Field(default=None, ge=0, le=100)
    summary: str
    createdAt: str
    status: str


class HistoryCreate(BaseModel):
    module: Literal["code", "link", "doc"]
    riskLevel: RiskLevel
    score: int = Field(ge=0, le=100)
    summary: str = Field(min_length=1, max_length=1000)
    status: str = Field(default="已生成报告", min_length=1, max_length=100)


class TextFinding(BaseModel):
    label: str
    evidence: str
    riskLevel: RiskLevel


class CodeAnalyzeRequest(BaseModel):
    language: Optional[str] = None
    code: str


class CodeVulnerability(BaseModel):
    id: str
    type: str
    title: str
    riskLevel: RiskLevel
    line: Optional[int] = None
    snippet: str
    reason: str
    suggestion: str


class CodeAnalyzeResponse(BaseModel):
    riskLevel: RiskLevel
    score: int
    summary: str
    language: str
    languageSource: Literal["explicit", "filename", "content", "fallback"]
    languageConfidence: float = Field(ge=0, le=1)
    vulnerabilities: List[CodeVulnerability]
    suggestions: List[str]
    shouldSubmit: bool


class ScamAnalyzeRequest(BaseModel):
    text: str


class ScamAnalyzeResponse(BaseModel):
    riskLevel: RiskLevel
    score: int
    reasons: List[TextFinding]
    suggestions: List[str]


class LinkCheckRequest(BaseModel):
    url: str = Field(min_length=1, max_length=4096)
    source: Optional[str] = Field(default="其他", max_length=100)


class LinkCheckItem(BaseModel):
    id: str
    label: str
    status: Literal["pass", "warning", "fail"]
    riskLevel: RiskLevel
    message: str


class SuspiciousParam(BaseModel):
    name: str
    riskLevel: RiskLevel
    reason: str


class SourceRisk(BaseModel):
    source: str
    riskLevel: RiskLevel
    reason: str


class LinkCheckResponse(BaseModel):
    riskLevel: RiskLevel
    score: int
    summary: str
    normalizedUrl: str
    checks: List[LinkCheckItem]
    suspiciousParams: List[SuspiciousParam]
    sourceRisk: SourceRisk
    suggestions: List[str]
    shouldOpen: bool


class QrDecodeResponse(BaseModel):
    decodedTexts: List[str]
    primaryText: str
    message: str


class ParsedRequirements(BaseModel):
    formats: List[str]
    namingRule: Optional[str] = None
    requiredMaterials: List[str]
    lengthRequirement: Optional[str] = None
    deadline: Optional[str] = None
    rawText: str


class DocFileSummary(BaseModel):
    fileName: str
    extension: str
    contentType: str
    size: int
    status: str
    wordCount: int
    pageCount: Optional[int] = None


class DocCheckItem(BaseModel):
    category: Literal["format", "completeness", "privacy"]
    label: str
    evidence: str
    riskLevel: RiskLevel
    status: Literal["pass", "warning", "fail"]


class DocCheckResponse(BaseModel):
    riskLevel: RiskLevel
    score: int
    summary: str
    parsedRequirements: ParsedRequirements
    files: List[DocFileSummary]
    checks: List[DocCheckItem]
    suggestions: List[str]
