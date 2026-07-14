import type { HistoryRecord } from '../types/privacy';

export type GuardianModule = 'privacy' | 'code' | 'link' | 'doc';

export const GUARDIAN_MODULES: GuardianModule[] = ['privacy', 'code', 'link', 'doc'];

export function calculateOverallScore(moduleAverages: Partial<Record<GuardianModule, number>>): number {
  const scores = GUARDIAN_MODULES
    .map((m) => moduleAverages[m])
    .filter((s): s is number => typeof s === 'number' && !isNaN(s));

  return scores.length ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length) : 100;
}

export function effectiveScore(record: HistoryRecord): number {
  return record.processedScore ?? record.score ?? 100;
}
