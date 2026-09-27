import type {
  CodeAnalyzeResponse,
  DetectResult,
  DocCheckResponse,
  HistoryRecord,
  LinkCheckResponse,
  MaskResponse,
  MaskType,
  ProcessingMode,
  QrDecodeResponse
} from '../types/privacy';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://127.0.0.1:8001';

const FETCH_TIMEOUT_MS = 30_000; // 30 seconds
const DETECT_LOCAL_TIMEOUT_MS = 60_000;
const DETECT_ONLINE_TIMEOUT_MS = 120_000;

async function fetchWithTimeout(input: RequestInfo, init?: RequestInit, timeoutMs = FETCH_TIMEOUT_MS): Promise<Response> {
  if (init?.method === 'POST') {
    if (!window.confirm(`本次操作会向 ${API_BASE_URL} 发送所选原文件或输入文本及必要元数据，用于分析或处理。联网增强还可能调用已配置的模型服务。是否授权本次发送？`)) {
      throw new Error('未授权上传，未发送数据。');
    }
    const headers = new Headers(init.headers);
    headers.set('X-Guardian-Consent', 'explicit');
    init = { ...init, headers };
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(input, { ...init, signal: controller.signal });
    return response;
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new Error('请求超时，请稍后重试。联网增强可能需要更长时间。');
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

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

export async function detectImage(file: File, processingMode: ProcessingMode): Promise<DetectResult> {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('processing_mode', processingMode);
  const timeoutMs = processingMode === 'online' ? DETECT_ONLINE_TIMEOUT_MS : DETECT_LOCAL_TIMEOUT_MS;
  const response = await fetchWithTimeout(
    `${API_BASE_URL}/api/detect`,
    {
      method: 'POST',
      body: formData
    },
    timeoutMs
  );
  return parseResponse<DetectResult>(response);
}

export async function processPrivacyImage(
  imageId: string,
  maskType: MaskType,
  scope: 'high' | 'all' | 'custom',
  itemIds: string[] = []
): Promise<MaskResponse> {
  const response = await fetchWithTimeout(`${API_BASE_URL}/api/privacy/process`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ imageId, maskType, scope, itemIds })
  });
  return parseResponse<MaskResponse>(response);
}

export interface PaginatedHistory {
  records: HistoryRecord[];
  total: number;
  offset: number;
  limit: number;
}

export async function fetchHistory(offset = 0, limit = 20): Promise<PaginatedHistory> {
  const response = await fetchWithTimeout(`${API_BASE_URL}/api/history?offset=${offset}&limit=${limit}`);
  return parseResponse<PaginatedHistory>(response);
}

export async function fetchModuleAverages(): Promise<Record<string, number>> {
  const response = await fetchWithTimeout(`${API_BASE_URL}/api/history/module-averages`);
  return parseResponse<Record<string, number>>(response);
}

export async function deleteHistoryRecord(recordId: string): Promise<void> {
  const response = await fetchWithTimeout(`${API_BASE_URL}/api/history/${recordId}`, { method: 'DELETE' });
  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: '删除失败' }));
    throw new Error(error.detail ?? '删除失败');
  }
}

export async function analyzeCode(
  language: string,
  code: string,
  processingMode: ProcessingMode,
  file?: File | null
): Promise<CodeAnalyzeResponse> {
  if (file) {
    const formData = new FormData();
    formData.append('language', language);
    formData.append('processing_mode', processingMode);
    formData.append('file', file);
    const response = await fetchWithTimeout(`${API_BASE_URL}/api/code/analyze`, {
      method: 'POST',
      body: formData
    });
    return parseResponse<CodeAnalyzeResponse>(response);
  }

  const response = await fetchWithTimeout(`${API_BASE_URL}/api/code/analyze`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ language, code, processingMode })
  });
  return parseResponse<CodeAnalyzeResponse>(response);
}

export async function checkLink(url: string, source: string): Promise<LinkCheckResponse> {
  const response = await fetchWithTimeout(`${API_BASE_URL}/api/link/check`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url, source })
  });
  return parseResponse<LinkCheckResponse>(response);
}

export async function decodeQrImage(file: File): Promise<QrDecodeResponse> {
  const formData = new FormData();
  formData.append('file', file);
  const response = await fetchWithTimeout(`${API_BASE_URL}/api/link/qr/decode`, {
    method: 'POST',
    body: formData
  });
  return parseResponse<QrDecodeResponse>(response);
}

export async function fixCode(
  code: string,
  language: string,
  items: Array<{type: string, title: string, line?: number | null, snippet: string}>,
  recordId?: string | null,
  originalScore?: number,
  totalVulns?: number,
): Promise<{fixedCode: string}> {
  const response = await fetchWithTimeout(
    `${API_BASE_URL}/api/code/fix`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        code,
        language: language === 'auto' ? 'python' : language,
        items: items.map((item) => ({
          type: item.type,
          title: item.title,
          line: item.line ?? null,
          snippet: item.snippet ?? ''
        })),
        recordId: recordId || undefined,
        originalScore: originalScore ?? 0,
        totalVulns: totalVulns ?? items.length
      })
    },
    120_000
  );
  return parseResponse<{fixedCode: string}>(response);
}

export async function exportCode(code: string, language: string, filename?: string): Promise<void> {
  const extMap: Record<string, string> = { python: '.py', java: '.java', javascript: '.js', typescript: '.ts', sql: '.sql' };
  const ext = extMap[language] ?? '.txt';
  const name = filename ?? `fixed_code${ext}`;
  const blob = new Blob([code], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

export async function checkDoc(requirementText: string, files: File[]): Promise<DocCheckResponse> {
  const formData = new FormData();
  formData.append('requirement_text', requirementText);
  files.forEach((file) => formData.append('files', file));

  const response = await fetchWithTimeout(`${API_BASE_URL}/api/doc/check`, {
    method: 'POST',
    body: formData
  });
  return parseResponse<DocCheckResponse>(response);
}
