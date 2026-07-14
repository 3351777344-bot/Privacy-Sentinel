import { describe, expect, it } from 'vitest';

import { calculateOverallScore } from './scoring';

describe('calculateOverallScore', () => {
  it('returns 100 when no module has scores', () => {
    expect(calculateOverallScore({})).toBe(100);
  });

  it('averages module scores from all modules', () => {
    expect(calculateOverallScore({ privacy: 80, code: 60, link: 100, doc: 40 })).toBe(70);
  });

  it('handles partial module scores', () => {
    expect(calculateOverallScore({ privacy: 100, code: 90 })).toBe(95);
  });
});
