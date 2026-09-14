/**
 * Doc Shield — L1 orchestration.
 *
 * Runs every on-device scanner over one file and folds the results into a
 * single verdict. The pipeline is intentionally ordered cheapest-first:
 *
 *   type verification  ->  hash reputation  ->  container-specific structure
 *   ->  decoded content (credentials, scripts, indicators)  ->  entropy
 *
 * Everything here is synchronous and in-memory. No network call, no temporary
 * file, no subprocess — the scanned bytes never leave the device.
 */

import { ThreatFinding, ThreatLevel, ThreatScanReport, ThreatVerdict } from '../models/ThreatModels';
import {
  ArchiveScanOptions,
  ArchiveScanResult,
  DEFAULT_ARCHIVE_OPTIONS,
  scanArchive
} from './scanners/ArchiveScanner';
import { shannonEntropy } from './scanners/EntropyScan';
import { HashBlacklist, normalizeHash } from './scanners/HashBlacklist';
import { assessIocs, extractIocs, indicatorList } from './scanners/IocExtractor';
import { scanMacros } from './scanners/MacroScanner';
import { PeAnalysis, analyzePe, peFindings } from './scanners/PEAnalyzer';
import { analyzePdf } from './scanners/PdfAnalyzer';
import { scanSensitiveText } from './scanners/RegexScanner';
import { looksLikeScript, scanScriptText } from './scanners/ScriptScanner';
import { sha256Hex } from './scanners/Sha256';
import {
  decodeTextPayload,
  extractAllStrings,
  looksLikeText,
  stringsToCorpus
} from './scanners/TextExtract';
import { TypeDetectResult, TypeDetector } from './scanners/TypeDetector';

const LEVEL_WEIGHT: Map<ThreatLevel, number> = new Map<ThreatLevel, number>([
  ['high', 26],
  ['medium', 10],
  ['low', 3],
  ['info', 0]
]);

const LEVEL_RANK: Map<ThreatLevel, number> = new Map<ThreatLevel, number>([
  ['high', 3],
  ['medium', 2],
  ['low', 1],
  ['info', 0]
]);

/** Categories that alone justify a `malicious` verdict. */
const DECISIVE_CATEGORIES: string[] = [
  'signature-match'
];

/** Findings that indicate active hostile capability when seen at high level. */
const HOSTILE_FINDING_IDS: string[] = [
  'pe.behavior.injection',
  'pe.behavior.reverse-shell',
  'pe.behavior.dropper',
  'pe.behavior.credential-access',
  'pe.behavior.keylogger',
  'script.reverse-shell',
  'script.download-exec-combo',
  'script.encoded-command',
  'script.disable-defender',
  'script.amsi-bypass',
  'script.persistence-run-key',
  'macro.auto-exec-trigger',
  'macro.host-abuse-api',
  'macro.execution-command',
  'archive.zip-slip',
  'archive.sensitive-target',
  'archive.bomb-ratio',
  'archive.bomb-total',
  'archive.inner-executable',
  'pe.disguised',
  'pe.malformed',
  'type.spoof-executable'
];

export interface ThreatScannerOptions {
  blacklist: HashBlacklist;
  archive: ArchiveScanOptions;
  /** Run text scanners over printable strings extracted from binaries. */
  scanBinaryStrings: boolean;
  /** Cap on characters handed to the text scanners. */
  maxTextScanChars: number;
  /** Cap on strings extracted from a binary. */
  maxExtractedStrings: number;
}

/**
 * Caller-facing options: every field optional, merged over the defaults.
 * Partial objects are accepted because most call sites only want to supply a
 * signature database and should not have to restate scan limits.
 */
export interface ThreatScannerOverrides {
  blacklist?: HashBlacklist;
  archive?: ArchiveScanOptions;
  scanBinaryStrings?: boolean;
  maxTextScanChars?: number;
  maxExtractedStrings?: number;
}

function defaultOptions(): ThreatScannerOptions {
  return {
    blacklist: HashBlacklist.createWithSeed(),
    archive: DEFAULT_ARCHIVE_OPTIONS,
    scanBinaryStrings: true,
    maxTextScanChars: 2 * 1024 * 1024,
    maxExtractedStrings: 4000
  };
}

function mergeOptions(overrides?: ThreatScannerOverrides): ThreatScannerOptions {
  const base: ThreatScannerOptions = defaultOptions();
  if (overrides === undefined) {
    return base;
  }
  if (overrides.blacklist !== undefined) {
    base.blacklist = overrides.blacklist;
  }
  if (overrides.archive !== undefined) {
    base.archive = overrides.archive;
  }
  if (overrides.scanBinaryStrings !== undefined) {
    base.scanBinaryStrings = overrides.scanBinaryStrings;
  }
  if (overrides.maxTextScanChars !== undefined) {
    base.maxTextScanChars = overrides.maxTextScanChars;
  }
  if (overrides.maxExtractedStrings !== undefined) {
    base.maxExtractedStrings = overrides.maxExtractedStrings;
  }
  return base;
}

/** Collapse duplicate finding ids, keeping the most severe instance. */
function dedupe(findings: ThreatFinding[]): ThreatFinding[] {
  const order: string[] = [];
  const byId: Map<string, ThreatFinding> = new Map<string, ThreatFinding>();
  for (let i = 0; i < findings.length; i++) {
    const finding: ThreatFinding = findings[i];
    const existing: ThreatFinding | undefined = byId.get(finding.id);
    if (existing === undefined) {
      order.push(finding.id);
      byId.set(finding.id, finding);
      continue;
    }
    const existingRank: number = LEVEL_RANK.get(existing.level) ?? 0;
    const candidateRank: number = LEVEL_RANK.get(finding.level) ?? 0;
    if (candidateRank > existingRank) {
      byId.set(finding.id, finding);
    } else if (candidateRank === existingRank && existing.evidence !== undefined &&
      finding.evidence !== undefined && existing.evidence.indexOf(finding.evidence) < 0) {
      // Same severity, extra context worth keeping — merge the evidence text.
      byId.set(finding.id, {
        id: existing.id,
        category: existing.category,
        label: existing.label,
        detail: existing.detail,
        level: existing.level,
        source: existing.source,
        evidence: `${existing.evidence}; ${finding.evidence}`
      });
    }
  }
  const out: ThreatFinding[] = [];
  for (let i = 0; i < order.length; i++) {
    const finding: ThreatFinding | undefined = byId.get(order[i]);
    if (finding !== undefined) {
      out.push(finding);
    }
  }
  return out;
}

function computeScore(findings: ThreatFinding[]): number {
  let deduction: number = 0;
  for (let i = 0; i < findings.length; i++) {
    const weight: number = LEVEL_WEIGHT.get(findings[i].level) ?? 0;
    deduction += weight;
  }
  const score: number = 100 - deduction;
  return score < 0 ? 0 : score;
}

function computeVerdict(findings: ThreatFinding[], scanned: boolean): ThreatVerdict {
  if (!scanned) {
    return 'unknown';
  }
  let highCount: number = 0;
  let mediumCount: number = 0;
  let decisive: boolean = false;
  let hostile: boolean = false;

  for (let i = 0; i < findings.length; i++) {
    const finding: ThreatFinding = findings[i];
    if (finding.level === 'high') {
      highCount++;
    } else if (finding.level === 'medium') {
      mediumCount++;
    }
    if (DECISIVE_CATEGORIES.indexOf(finding.category) >= 0) {
      decisive = true;
    }
    if (finding.level === 'high' && HOSTILE_FINDING_IDS.indexOf(finding.id) >= 0) {
      hostile = true;
    }
  }

  if (decisive || hostile || highCount >= 2) {
    return 'malicious';
  }
  if (highCount === 1 || mediumCount >= 2) {
    return 'suspicious';
  }
  if (mediumCount === 1) {
    return 'suspicious';
  }
  return 'clean';
}

function buildSummary(report: ThreatScanReport): string {
  const counts: Map<ThreatLevel, number> = new Map<ThreatLevel, number>([
    ['high', 0], ['medium', 0], ['low', 0], ['info', 0]
  ]);
  for (let i = 0; i < report.findings.length; i++) {
    const level: ThreatLevel = report.findings[i].level;
    counts.set(level, (counts.get(level) ?? 0) + 1);
  }
  const high: number = counts.get('high') ?? 0;
  const medium: number = counts.get('medium') ?? 0;
  const low: number = counts.get('low') ?? 0;

  const verdictText: string = report.verdict === 'malicious'
    ? '该文件存在明确的恶意特征，不建议提交或打开。'
    : (report.verdict === 'suspicious'
      ? '该文件存在可疑特征，建议核实来源后再处理。'
      : (report.verdict === 'clean'
        ? '未发现恶意特征。'
        : '文件内容无法有效解析，未能完成检查。'));

  return `${verdictText}识别类型：${report.detectedType}。` +
    `高风险 ${high} 项、中风险 ${medium} 项、提示 ${low} 项。`;
}

/** Scan the decoded text of a payload with every text-side scanner. */
function scanTextPayload(text: string, options: ThreatScannerOptions): ThreatFinding[] {
  if (text.length === 0) {
    return [];
  }
  const scoped: string = text.length > options.maxTextScanChars
    ? text.substring(0, options.maxTextScanChars)
    : text;

  const findings: ThreatFinding[] = [];
  findings.push(...scanSensitiveText(scoped));
  if (looksLikeScript(scoped)) {
    findings.push(...scanScriptText(scoped));
  }
  const iocs = extractIocs(scoped);
  findings.push(...assessIocs(iocs));
  return findings;
}

export class ThreatScanner {
  /** Scan one file entirely on-device. */
  static scanFile(fileName: string, data: Uint8Array,
    overrides?: ThreatScannerOverrides): ThreatScanReport {
    const started: number = Date.now();
    const effective: ThreatScannerOptions = mergeOptions(overrides);

    const findings: ThreatFinding[] = [];
    const typeResult: TypeDetectResult = TypeDetector.scan(fileName, data);
    findings.push(...typeResult.findings);
    const sha256: string = sha256Hex(data);

    if (data.length === 0) {
      return {
        fileName: fileName,
        fileSize: 0,
        sha256: sha256,
        detectedType: '空文件',
        declaredType: typeResult.declaredLabel,
        typeConsistent: true,
        containerKind: 'unknown',
        findings: [],
        indicators: [],
        verdict: 'unknown',
        score: 100,
        durationMs: Date.now() - started,
        layers: 'L1',
        summary: '文件为空，未执行检查。'
      };
    }

    // ------------------------------------------------------ hash reputation
    if (effective.blacklist.size > 0) {
      const match = effective.blacklist.lookup(sha256);
      if (match !== undefined) {
        const note: string = match.entry.note !== undefined ? ` ${match.entry.note}` : '';
        findings.push({
          id: 'signature.blacklist-hit',
          category: 'signature-match',
          label: '命中已知样本黑名单',
          detail: `该文件哈希与已知样本「${match.entry.family}」完全一致。${note}`,
          level: 'high',
          source: 'SignatureDB',
          evidence: `${normalizeHash(sha256).substring(0, 16)}…`
        });
      }
    }

    // ------------------------------------------------- container dispatch
    const container: string = typeResult.container;
    let scannedContent: boolean = false;
    let decodedText: string = '';

    if (container === 'zip') {
      const archive: ArchiveScanResult = scanArchive(fileName, data, effective.archive);
      findings.push(...archive.findings);
      scannedContent = true;

      const macro = scanMacros(
        fileName,
        data,
        archive.directory !== undefined ? archive.directory.entries : undefined,
        archive.vbaPayloads
      );
      findings.push(...macro.findings);

      // Inner executables found inside the archive go through PE analysis.
      for (let i = 0; i < archive.innerExecutables.length; i++) {
        const inner = archive.innerExecutables[i];
        const analysis: PeAnalysis = analyzePe(inner.data);
        if (analysis.valid) {
          findings.push(...peFindings(analysis, inner.name));
        } else if (analysis.isPe) {
          findings.push(...peFindings(analysis, inner.name));
        }
      }

      if (archive.extractedText.length > 0) {
        decodedText = archive.extractedText;
        findings.push(...scanTextPayload(decodedText, effective));
      }
    } else if (container === 'ole') {
      const macro = scanMacros(fileName, data, undefined, []);
      findings.push(...macro.findings);
      scannedContent = true;
    } else if (container === 'pe') {
      const analysis: PeAnalysis = analyzePe(data);
      findings.push(...peFindings(analysis, fileName));
      scannedContent = true;
    } else if (container === 'pdf') {
      const pdf = analyzePdf(data);
      findings.push(...pdf.findings);
      if (pdf.embeddedScript.length > 0) {
        findings.push(...scanScriptText(pdf.embeddedScript));
      }
      scannedContent = true;
    }

    // ---------------------------------------------- text / string payloads
    if (looksLikeText(data)) {
      const text: string = decodeTextPayload(data);
      if (text.length > 0) {
        decodedText = decodedText.length > 0 ? decodedText : text;
        findings.push(...scanTextPayload(text, effective));
        scannedContent = true;
      }
    } else if (effective.scanBinaryStrings && data.length > 64) {
      const strings: string[] = extractAllStrings(
        data, 6, effective.maxExtractedStrings
      );
      if (strings.length > 0) {
        const corpus: string = stringsToCorpus(strings, effective.maxTextScanChars);
        findings.push(...scanTextPayload(corpus, effective));
        scannedContent = true;
      }
    }

    // ------------------------------------------------------------- entropy
    if (data.length >= 4096) {
      const entropy: number = shannonEntropy(data, 0, data.length);
      // Executable containers already reason about entropy per section.
      if (entropy >= 7.95 && container !== 'pe') {
        findings.push({
          id: 'entropy.whole-file',
          category: 'entropy',
          label: '文件整体接近完全随机',
          detail: `整文件熵为 ${entropy.toFixed(2)} bit/byte（上限 8.00），` +
            '说明内容被强加密或压缩，常规内容检查无法生效。',
          level: 'medium',
          source: 'EntropyScan',
          evidence: `熵 ${entropy.toFixed(2)}`
        });
      }
    }

    // ------------------------------------------------------------ finalise
    const unique: ThreatFinding[] = dedupe(findings);
    const score: number = computeScore(unique);
    const verdict: ThreatVerdict = computeVerdict(unique, scannedContent);
    // Only text that was actually decoded can yield indicators; a PE's string
    // blob is deliberately not mined here to keep this step cheap.
    const indicators: string[] = decodedText.length > 0
      ? indicatorList(extractIocs(decodedText)) : [];

    const report: ThreatScanReport = {
      fileName: fileName,
      fileSize: data.length,
      sha256: sha256,
      detectedType: typeResult.detectedLabel,
      declaredType: typeResult.declaredLabel,
      typeConsistent: typeResult.consistent,
      containerKind: container,
      findings: unique,
      indicators: indicators,
      verdict: verdict,
      score: score,
      durationMs: Date.now() - started,
      layers: 'L1',
      summary: ''
    };
    report.summary = buildSummary(report);
    return report;
  }
}
