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
    url: str
    source: Optional[str] = "其他"


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
