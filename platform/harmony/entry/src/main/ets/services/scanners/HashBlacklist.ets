/**
 * L1 — known-bad hash blacklist (pure logic).
 *
 * Storage-agnostic on purpose: `SignatureDB` persists this through HarmonyOS
 * KV-Store, while tests exercise the same class in memory. Entries are keyed by
 * SHA-256 and carry enough metadata to explain a hit to the user.
 */

export interface BlacklistEntry {
  sha256: string;
  /** Malware family or verdict label. */
  family: string;
  /** ISO date the sample was first seen, `''` when unknown. */
  firstSeen: string;
  /** Feed the entry came from. */
  source: string;
  /** Optional note shown verbatim in the report. */
  note?: string;
}

/**
 * Seed entries.
 *
 * Only publicly documented, non-malicious test vectors live here — a real
 * production list is delivered by the signed feed and merged at runtime, so
 * shipping invented hashes would be both useless and misleading.
 */
const SEED_ENTRIES: BlacklistEntry[] = [
  {
    sha256: '275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f',
    family: 'EICAR 测试文件',
    firstSeen: '1991-01-01',
    source: 'builtin',
    note: '行业标准反病毒测试样本，本身无害，用于验证检测链路。'
  }
];

export interface BlacklistMatch {
  entry: BlacklistEntry;
  sha256: string;
}

export class HashBlacklist {
  private index: Map<string, BlacklistEntry> = new Map<string, BlacklistEntry>();

  add(entry: BlacklistEntry): void {
    const key: string = normalizeHash(entry.sha256);
    if (key.length !== 64) {
      return;
    }
    this.index.set(key, entry);
  }

  addRaw(sha256: string, source: string): void {
    this.add({
      sha256: sha256,
      family: '已知恶意样本',
      firstSeen: '',
      source: source
    });
  }

  has(sha256: string): boolean {
    return this.index.has(normalizeHash(sha256));
  }

  lookup(sha256: string): BlacklistMatch | undefined {
    const key: string = normalizeHash(sha256);
    const entry: BlacklistEntry | undefined = this.index.get(key);
    if (entry === undefined) {
      return undefined;
    }
    return { entry: entry, sha256: key };
  }

  get size(): number {
    return this.index.size;
  }

  /** Merge a feed. Returns how many entries were added or replaced. */
  loadCsv(text: string, defaultSource: string): number {
    let added: number = 0;
    const lines: string[] = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      const fields: string[] = line.split(',');
      const hash: string = normalizeHash(fields[0]);
      if (hash.length !== 64) {
        continue;
      }
      const family: string = fields.length > 1 && fields[1].trim().length > 0
        ? fields[1].trim() : '已知恶意样本';
      const firstSeen: string = fields.length > 2 ? fields[2].trim() : '';
      const source: string = fields.length > 3 && fields[3].trim().length > 0
        ? fields[3].trim() : defaultSource;
      this.index.set(hash, {
        sha256: hash,
        family: family,
        firstSeen: firstSeen,
        source: source
      });
      added++;
    }
    return added;
  }

  exportCsv(): string {
    const lines: string[] = ['# sha256,family,firstSeen,source'];
    this.index.forEach((entry: BlacklistEntry) => {
      lines.push(`${entry.sha256},${entry.family},${entry.firstSeen},${entry.source}`);
    });
    return lines.join('\n');
  }

  /** Snapshot of every entry, used to render a feed-status line in the UI. */
  all(): BlacklistEntry[] {
    const out: BlacklistEntry[] = [];
    this.index.forEach((entry: BlacklistEntry) => {
      out.push(entry);
    });
    return out;
  }

  clear(): void {
    this.index.clear();
  }

  /** Blacklist preloaded with the bundled seed vectors. */
  static createWithSeed(): HashBlacklist {
    const blacklist: HashBlacklist = new HashBlacklist();
    for (let i = 0; i < SEED_ENTRIES.length; i++) {
      blacklist.add(SEED_ENTRIES[i]);
    }
    return blacklist;
  }

  static seedEntries(): BlacklistEntry[] {
    return SEED_ENTRIES;
  }
}

export function normalizeHash(value: string): string {
  if (value === undefined || value === null) {
    return '';
  }
  const trimmed: string = value.trim().toLowerCase();
  if (trimmed.length !== 64) {
    return '';
  }
  for (let i = 0; i < trimmed.length; i++) {
    const code: number = trimmed.charCodeAt(i);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isHexLower: boolean = code >= 97 && code <= 102;
    if (!isDigit && !isHexLower) {
      return '';
    }
  }
  return trimmed;
}
