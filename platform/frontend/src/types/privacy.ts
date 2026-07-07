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
  summary: string;
  items: PrivacyItem[];
}

export interface HistoryRecord {
  imageId: string;
  originalImageUrl: string;
  processedImageUrl?: string | null;
  riskLevel: RiskLevel;
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

export interface ScamAnalyzeResponse {
  riskLevel: RiskLevel;
  score: number;
  reasons: TextFinding[];
  suggestions: string[];
}

export interface LinkCheckResponse {
  riskLevel: RiskLevel;
  normalizedUrl: string;
  checks: TextFinding[];
  suggestions: string[];
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
