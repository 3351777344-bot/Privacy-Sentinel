import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LocalHistoryInput, LocalHistoryRecord } from '../models/SecurityModels';

const STORE_NAME: string = 'guardianhub_local_history';
const HISTORY_KEY: string = 'records';
const MAX_RECORDS: number = 20;

export class HistoryStore {
  static async list(context: common.UIAbilityContext): Promise<LocalHistoryRecord[]> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const rawValue = await store.get(HISTORY_KEY, '[]');
      const rawText = rawValue as string;
      const parsed = JSON.parse(rawText) as LocalHistoryRecord[];
      return parsed.slice(0, MAX_RECORDS);
    } catch (_) {
      return [];
    }
  }

  static async add(context: common.UIAbilityContext, input: LocalHistoryInput): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const records = await HistoryStore.list(context);
      const createdAt = Date.now();
      const nextRecord: LocalHistoryRecord = {
        id: `${input.module}-${createdAt}`,
        module: input.module,
        moduleLabel: input.moduleLabel,
        riskLevel: input.riskLevel,
        score: input.score,
        summary: input.summary,
        createdAt: createdAt
      };
      records.unshift(nextRecord);
      await store.put(HISTORY_KEY, JSON.stringify(records.slice(0, MAX_RECORDS)));
      await store.flush();
    } catch (_) {
      // History persistence must never turn a successful safety check into a failed request.
    }
  }
}
