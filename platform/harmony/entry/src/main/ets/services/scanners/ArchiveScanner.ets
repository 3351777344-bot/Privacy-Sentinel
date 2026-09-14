/**
 * L1 — archive scanner.
 *
 * Order of operations is the security property here:
 *
 *   1. Parse the central directory and decide *structurally* whether the
 *      archive is safe to touch (bomb ratio, declared totals, traversal paths,
 *      symlinks, encryption).
 *   2. Only then decompress selected small entries through the capped in-memory
 *      inflater.
 *   3. Recurse into nested containers with a hard depth limit.
 *
 * Steps 1 and 2 are separated precisely so a bomb is identified by its declared
 * metadata rather than discovered by exhausting memory.
 */

import { ThreatFinding } from '../../models/ThreatModels';
import { inflateRaw } from './Inflate';
import {
  ZipDirectory,
  ZipEntry,
  ZIP_METHOD_DEFLATE,
  ZIP_METHOD_STORED,
  readEntryCompressedData,
  readZipDirectory
} from './ZipReader';
import { decodeTextPayload, looksLikeText } from './TextExtract';

const SOURCE: string = 'ArchiveScanner';

export interface ArchiveScanOptions {
  maxDepth: number;
  maxEntries: number;
  /** Declared uncompressed bytes across the archive. */
  maxTotalUncompressed: number;
  /** Declared uncompressed bytes for a single entry. */
  maxSingleUncompressed: number;
  /** Compression ratio above which an entry is treated as a bomb. */
  maxRatio: number;
  /** Total decoded bytes fed to content scanners. */
  maxContentBytes: number;
  /** Largest single entry that will be decoded for content scanning. */
  maxContentEntryBytes: number;
  /** How many entries get content-scanned. */
  maxContentEntries: number;
}

export const DEFAULT_ARCHIVE_OPTIONS: ArchiveScanOptions = {
  maxDepth: 3,
  maxEntries: 10000,
  maxTotalUncompressed: 512 * 1024 * 1024,
  maxSingleUncompressed: 256 * 1024 * 1024,
  maxRatio: 120,
  maxContentBytes: 8 * 1024 * 1024,
  maxContentEntryBytes: 2 * 1024 * 1024,
  maxContentEntries: 200
};

export interface ExtractedEntry {
  name: string;
  data: Uint8Array;
}

export interface ArchiveScanResult {
  isArchive: boolean;
  directory: ZipDirectory | undefined;
  findings: ThreatFinding[];
  /** vbaProject.bin style payloads handed to the macro scanner. */
  vbaPayloads: Uint8Array[];
  /** Decoded text from all entries, concatenated for downstream scanners. */
  extractedText: string;
  extractedTextTruncated: boolean;
  /** Inner PE payloads found inside the archive, for PE analysis. */
  innerExecutables: ExtractedEntry[];
  /** Nested archives that were recursed into. */
  nestedDepthReached: number;
  decompressedBytes: number;
}

const SENSITIVE_TARGET_FRAGMENTS: string[] = [
  'appdata/roaming/microsoft/windows/start menu/programs/startup',
  'startup/',
  'authorized_keys',
  '.ssh/',
  '.bashrc',
  '.profile',
  'etc/passwd',
  'etc/shadow',
  'etc/cron',
  'crontab',
  'system32/',
  'windows/win.ini',
  'library/launchagents',
  'lib/systemd/system',
  'etc/sudoers',
  'web.config',
  '.gitconfig',
  'hosts'
];

function emptyResult(): ArchiveScanResult {
  return {
    isArchive: false,
    directory: undefined,
    findings: [],
    vbaPayloads: [],
    extractedText: '',
    extractedTextTruncated: false,
    innerExecutables: [],
    nestedDepthReached: 0,
    decompressedBytes: 0
  };
}

/** True when the entry path escapes the extraction root or targets a system location. */
export function isTraversalPath(rawName: string): boolean {
  const name: string = rawName.replace(/\\/g, '/');
  if (name.length === 0) {
    return false;
  }
  if (name.startsWith('/')) {
    return true;
  }
  if (name.startsWith('//')) {
    return true;
  }
  if (/^[A-Za-z]:/.test(name)) {
    return true;
  }
  // A device path such as \\?\C:\... is never legitimate inside an archive.
  if (/^\\\\[.?]/.test(rawName)) {
    return true;
  }

  const parts: string[] = name.split('/');
  let depth: number = 0;
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    if (part === '..') {
      depth--;
      if (depth < 0) {
        return true;
      }
    } else if (part !== '.' && part.length > 0) {
      depth++;
    }
  }
  return false;
}

function targetsSensitiveLocation(rawName: string): boolean {
  const lower: string = rawName.replace(/\\/g, '/').toLowerCase();
  for (let i = 0; i < SENSITIVE_TARGET_FRAGMENTS.length; i++) {
    if (lower.indexOf(SENSITIVE_TARGET_FRAGMENTS[i]) >= 0) {
      return true;
    }
  }
  return false;
}

/** Deepest `../` escape distance in a path, 0 when contained. */
export function traversalDepth(rawName: string): number {
  const parts: string[] = rawName.replace(/\\/g, '/').split('/');
  let depth: number = 0;
  let minimum: number = 0;
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    if (part === '..') {
      depth--;
      if (depth < minimum) {
        minimum = depth;
      }
    } else if (part !== '.' && part.length > 0) {
      depth++;
    }
  }
  return minimum < 0 ? -minimum : 0;
}

function makeFinding(id: string, category: 'archive-bomb' | 'archive-slip' |
  'archive-nesting' | 'archive-encrypted', label: string, detail: string,
  level: 'high' | 'medium' | 'low' | 'info', evidence: string): ThreatFinding {
  return {
    id: id,
    category: category,
    label: label,
    detail: detail,
    level: level,
    source: SOURCE,
    evidence: evidence
  };
}

function formatBytes(value: number): string {
  if (value >= 1024 * 1024 * 1024) {
    return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }
  if (value >= 1024 * 1024) {
    return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  }
  if (value >= 1024) {
    return `${(value / 1024).toFixed(1)} KB`;
  }
  return `${value} B`;
}

/** Structural assessment — never decompresses anything. */
function assessStructure(directory: ZipDirectory,
  options: ArchiveScanOptions): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  const entries: ZipEntry[] = directory.entries;

  if (directory.entryLimitHit || entries.length > options.maxEntries) {
    findings.push(makeFinding(
      'archive.entry-flood',
      'archive-bomb',
      '条目数量异常',
      `压缩包包含 ${entries.length} 个条目，超过 ${options.maxEntries} 的合理上限。` +
        '海量小文件常用于拖慢或压垮扫描器。',
      'medium',
      `条目数 ${entries.length}`
    ));
  }

  if (directory.declaredTotal > options.maxTotalUncompressed) {
    findings.push(makeFinding(
      'archive.bomb-total',
      'archive-bomb',
      '解压后总体积超限（压缩炸弹）',
      `全部条目声明解压后共 ${formatBytes(directory.declaredTotal)}，` +
        `而压缩包本身仅 ${formatBytes(directory.compressedTotal)}。`,
      'high',
      `${formatBytes(directory.compressedTotal)} -> ${formatBytes(directory.declaredTotal)}`
    ));
  }

  const encryptedNames: string[] = [];
  const symlinkNames: string[] = [];
  const traversalNames: string[] = [];
  const absoluteNames: string[] = [];
  const sensitiveNames: string[] = [];
  const oversizeNames: string[] = [];
  const bombNames: string[] = [];

  for (let i = 0; i < entries.length; i++) {
    const entry: ZipEntry = entries[i];

    if (entry.encrypted) {
      if (encryptedNames.length < 4) {
        encryptedNames.push(entry.name);
      }
      continue;
    }

    if (entry.symlink) {
      if (symlinkNames.length < 4) {
        symlinkNames.push(entry.name);
      }
    }

    if (entry.name.startsWith('/') || /^[A-Za-z]:/.test(entry.name)) {
      if (absoluteNames.length < 4) {
        absoluteNames.push(entry.name);
      }
    }

    if (isTraversalPath(entry.name)) {
      if (traversalNames.length < 4) {
        traversalNames.push(entry.name);
      }
    } else if (targetsSensitiveLocation(entry.name)) {
      if (sensitiveNames.length < 4) {
        sensitiveNames.push(entry.name);
      }
    }

    if (entry.uncompressedSize > options.maxSingleUncompressed) {
      if (oversizeNames.length < 4) {
        oversizeNames.push(`${entry.name} (${formatBytes(entry.uncompressedSize)})`);
      }
    } else if (entry.ratio > options.maxRatio && entry.uncompressedSize > 1024 * 1024 &&
      entry.compressedSize > 0) {
      if (bombNames.length < 4) {
        bombNames.push(`${entry.name} (压缩比 ${Math.round(entry.ratio)}:1)`);
      }
    }
  }

  if (bombNames.length > 0) {
    findings.push(makeFinding(
      'archive.bomb-ratio',
      'archive-bomb',
      '单个条目压缩比异常（压缩炸弹）',
      `以下条目解压后会膨胀上百倍，是典型的压缩炸弹构造。`,
      'high',
      bombNames.join(', ')
    ));
  }
  if (oversizeNames.length > 0) {
    findings.push(makeFinding(
      'archive.bomb-single',
      'archive-bomb',
      '单个条目解压体积超限',
      '存在声明解压后体积过大的条目，解压即可能耗尽存储。',
      'high',
      oversizeNames.join(', ')
    ));
  }

  if (traversalNames.length > 0) {
    findings.push(makeFinding(
      'archive.zip-slip',
      'archive-slip',
      '路径穿越条目（Zip Slip）',
      '条目路径通过 ../ 逃出解压目录，可覆盖应用数据甚至系统文件。',
      'high',
      traversalNames.join(', ')
    ));
  }
  if (absoluteNames.length > 0) {
    findings.push(makeFinding(
      'archive.absolute-path',
      'archive-slip',
      '绝对路径条目',
      '条目使用绝对路径或盘符，解压时会写到目标目录之外。',
      'high',
      absoluteNames.join(', ')
    ));
  }
  if (symlinkNames.length > 0) {
    findings.push(makeFinding(
      'archive.symlink',
      'archive-slip',
      '包含符号链接条目',
      '符号链接可指向解压目录之外，二次解压时会写到意外位置。',
      'high',
      symlinkNames.join(', ')
    ));
  }
  if (sensitiveNames.length > 0) {
    findings.push(makeFinding(
      'archive.sensitive-target',
      'archive-slip',
      '指向敏感系统位置',
      '条目试图写入开机启动目录、SSH 授权文件或系统配置。',
      'high',
      sensitiveNames.join(', ')
    ));
  }

  if (encryptedNames.length > 0) {
    findings.push(makeFinding(
      'archive.encrypted',
      'archive-encrypted',
      '包含加密条目，内容无法检查',
      '加密压缩包常用于绕过检测投递载荷；在提供口令前，本工具无法确认其内容。',
      'medium',
      encryptedNames.join(', ')
    ));
  }

  return findings;
}

function isTextualEntryName(name: string): boolean {
  const lower: string = name.toLowerCase();
  const textExtensions: string[] = [
    '.txt', '.md', '.csv', '.tsv', '.log', '.json', '.xml', '.yaml', '.yml',
    '.ini', '.cfg', '.conf', '.env', '.properties', '.sql', '.pem', '.key',
    '.ps1', '.bat', '.cmd', '.sh', '.bash', '.vbs', '.vbe', '.js', '.jse',
    '.wsf', '.wsh', '.hta', '.py', '.pl', '.rb', '.php', '.html', '.htm',
    '.css', '.java', '.c', '.cpp', '.h', '.hpp', '.go', '.rs', '.kt', '.ets',
    '.ts', '.jsx', '.tsx', '.gradle', '.config', '.htaccess', '.gitconfig'
  ];
  for (let i = 0; i < textExtensions.length; i++) {
    if (lower.endsWith(textExtensions[i])) {
      return true;
    }
  }
  return false;
}

/** Decode a compressed entry into memory, honouring the caps. */
function decodeEntry(data: Uint8Array, entry: ZipEntry,
  maxBytes: number): Uint8Array | undefined {
  if (entry.encrypted) {
    return undefined;
  }
  if (entry.uncompressedSize > maxBytes) {
    return undefined;
  }
  if (entry.method === ZIP_METHOD_STORED) {
    const raw: Uint8Array = readEntryCompressedData(data, entry);
    return raw.length > maxBytes ? raw.subarray(0, maxBytes) : raw;
  }
  if (entry.method === ZIP_METHOD_DEFLATE) {
    const raw: Uint8Array = readEntryCompressedData(data, entry);
    if (raw.length === 0) {
      return undefined;
    }
    const result = inflateRaw(raw, maxBytes, entry.uncompressedSize);
    if (!result.ok && result.data.length === 0) {
      return undefined;
    }
    return result.data;
  }
  // Deflate64 / bzip2 / LZMA / AES are not decoded in the L1 layer.
  return undefined;
}

/**
 * Scan a ZIP container: structure first, then bounded content extraction.
 *
 * `onInnerExecutable` lets the orchestrator run PE analysis on payloads found
 * inside the archive without this module depending on the PE analyser.
 */
export function scanArchive(fileName: string, data: Uint8Array,
  options: ArchiveScanOptions = DEFAULT_ARCHIVE_OPTIONS,
  depth: number = 0): ArchiveScanResult {
  const directory: ZipDirectory = readZipDirectory(data);
  if (!directory.ok) {
    const result: ArchiveScanResult = emptyResult();
    result.isArchive = false;
    if (directory.error.length > 0 && depth === 0) {
      result.findings.push(makeFinding(
        'archive.unreadable',
        'archive-nesting',
        '压缩包结构无法解析',
        `文件以 ZIP 头开始，但中央目录无法解析：${directory.error}。` +
          '可能已损坏，也可能是刻意破坏以规避扫描。',
        'medium',
        directory.error
      ));
    }
    return result;
  }

  const result: ArchiveScanResult = emptyResult();
  result.isArchive = true;
  result.directory = directory;
  result.nestedDepthReached = depth;
  result.findings.push(...assessStructure(directory, options));

  if (depth >= options.maxDepth) {
    result.findings.push(makeFinding(
      'archive.nesting-depth',
      'archive-nesting',
      '嵌套层级超过上限',
      `压缩包嵌套已达 ${depth} 层，停止继续解包。深层嵌套常被用于逃避扫描。`,
      'medium',
      `深度 ${depth}`
    ));
    return result;
  }

  const structured: ThreatFinding[] = [];

  let contentBudget: number = options.maxContentBytes;
  let scannedEntries: number = 0;
  const textParts: string[] = [];

  for (let i = 0; i < directory.entries.length; i++) {
    const entry: ZipEntry = directory.entries[i];
    if (entry.directory || entry.encrypted) {
      continue;
    }
    if (scannedEntries >= options.maxContentEntries || contentBudget <= 0) {
      result.extractedTextTruncated = true;
      break;
    }

    const perEntryCap: number = Math.min(options.maxContentEntryBytes, contentBudget);
    const decoded: Uint8Array | undefined = decodeEntry(data, entry, perEntryCap);
    if (decoded === undefined || decoded.length === 0) {
      continue;
    }

    scannedEntries++;
    contentBudget -= decoded.length;
    result.decompressedBytes += decoded.length;

    const lowerName: string = entry.name.toLowerCase();

    // ------------------------------------------------ macro project payload
    if (lowerName.endsWith('vbaproject.bin') || lowerName.endsWith('vba_data.xml')) {
      result.vbaPayloads.push(decoded);
    }

    // ------------------------------------------------- nested archive
    if (looksLikeZipMagic(decoded)) {
      result.findings.push(makeFinding(
        'archive.nested-container',
        'archive-nesting',
        '压缩包内嵌套压缩包',
        `条目 ${entry.name} 本身是压缩包，已递归检查（深度 ${depth + 1}）。`,
        'low',
        entry.name
      ));
      const nested: ArchiveScanResult = scanArchive(
        entry.name, decoded, options, depth + 1
      );
      if (nested.isArchive) {
        result.findings.push(...nested.findings);
        for (let v = 0; v < nested.vbaPayloads.length; v++) {
          result.vbaPayloads.push(nested.vbaPayloads[v]);
        }
        for (let e = 0; e < nested.innerExecutables.length; e++) {
          result.innerExecutables.push(nested.innerExecutables[e]);
        }
        if (nested.extractedText.length > 0) {
          textParts.push(nested.extractedText);
        }
        if (nested.nestedDepthReached > result.nestedDepthReached) {
          result.nestedDepthReached = nested.nestedDepthReached;
        }
        continue;
      }
      continue;
    }

    // ------------------------------------------------- inner executable
    if (decoded.length > 2 && decoded[0] === 0x4D && decoded[1] === 0x5A) {
      result.innerExecutables.push({ name: entry.name, data: decoded });
      structured.push({
        id: 'archive.inner-executable',
        category: 'pe-structure',
        label: '压缩包内藏可执行程序',
        detail: `条目 ${entry.name} 是 Windows 可执行文件，解压后双击即运行。`,
        level: 'high',
        source: SOURCE,
        evidence: entry.name
      });
      continue;
    }

    // -------------------------------------------------- other binaries
    if (decoded.length > 8 && decoded[0] === 0x7F && decoded[1] === 0x45) {
      structured.push({
        id: 'archive.inner-elf',
        category: 'pe-structure',
        label: '压缩包内藏 ELF 可执行文件',
        detail: `条目 ${entry.name} 是 Linux / 鸿蒙原生可执行文件。`,
        level: 'high',
        source: SOURCE,
        evidence: entry.name
      });
      continue;
    }

    // --------------------------------------------------------- text body
    if (isTextualEntryName(entry.name) || looksLikeText(decoded)) {
      const text: string = decodeTextPayload(decoded);
      if (text.length > 0) {
        textParts.push(`\n### ${entry.name}\n${text}`);
      }
    }
  }

  result.findings.push(...structured);
  result.extractedText = textParts.join('');
  return result;
}

function looksLikeZipMagic(data: Uint8Array): boolean {
  if (data.length < 4) {
    return false;
  }
  return data[0] === 0x50 && data[1] === 0x4B &&
    (data[2] === 0x03 || data[2] === 0x05 || data[2] === 0x07);
}
