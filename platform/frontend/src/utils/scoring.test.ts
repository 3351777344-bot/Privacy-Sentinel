import { describe, expect, it } from 'vitest';
import { calculateOverallScore, effectiveScore } from './scoring';
import type { HistoryRecord } from '../types/privacy';

describe('calculateOverallScore', () => {
  it('returns 100 when no modules have scores', () => {
    expect(calculateOverallScore({})).toBe(100);
  });

  it('averages scores from four modules', () => {
    expect(calculateOverallScore({ privacy: 80, code: 70, link: 60, doc: 70 })).toBe(70);
  });

  it('averages partial modules', () => {
    expect(calculateOverallScore({ code: 90, link: 100 })).toBe(95);
  });
});

describe('effectiveScore', () => {
  const base: HistoryRecord = {
    imageId: 'test',
    originalImageUrl: '',
    riskLevel: 'low',
    summary: 'test',
    createdAt: '2026-01-01T00:00:00',
    status: 'done',
  };

  it('returns processedScore when available', () => {
    expect(effectiveScore({ ...base, processedScore: 85, score: 60 })).toBe(85);
  });

  it('falls back to score when processedScore is null', () => {
    expect(effectiveScore({ ...base, score: 60 })).toBe(60);
  });

  it('returns 100 as default fallback', () => {
    expect(effectiveScore(base)).toBe(100);
  });
});
