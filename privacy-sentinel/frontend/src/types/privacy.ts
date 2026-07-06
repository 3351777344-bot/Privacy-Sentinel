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
