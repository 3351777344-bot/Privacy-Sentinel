/**
 * Doc Shield — requirement text persistence.
 *
 * The requirement text used to be a bare `@State` initialised to a hardcoded
 * string, so leaving the page and coming back silently reset it to that sample
 * and the next scan ran against the old requirement. It is now persisted in
 * KV-Store.
 *
 * The keyword pre-check lives in `scanners/RequirementKeywords` (pure, so it is
 * unit-testable under Node); this module owns storage only.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ParsedRequirements } from '../models/SecurityModels';

const STORE_NAME: string = 'guardianhub_doc_shield';
const REQUIREMENT_KEY: string = 'requirement_text';
/** Longer than any sane submission brief; guards the KV-Store write. */
const MAX_REQUIREMENT_CHARS: number = 4000;

export class RequirementStore {
  private static cached: string = '';

  /**
   * Text to show in the editor. Returns `undefined` when storage could not be
   * read, so the caller can retry once the ability context is live rather than
   * silently losing the user's edit. An empty store yields an empty string: the
   * requirement is the user's own submission brief, so prefilling a sample would
   * make the next scan run against text the user never wrote.
   */
  static async load(context: common.Context): Promise<string | undefined> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(REQUIREMENT_KEY, '');
      const text: string = raw as string;
      RequirementStore.cached = text;
      return text;
    } catch (_) {
      return undefined;
    }
  }

  /** Persist an edit. Empty input clears the stored copy. */
  static async save(context: common.Context, text: string): Promise<void> {
    const scoped: string = text.length > MAX_REQUIREMENT_CHARS
      ? text.substring(0, MAX_REQUIREMENT_CHARS) : text;
    RequirementStore.cached = scoped;
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(REQUIREMENT_KEY, scoped);
      await store.flush();
    } catch (_) {
      // A failed write only costs persistence; the current session still works.
    }
  }

  /** Last value seen in this process, without touching storage. */
  static current(): string {
    return RequirementStore.cached;
  }

  /** Clear the stored copy so the editor comes back empty on next open. */
  static async reset(context: common.Context): Promise<string> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.delete(REQUIREMENT_KEY);
      await store.flush();
    } catch (_) {
    }
    RequirementStore.cached = '';
    return '';
  }

  /**
   * Render the server's authoritative parse as one line, so a report can state
   * which rules produced it. Returns a plain sentence when nothing was
   * extracted — that is the single most useful thing to show, because it
   * explains why a report looks unrelated to the brief.
   */
  static describeParsed(parsed: ParsedRequirements | undefined): string {
    if (parsed === undefined) {
      return '';
    }
    const parts: string[] = [];
    if (parsed.formats.length > 0) {
      parts.push(`格式 ${parsed.formats.join('/')}`);
    }
    if (parsed.requiredMaterials.length > 0) {
      parts.push(`必备材料 ${parsed.requiredMaterials.join('/')}`);
    }
    if (parsed.namingRule !== null && parsed.namingRule !== undefined
      && parsed.namingRule.length > 0) {
      parts.push(`命名 ${parsed.namingRule}`);
    }
    if (parsed.lengthRequirement !== null && parsed.lengthRequirement !== undefined
      && parsed.lengthRequirement.length > 0) {
      parts.push(`篇幅 ${parsed.lengthRequirement}`);
    }
    if (parsed.deadline !== null && parsed.deadline !== undefined
      && parsed.deadline.length > 0) {
      parts.push(`截止 ${parsed.deadline}`);
    }
    if (parts.length === 0) {
      return '服务端未能从这段文字中解析出任何具体要求，因此只执行了通用检查。';
    }
    return parts.join('；');
  }
}
