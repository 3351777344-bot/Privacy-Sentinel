import type {
  Box,
  CodeAnalyzeResponse,
  DetectResult,
  DocCheckResponse,
  HistoryRecord,
  LinkCheckResponse,
  MaskResponse,
  MaskType
} from '../types/privacy';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://127.0.0.1:8000';

async function parseResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: '请求失败，请稍后重试。' }));
    throw new Error(error.detail ?? '请求失败，请稍后重试。');
  }
  return response.json() as Promise<T>;
}

export function toAssetUrl(url?: string | null): string {
  if (!url) return '';
  return url.startsWith('http') ? url : `${API_BASE_URL}${url}`;
}

export async function detectImage(file: File): Promise<DetectResult> {
  const formData = new FormData();
  formData.append('file', file);
  const response = await fetch(`${API_BASE_URL}/api/detect`, {
    method: 'POST',
    body: formData
  });
  return parseResponse<DetectResult>(response);
}

export async function maskImage(imageId: string, maskType: MaskType, items: Box[]): Promise<MaskResponse> {
  const response = await fetch(`${API_BASE_URL}/api/mask`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ imageId, maskType, items })
  });
  return parseResponse<MaskResponse>(response);
}

export async function fetchHistory(): Promise<HistoryRecord[]> {
  const response = await fetch(`${API_BASE_URL}/api/history`);
  return parseResponse<HistoryRecord[]>(response);
}

export async function saveHistory(
  module: 'code' | 'link' | 'doc',
  riskLevel: HistoryRecord['riskLevel'],
  score: number,
  summary: string
): Promise<HistoryRecord> {
  const response = await fetch(`${API_BASE_URL}/api/history`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ module, riskLevel, score, summary, status: '已生成报告' })
  });
  return parseResponse<HistoryRecord>(response);
}

export async function analyzeCode(language: string, code: string, file?: File | null): Promise<CodeAnalyzeResponse> {
  if (file) {
    const formData = new FormData();
    formData.append('language', language);
    formData.append('file', file);
    const response = await fetch(`${API_BASE_URL}/api/code/analyze`, {
      method: 'POST',
      body: formData
    });
    return parseResponse<CodeAnalyzeResponse>(response);
  }

  const response = await fetch(`${API_BASE_URL}/api/code/analyze`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ language, code })
  });
  return parseResponse<CodeAnalyzeResponse>(response);
}

export async function checkLink(url: string, source: string): Promise<LinkCheckResponse> {
  const response = await fetch(`${API_BASE_URL}/api/link/check`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url, source })
  });
  return parseResponse<LinkCheckResponse>(response);
}

export async function checkDoc(requirementText: string, files: File[]): Promise<DocCheckResponse> {
  const formData = new FormData();
  formData.append('requirement_text', requirementText);
  files.forEach((file) => formData.append('files', file));

  const response = await fetch(`${API_BASE_URL}/api/doc/check`, {
    method: 'POST',
    body: formData
  });
  return parseResponse<DocCheckResponse>(response);
}
