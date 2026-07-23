export type RiskLevel = 'high' | 'medium' | 'low';

export interface Finding {
  title: string;
  evidence: string;
  suggestion: string;
  riskLevel: RiskLevel;
}

export interface ModuleDefinition {
  id: string;
  icon: string;
  eyebrow: string;
  title: string;
  moment: string;
  description: string;
  route: string;
  accent: string;
  tint: string;
}

export interface ScanReport {
  findings: Finding[];
  score: number;
}

export interface CodeVulnerability {
  title: string;
  riskLevel: RiskLevel;
  filePath?: string;
  line?: number;
  snippet: string;
  reason: string;
  suggestion: string;
}

export interface CodeProjectFileSummary {
  path: string;
  language: string;
  riskLevel: RiskLevel;
  score: number;
  vulnerabilityCount: number;
}

export interface CodeAnalyzeResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  vulnerabilities: CodeVulnerability[];
  suggestions: string[];
  shouldSubmit: boolean;
  scanMode: 'single' | 'project';
  projectName?: string;
  totalEntries: number;
  scannedFiles: number;
  skippedFiles: number;
  topRiskFiles: CodeProjectFileSummary[];
}

export interface LinkCheckItem {
  label: string;
  riskLevel: RiskLevel;
  message: string;
}

export interface LinkCheckResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  checks: LinkCheckItem[];
  suggestions: string[];
  shouldOpen: boolean;
}

export interface QrDecodeResponse {
  decodedTexts: string[];
  primaryText: string;
  message: string;
}

export interface DocCheckItem {
  label: string;
  evidence: string;
  riskLevel: RiskLevel;
}

export interface DocCheckResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  checks: DocCheckItem[];
  suggestions: string[];
}

export interface PrivacyItem {
  label: string;
  text: string;
  riskLevel: RiskLevel;
  suggestion: string;
}

export interface DetectResponse {
  imageId: string;
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  items: PrivacyItem[];
}

export interface PrivacyProcessResponse {
  processedImageUrl: string;
  message: string;
}

export interface LocalHistoryRecord {
  id: string;
  module: 'privacy' | 'code' | 'link' | 'doc';
  moduleLabel: string;
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  createdAt: number;
}

export interface LocalHistoryInput {
  module: 'privacy' | 'code' | 'link' | 'doc';
  moduleLabel: string;
  riskLevel: RiskLevel;
  score: number;
  summary: string;
}
