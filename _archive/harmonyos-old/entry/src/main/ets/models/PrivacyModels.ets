export type RiskLevel = 'high' | 'medium' | 'low' | 'safe';

export interface PrivacyRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PrivacyItem {
  id: string;
  type: string;
  label: string;
  valuePreview: string;
  riskLevel: RiskLevel;
  suggestion: string;
  rect: PrivacyRect;
}

export interface DetectResult {
  id: string;
  imageName: string;
  scene: string;
  riskLevel: RiskLevel;
  score: number;
  summary: string;
  privacyItems: PrivacyItem[];
  detectedAt: string;
}

export interface HistoryRecord {
  id: string;
  title: string;
  scene: string;
  riskLevel: RiskLevel;
  itemCount: number;
  createdAt: string;
}

export interface MaskMode {
  id: string;
  name: string;
  description: string;
}

