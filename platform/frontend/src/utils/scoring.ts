import type { HistoryRecord } from '../types/privacy';

export type GuardianModule = 'privacy' | 'code' | 'link' | 'doc';

export const GUARDIAN_MODULES: GuardianModule[] = ['privacy', 'code', 'link', 'doc'];

export function calculateOverallScore(
  records: HistoryRecord[],
  latestScores: Partial<Record<GuardianModule, number>>
): number {
  const scores = GUARDIAN_MODULES.map(
    (module) => latestScores[module] ?? records.find((record) => (record.module ?? 'privacy') === module)?.score
  ).filter((score): score is number => typeof score === 'number');

  return scores.length ? Math.round(scores.reduce((total, score) => total + score, 0) / scores.length) : 96;
}
