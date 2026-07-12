import { describe, expect, it } from 'vitest';

import type { HistoryRecord } from '../types/privacy';
import { calculateOverallScore } from './scoring';

function record(module: HistoryRecord['module'], score: number): HistoryRecord {
  return {
    module,
    imageId: '',
    originalImageUrl: '',
    riskLevel: score >= 80 ? 'low' : score >= 60 ? 'medium' : 'high',
    score,
    summary: 'test',
    createdAt: '2026-07-12T12:00:00+08:00',
    status: '已生成报告'
  };
}

describe('calculateOverallScore', () => {
  it('uses the default score when no module has a result', () => {
    expect(calculateOverallScore([], {})).toBe(96);
  });

  it('combines current module scores with persisted scores from other modules', () => {
    const history = [record('privacy', 80), record('code', 60), record('link', 100), record('doc', 40)];
    expect(calculateOverallScore(history, { code: 90 })).toBe(78);
  });

  it('prefers a current result over that module history', () => {
    expect(calculateOverallScore([record('privacy', 30)], { privacy: 100 })).toBe(100);
  });
});
