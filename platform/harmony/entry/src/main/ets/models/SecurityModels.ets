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
  detectorSource?: 'rule' | 'deepseek';
  deepseekWarning?: string;
  scanMode?: 'single' | 'project';
  projectName?: string;
  totalEntries?: number;
  scannedFiles?: number;
  skippedFiles?: number;
  topRiskFiles?: CodeProjectFileSummary[];
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

/**
 * The rule set the server actually extracted from the brief. Echoing this back
 * is what lets a user see *which* requirement a report was produced from —
 * previously the report carried no trace of it.
 */
export interface ParsedRequirements {
  formats: string[];
  namingRule: string | null;
  requiredMaterials: string[];
  lengthRequirement: string | null;
  deadline: string | null;
  rawText: string;
}

export interface DocCheckResponse {
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  parsedRequirements: ParsedRequirements;
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
  detectorMode?: string;
  detectorMessage?: string;
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
  updatedAt: number;
  sourceLabel: string;
  status: string;
  processed: boolean;
  processedScore?: number;
  action: string;
  findings: Finding[];
  suggestions: string[];
}

export interface LocalHistoryInput {
  module: 'privacy' | 'code' | 'link' | 'doc';
  moduleLabel: string;
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  sourceLabel?: string;
  status?: string;
  findings?: Finding[];
  suggestions?: string[];
}
