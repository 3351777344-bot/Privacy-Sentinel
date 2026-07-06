import type { Box, DetectResult, HistoryRecord, MaskResponse, MaskType } from '../types/privacy';

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
