/**
 * Presentation mapping for Doc Shield scan results.
 *
 * Keeps the page component free of scoring tables: turns raw `ThreatFinding`
 * records into the `Finding` shape the report panel renders, and merges the
 * on-device pass with the optional server pass.
 */

import { Finding, RiskLevel } from '../models/SecurityModels';
import { ThreatFinding, ThreatLevel, ThreatScanReport } from '../models/ThreatModels';

/** Map a scanner severity onto the 3-level UI scale. */
export function riskLevelOfThreat(level: ThreatLevel): RiskLevel {
  if (level === 'high') {
    return 'high';
  }
  if (level === 'medium') {
    return 'medium';
  }
  return 'low';
}

/** Derive an overall risk level from the 0-100 score. */
export function riskLevelOfScore(score: number): RiskLevel {
  if (score < 60) {
    return 'high';
  }
  if (score < 85) {
    return 'medium';
  }
  return 'low';
}

/** Actionable Chinese advice for one finding, keyed by its category. */
export function suggestionForFinding(item: ThreatFinding): string {
  const category: string = item.category;
  if (category === 'signature-match') {
    return '该文件与已知恶意样本一致，请立即删除，不要提交。';
  }
  if (category === 'type-spoof') {
    return '文件真实类型与扩展名不符，请重命名或隔离后再处理。';
  }
  if (category === 'archive-bomb' || category === 'archive-slip') {
    return '不要解压该压缩包，请通过官方渠道重新获取。';
  }
  if (category === 'archive-nesting') {
    return '压缩包内还有多层压缩，建议逐层核对来源后再处理。';
  }
  if (category === 'archive-encrypted') {
    return '加密压缩包无法核查内容，请向发送方索要明文版本。';
  }
  if (category === 'credential-leak') {
    return '移除或替换泄露的密钥、口令等凭据后再提交。';
  }
  if (category === 'privacy-leak') {
    return '遮盖或删除个人敏感信息后再提交。';
  }
  if (category === 'dangerous-script') {
    return '不要执行该脚本，仅用纯文本编辑器查看内容。';
  }
  if (category === 'macro') {
    return '禁用宏并拒绝启用内容，必要时向对方索取 PDF 版本。';
  }
  if (category === 'pe-structure' || category === 'pe-behavior') {
    return '不要运行该程序；如非课程必需，请直接删除。';
  }
  if (category === 'entropy') {
    return '内容高度加密或压缩，请核实来源后再决定是否使用。';
  }
  if (category === 'ioc') {
    return '核实其中的域名与地址是否可信，避免点击或访问。';
  }
  return '核实文件来源，必要时用杀毒工具二次确认。';
}

/** Convert one scan report into UI findings, prefixed with the file name. */
export function toFindings(report: ThreatScanReport, fileName: string): Finding[] {
  return toFindingsFromThreat(report.findings, fileName);
}

/** Convert raw scanner findings into UI findings, prefixed with the file name. */
export function toFindingsFromThreat(items: ThreatFinding[], fileName: string): Finding[] {
  const out: Finding[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: ThreatFinding = items[i];
    const detail: string = item.evidence !== undefined && item.evidence.length > 0
      ? `${item.detail}\n证据：${item.evidence}`
      : item.detail;
    out.push({
      title: `【${fileName}】${item.label}`,
      evidence: detail,
      suggestion: suggestionForFinding(item),
      riskLevel: riskLevelOfThreat(item.level)
    });
  }
  return out;
}

export function appendFindings(target: Finding[], items: Finding[]): void {
  for (let i = 0; i < items.length; i++) {
    target.push(items[i]);
  }
}

/** Concatenate two finding lists, dropping later duplicates by title. */
export function mergeFindings(local: Finding[], backend: Finding[]): Finding[] {
  const out: Finding[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < local.length; i++) {
    if (!seen.has(local[i].title)) {
      seen.add(local[i].title);
      out.push(local[i]);
    }
  }
  for (let i = 0; i < backend.length; i++) {
    if (!seen.has(backend[i].title)) {
      seen.add(backend[i].title);
      out.push(backend[i]);
    }
  }
  return out;
}

/** One-line Chinese summary of the on-device pass. */
export function buildLocalSummary(scanned: number, malicious: number,
  suspicious: number, unreadable: number): string {
  const parts: string[] = [`本机已检查 ${scanned} 个文件。`];
  if (malicious > 0) {
    parts.push(`${malicious} 个文件存在明确恶意特征。`);
  }
  if (suspicious > 0) {
    parts.push(`${suspicious} 个文件存在可疑特征。`);
  }
  if (unreadable > 0) {
    parts.push(`${unreadable} 个文件未能读取。`);
  }
  if (malicious === 0 && suspicious === 0 && unreadable === 0 && scanned > 0) {
    parts.push('未发现恶意或可疑特征。');
  }
  return parts.join('');
}

/** Normalise a thrown value into a readable message. */
export function describeError(error: Object, fallback: string): string {
  const typedError = error as Error;
  return typedError.message ? `${fallback}：${typedError.message}` : fallback;
}
