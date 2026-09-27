import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import DocReportPanel from './DocReportPanel';
import type { DocCheckResponse, ParsedRequirements } from '../types/privacy';

function docResult(parsed: Partial<ParsedRequirements>): DocCheckResponse {
  return {
    riskLevel: 'low',
    score: 93,
    summary: '材料格式、清单和隐私风险未发现明显问题。',
    parsedRequirements: {
      formats: ['pdf'],
      namingRule: '学号_姓名_课程名称',
      requiredMaterials: ['封面'],
      lengthRequirement: null,
      deadline: null,
      rawText: '提交课程论文 PDF。',
      ...parsed
    },
    files: [],
    checks: [],
    suggestions: []
  };
}

describe('DocReportPanel provenance', () => {
  it('labels a model-parsed report as online and lists its content requirements', () => {
    render(
      <DocReportPanel
        result={docResult({
          source: 'online',
          sourceFields: ['formats', 'contentRequirements'],
          contentRequirements: ['正文不少于3000字', '需给出测试结论']
        })}
      />
    );

    expect(screen.getByText('在线 AI 识别')).toBeTruthy();
    expect(screen.getByText(/需给出测试结论/)).toBeTruthy();
    expect(screen.queryByText(/当前后端版本不包含联网解析/)).toBeNull();
  });

  it('labels a rule-parsed report as local without crying wolf about the backend', () => {
    render(
      <DocReportPanel
        result={docResult({
          source: 'local',
          modelWarning: '联网解析未启用，本次报告仅依据本地规则。'
        })}
      />
    );

    expect(screen.getByText('本地规则解析')).toBeTruthy();
    expect(screen.getByText('联网解析未启用，本次报告仅依据本地规则。')).toBeTruthy();
    // A disabled model is not a stale backend: the field is present and honest.
    expect(screen.queryByText(/当前后端版本不包含联网解析/)).toBeNull();
  });

  it('says so when the backend predates the online pass and ignored the mode', () => {
    // No `source` key at all — what a backend without the online pass returns
    // even when the request asked for online mode.
    render(<DocReportPanel result={docResult({})} />);

    expect(screen.getByText(/当前后端版本不包含联网解析/)).toBeTruthy();
  });
});
