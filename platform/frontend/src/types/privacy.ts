export type RiskLevel = 'high' | 'medium' | 'low';
export type MaskType = 'black' | 'blur' | 'mosaic';

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PrivacyItem {
  id: string;
  type: string;
  label: string;
  text: string;
  riskLevel: RiskLevel;
  box: Box;
  suggestion: string;
}

export interface DetectResult {
  imageId: string;
  originalImageUrl: string;
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  detectorMode: 'ocr' | 'demo' | 'unavailable';
  detectorMessage: string;
  items: PrivacyItem[];
}

export interface HistoryRecord {
  recordId?: string;
  module?: 'privacy' | 'code' | 'link' | 'doc';
  imageId: string;
  originalImageUrl: string;
  processedImageUrl?: string | null;
  riskLevel: RiskLevel;
  score?: number | null;
  summary: string;
  createdAt: string;
  status: string;
}

export interface MaskResponse {
  processedImageUrl: string;
  message: string;
}

export interface TextFinding {
  label: string;
  evidence: string;
  riskLevel: RiskLevel;
}

export interface CodeVulnerability {
  id: string;
  type: string;
  title: string;
  riskLevel: RiskLevel;
  line?: number | null;
  snippet: string;
  reason: string;
  suggestion: string;
}

export interface CodeAnalyzeResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  language: string;
  languageSource: 'explicit' | 'filename' | 'content' | 'fallback';
  languageConfidence: number;
  vulnerabilities: CodeVulnerability[];
  suggestions: string[];
  shouldSubmit: boolean;
}

export interface LinkCheckItem {
  id: string;
  label: string;
  status: 'pass' | 'warning' | 'fail';
  riskLevel: RiskLevel;
  message: string;
}

export interface SuspiciousParam {
  name: string;
  riskLevel: RiskLevel;
  reason: string;
}

export interface SourceRisk {
  source: string;
  riskLevel: RiskLevel;
  reason: string;
}

export interface LinkCheckResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  normalizedUrl: string;
  checks: LinkCheckItem[];
  suspiciousParams: SuspiciousParam[];
  sourceRisk: SourceRisk;
  suggestions: string[];
  shouldOpen: boolean;
}

export interface DocCheckResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  parsedRequirements: {
    formats: string[];
    namingRule?: string | null;
    requiredMaterials: string[];
    lengthRequirement?: string | null;
    deadline?: string | null;
    rawText: string;
  };
  files: Array<{
    fileName: string;
    extension: string;
    contentType: string;
    size: number;
    status: string;
    wordCount: number;
    pageCount?: number | null;
  }>;
  checks: Array<TextFinding & {
    category: 'format' | 'completeness' | 'privacy';
    status: 'pass' | 'warning' | 'fail';
  }>;
  checklist?: Array<{
    item: string;
    status: 'pass' | 'warning' | 'pending';
  }>;
  suggestions: string[];
}
