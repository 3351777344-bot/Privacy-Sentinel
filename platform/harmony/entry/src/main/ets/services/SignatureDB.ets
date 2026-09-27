import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { HashBlacklist } from './scanners/HashBlacklist';
import { SignedFeedVerifier } from './SignedFeedVerifier';

const STORE_NAME: string = 'guardianhub_threat_signatures';
const BUNDLE_KEY: string = 'signed_bundle_v1';
const PREVIOUS_KEY: string = 'previous_signed_bundle_v1';

interface SignedBundle {
  csv: string;
  version: string;
  expiresAt: number;
  signature: string;
}

export interface SignatureFeedMeta {
  version: string;
  updatedAt: number;
  entryCount: number;
}

export class SignatureDB {
  private static cached: HashBlacklist | undefined = undefined;
  private static cachedMeta: SignatureFeedMeta = { version: 'builtin', updatedAt: 0, entryCount: 1 };
  private static expiresAt: number = 0;

  static async ensureLoaded(context: common.Context): Promise<HashBlacklist> {
    if (SignatureDB.cached !== undefined) { return SignatureDB.current(); }
    let blacklist = HashBlacklist.createWithSeed();
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(BUNDLE_KEY, '') as string;
      if (raw.length > 0) {
        const bundle = JSON.parse(raw) as SignedBundle;
        await SignedFeedVerifier.verify(bundle.csv, bundle.version, bundle.expiresAt, bundle.signature);
        blacklist.loadCsv(bundle.csv, 'signed-feed');
        SignatureDB.expiresAt = bundle.expiresAt;
        SignatureDB.cachedMeta = { version: bundle.version, updatedAt: Date.now(), entryCount: blacklist.size };
      }
    } catch (_) {
      blacklist = HashBlacklist.createWithSeed();
    }
    SignatureDB.cached = blacklist;
    return blacklist;
  }

  static current(): HashBlacklist {
    if (SignatureDB.expiresAt > 0 && SignatureDB.expiresAt <= Date.now()) {
      SignatureDB.cached = HashBlacklist.createWithSeed();
      SignatureDB.cachedMeta = { version: 'expired', updatedAt: 0, entryCount: SignatureDB.cached.size };
    }
    return SignatureDB.cached !== undefined ? SignatureDB.cached : HashBlacklist.createWithSeed();
  }

  static meta(): SignatureFeedMeta { return SignatureDB.cachedMeta; }

  static metaLabel(): string {
    SignatureDB.current();
    const meta = SignatureDB.cachedMeta;
    return meta.updatedAt === 0 ? '内置测试规则（非生产情报；未配置或已过期）' :
      `签名情报 ${meta.version}（${meta.entryCount} 条）`;
  }

  static async installFeed(context: common.Context, csv: string, version: string,
    expiresAt: number = 0, signature: string = ''): Promise<SignatureFeedMeta> {
    await SignatureDB.ensureLoaded(context);
    await SignedFeedVerifier.verify(csv, version, expiresAt, signature);
    const store = await preferences.getPreferences(context, STORE_NAME);
    const previous = await store.get(BUNDLE_KEY, '') as string;
    if (previous.length > 0) {
      const old = JSON.parse(previous) as SignedBundle;
      if (Number(version) <= Number(old.version)) { throw new Error('拒绝情报库版本回退或重放。'); }
    }
    const bundle: SignedBundle = { csv: csv, version: version, expiresAt: expiresAt, signature: signature };
    const blacklist = HashBlacklist.createWithSeed();
    blacklist.loadCsv(csv, 'signed-feed');
    // The active feed is one KV value: metadata and contents cannot tear apart.
    if (previous.length > 0) { await store.put(PREVIOUS_KEY, previous); }
    await store.put(BUNDLE_KEY, JSON.stringify(bundle));
    await store.flush();
    SignatureDB.cached = blacklist;
    SignatureDB.expiresAt = expiresAt;
    SignatureDB.cachedMeta = { version: version, updatedAt: Date.now(), entryCount: blacklist.size };
    return SignatureDB.cachedMeta;
  }

  static async rollback(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(PREVIOUS_KEY, '') as string;
    const bundle = JSON.parse(raw) as SignedBundle;
    await SignedFeedVerifier.verify(bundle.csv, bundle.version, bundle.expiresAt, bundle.signature);
    await store.put(BUNDLE_KEY, raw);
    await store.flush();
    SignatureDB.release();
    await SignatureDB.ensureLoaded(context);
  }

  static async clearFeed(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.delete(BUNDLE_KEY);
    await store.delete(PREVIOUS_KEY);
    await store.flush();
    SignatureDB.release();
  }

  static release(): void {
    SignatureDB.cached = undefined;
    SignatureDB.expiresAt = 0;
    SignatureDB.cachedMeta = { version: 'builtin', updatedAt: 0, entryCount: 1 };
  }
}
