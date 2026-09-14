/**
 * L1 — signature database persistence.
 *
 * Wraps the pure `HashBlacklist` with HarmonyOS KV-Store so a signed hash feed
 * survives restarts. The scan path is synchronous, so the database is loaded
 * once into a process-wide cache and `current()` hands that cache straight to
 * `ThreatScanner` without awaiting storage on every file.
 *
 * Only SHA-256 values and their family labels are stored — never file content.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { HashBlacklist } from './scanners/HashBlacklist';

const STORE_NAME: string = 'guardianhub_threat_signatures';
const FEED_KEY: string = 'hash_feed_csv';
const META_KEY: string = 'hash_feed_meta';
/** Hard cap on accepted feed text so a corrupt payload cannot exhaust memory. */
const MAX_FEED_CHARS: number = 2 * 1024 * 1024;

export interface SignatureFeedMeta {
  /** Feed version string, `builtin` when only seed vectors are loaded. */
  version: string;
  /** Epoch ms of the last successful install, 0 for the bundled seed. */
  updatedAt: number;
  /** Number of hashes currently indexed, seed vectors included. */
  entryCount: number;
}

function builtinMeta(entryCount: number): SignatureFeedMeta {
  return {
    version: 'builtin',
    updatedAt: 0,
    entryCount: entryCount
  };
}

export class SignatureDB {
  private static cached: HashBlacklist | undefined = undefined;
  private static cachedMeta: SignatureFeedMeta = builtinMeta(0);

  /**
   * Load the blacklist from KV-Store into the process cache.
   * Safe to call on every scan — subsequent calls return the cache.
   */
  static async ensureLoaded(context: common.Context): Promise<HashBlacklist> {
    if (SignatureDB.cached !== undefined) {
      return SignatureDB.cached;
    }
    const blacklist: HashBlacklist = HashBlacklist.createWithSeed();
    let meta: SignatureFeedMeta = builtinMeta(blacklist.size);
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const rawCsv = await store.get(FEED_KEY, '');
      const csv: string = rawCsv as string;
      if (csv.length > 0) {
        blacklist.loadCsv(csv, 'feed');
      }
      const rawMeta = await store.get(META_KEY, '');
      const metaText: string = rawMeta as string;
      if (metaText.length > 0) {
        meta = JSON.parse(metaText) as SignatureFeedMeta;
        meta.entryCount = blacklist.size;
      } else {
        meta = builtinMeta(blacklist.size);
      }
    } catch (_) {
      meta = builtinMeta(blacklist.size);
    }
    SignatureDB.cached = blacklist;
    SignatureDB.cachedMeta = meta;
    return blacklist;
  }

  /**
   * Synchronous view for the scan path. Falls back to the bundled seed so a
   * scan never fails just because storage was not opened yet.
   */
  static current(): HashBlacklist {
    return SignatureDB.cached !== undefined ? SignatureDB.cached : HashBlacklist.createWithSeed();
  }

  static meta(): SignatureFeedMeta {
    return SignatureDB.cachedMeta;
  }

  /** Human-readable feed status, e.g. `内置种子（1 条）`. */
  static metaLabel(): string {
    const meta: SignatureFeedMeta = SignatureDB.cachedMeta;
    if (meta.version === 'builtin' || meta.updatedAt === 0) {
      return `内置种子（${meta.entryCount} 条）`;
    }
    return `${meta.version}（${meta.entryCount} 条）`;
  }

  /**
   * Install a new feed (CSV: `sha256,family,firstSeen,source`).
   * Replaces the previous feed rather than merging, so a recalled sample can be
   * removed by publishing a feed without it.
   */
  static async installFeed(context: common.Context, csv: string,
    version: string): Promise<SignatureFeedMeta> {
    const scoped: string = csv.length > MAX_FEED_CHARS ? csv.substring(0, MAX_FEED_CHARS) : csv;
    const blacklist: HashBlacklist = HashBlacklist.createWithSeed();
    blacklist.loadCsv(scoped, 'feed');
    const meta: SignatureFeedMeta = {
      version: version.length > 0 ? version : 'feed',
      updatedAt: Date.now(),
      entryCount: blacklist.size
    };
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(FEED_KEY, scoped);
      await store.put(META_KEY, JSON.stringify(meta));
      await store.flush();
    } catch (_) {
      // Persistence failure still leaves the in-memory feed usable this session.
    }
    SignatureDB.cached = blacklist;
    SignatureDB.cachedMeta = meta;
    return meta;
  }

  /** Drop the downloaded feed and fall back to the bundled seed vectors. */
  static async clearFeed(context: common.Context): Promise<void> {
    const blacklist: HashBlacklist = HashBlacklist.createWithSeed();
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.delete(FEED_KEY);
      await store.delete(META_KEY);
      await store.flush();
    } catch (_) {
    }
    SignatureDB.cached = blacklist;
    SignatureDB.cachedMeta = builtinMeta(blacklist.size);
  }

  /** Release the process cache, e.g. from `onDestroy`. */
  static release(): void {
    SignatureDB.cached = undefined;
    SignatureDB.cachedMeta = builtinMeta(0);
  }
}
