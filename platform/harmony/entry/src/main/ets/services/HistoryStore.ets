import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LocalHistoryInput, LocalHistoryRecord } from '../models/SecurityModels';

const STORE_NAME: string = 'guardianhub_local_history';
const HISTORY_KEY: string = 'records';
const MAX_RECORDS: number = 100;

export class HistoryStore {
  static async list(context: common.UIAbilityContext): Promise<LocalHistoryRecord[]> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const rawValue = await store.get(HISTORY_KEY, '[]');
      const rawText = rawValue as string;
      const parsed = JSON.parse(rawText) as LocalHistoryRecord[];
      return parsed.slice(0, MAX_RECORDS).map((record: LocalHistoryRecord): LocalHistoryRecord => {
        return HistoryStore.normalize(record);
      });
    } catch (_) {
      return [];
    }
  }

  static async add(context: common.UIAbilityContext, input: LocalHistoryInput): Promise<string> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const records = await HistoryStore.list(context);
      const createdAt = Date.now();
      const nextRecord: LocalHistoryRecord = {
        id: `${input.module}-${createdAt}-${Math.floor(Math.random() * 100000)}`,
        module: input.module,
        moduleLabel: input.moduleLabel,
        riskLevel: input.riskLevel,
        score: input.score,
        summary: input.summary,
        createdAt: createdAt,
        updatedAt: createdAt,
        sourceLabel: input.sourceLabel ?? '',
        status: input.status ?? (input.riskLevel === 'low' ? '已检测' : '待复核'),
        processed: false,
        action: '',
        findings: input.findings ?? [],
        suggestions: input.suggestions ?? []
      };
      records.unshift(nextRecord);
      const saved = await HistoryStore.save(store, records);
      return saved ? nextRecord.id : '';
    } catch (_) {
      // History persistence must never turn a successful safety check into a failed request.
      return '';
    }
  }

  static async get(context: common.UIAbilityContext, id: string): Promise<LocalHistoryRecord | undefined> {
    const records = await HistoryStore.list(context);
    return records.find((record: LocalHistoryRecord): boolean => record.id === id);
  }

  static async updateProcessed(context: common.UIAbilityContext, id: string,
    action: string, processedScore?: number): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const records = await HistoryStore.list(context);
      const index = records.findIndex((record: LocalHistoryRecord): boolean => record.id === id);
      if (index < 0) {
        return false;
      }
      records[index].processed = true;
      if (processedScore !== undefined) {
        records[index].processedScore = processedScore;
      }
      records[index].status = '已处理';
      records[index].action = action;
      records[index].updatedAt = Date.now();
      return await HistoryStore.save(store, records);
    } catch (_) {
      return false;
    }
  }

  static async updateAction(context: common.UIAbilityContext, id: string,
    action: string, status: string = '已处置'): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const records = await HistoryStore.list(context);
      const index = records.findIndex((record: LocalHistoryRecord): boolean => record.id === id);
      if (index < 0) {
        return false;
      }
      records[index].action = action;
      records[index].status = status;
      records[index].updatedAt = Date.now();
      return await HistoryStore.save(store, records);
    } catch (_) {
      return false;
    }
  }

  static async remove(context: common.UIAbilityContext, id: string): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const records = await HistoryStore.list(context);
      const retained = records.filter((record: LocalHistoryRecord): boolean => record.id !== id);
      if (retained.length === records.length) {
        return false;
      }
      return await HistoryStore.save(store, retained);
    } catch (_) {
      return false;
    }
  }

  static async clear(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.delete(HISTORY_KEY);
      await store.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  private static normalize(record: LocalHistoryRecord): LocalHistoryRecord {
    return {
      id: record.id,
      module: record.module,
      moduleLabel: record.moduleLabel,
      riskLevel: record.riskLevel,
      score: record.score,
      summary: record.summary,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt ?? record.createdAt,
      sourceLabel: record.sourceLabel ?? '',
      status: record.status ?? (record.riskLevel === 'low' ? '已检测' : '待复核'),
      processed: record.processed ?? false,
      processedScore: record.processedScore,
      action: record.action ?? '',
      findings: record.findings ?? [],
      suggestions: record.suggestions ?? []
    };
  }

  private static async save(store: preferences.Preferences,
    records: LocalHistoryRecord[]): Promise<boolean> {
    try {
      await store.put(HISTORY_KEY, JSON.stringify(records.slice(0, MAX_RECORDS)));
      await store.flush();
      return true;
    } catch (_) {
      return false;
    }
  }
}
