import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import CodePage from './CodePage';
import type { CodeAnalyzeResponse } from '../types/privacy';

const projectResult: CodeAnalyzeResponse = {
  scanMode: 'project',
  projectName: 'demo-project',
  totalEntries: 12,
  scannedFiles: 7,
  skippedFiles: 5,
  languages: { TypeScript: 4, Python: 3 },
  topRiskFiles: [
    {
      path: 'src/auth.ts',
      language: 'TypeScript',
      vulnerabilityCount: 2,
      riskLevel: 'high',
      score: 46,
    },
  ],
  fileSummaries: [],
  language: 'Multiple',
  languageSource: 'content',
  languageConfidence: 1,
  detectorSource: 'rule',
  vulnerabilities: [
    {
      id: 'src/auth.ts:1',
      type: 'secret',
      title: '疑似硬编码密钥',
      reason: '密钥不应写入源码。',
      suggestion: '改用安全配置注入。',
      snippet: 'const token = "secret";',
      filePath: 'src/auth.ts',
      line: 1,
      riskLevel: 'high',
      source: 'rule',
    },
  ],
  riskLevel: 'high',
  score: 46,
  summary: '项目中发现高风险问题。',
  suggestions: ['移除硬编码密钥。'],
  shouldSubmit: false,
};

function renderPage(overrides: Partial<React.ComponentProps<typeof CodePage>> = {}) {
  const props: React.ComponentProps<typeof CodePage> = {
    text: '',
    language: 'auto',
    file: null,
    result: null,
    loading: false,
    fixedCode: null,
    loadingFix: false,
    processingMode: 'local',
    onBack: vi.fn(),
    onTextChange: vi.fn(),
    onLanguageChange: vi.fn(),
    onProcessingModeChange: vi.fn(),
    onFileChange: vi.fn(),
    onAnalyze: vi.fn().mockResolvedValue(undefined),
    onFix: vi.fn().mockResolvedValue(undefined),
    onExport: vi.fn(),
    ...overrides,
  };
  const view = render(<CodePage {...props} />);
  return { ...view, props };
}

describe('CodePage project ZIP flow', () => {
  it('selects a ZIP as an archive instead of reading it into the editor', async () => {
    const user = userEvent.setup();
    const { container, props } = renderPage({ text: 'old code' });
    const input = container.querySelector('input[type="file"]') as HTMLInputElement;
    const archive = new File(['PK'], 'course-project.zip', { type: 'application/zip' });

    await user.upload(input, archive);

    expect(props.onTextChange).toHaveBeenCalledWith('');
    expect(props.onFileChange).toHaveBeenCalledWith(archive);
  });

  it('shows project-level metrics and file paths in the report', () => {
    renderPage({
      file: new File(['PK'], 'demo-project.zip', { type: 'application/zip' }),
      result: projectResult,
    });

    expect(screen.getByText('项目扫描概览')).not.toBeNull();
    expect(screen.getByText('压缩包条目').nextElementSibling?.textContent).toBe('12');
    expect(screen.getAllByText('src/auth.ts').length).toBeGreaterThan(0);
    expect(
      screen.getByText((_, element) =>
        element?.tagName === 'SPAN' && element.textContent?.replace(/\s/g, '') === 'TypeScript4'
      )
    ).not.toBeNull();
    expect(screen.queryByText(/一键修复选中/)).toBeNull();
  });
});
