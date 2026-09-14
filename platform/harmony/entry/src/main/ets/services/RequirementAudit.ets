/**
 * Doc Shield — requirement-driven audit of the selected file names, on device.
 *
 * Only names and extensions are read, never file content, so the whole check
 * runs locally with no upload. `RequirementKeywords.parseRequirement` reads the
 * brief, `NamingTemplate` judges each name against the naming template and
 * `checkFormats` compares the extensions — the same code the server runs, pinned
 * by platform/contracts/requirement_cases.json so the two cannot drift.
 *
 * This lives outside `scanners/` on purpose: it builds UI findings, while the
 * scanners stay platform- and model-free so the Node harness can run them.
 */

import { Finding } from '../models/SecurityModels';
import {
  FormatCheckResult,
  LocalRequirements,
  checkFormats,
  parseRequirement
} from './scanners/RequirementKeywords';
import {
  NamingCheckResult,
  NamingTemplate,
  checkNaming,
  describeProblems,
  describeTemplate
} from './scanners/NamingTemplate';

/** Result of comparing the selected materials against the brief. */
export interface RequirementAudit {
  findings: Finding[];
  /** One line for the status area; `''` when the brief stated nothing usable. */
  note: string;
  /** What the device read out of the brief, for the report attribution card. */
  echo: string;
  /** How many file names were judged against a recognised template. */
  checkedNames: number;
}

/** Deduction for one finding of this severity, mirroring the server table. */
function penaltyPerFinding(level: string): number {
  if (level === 'high') {
    return 25;
  }
  if (level === 'medium') {
    return 12;
  }
  return 3;
}

/**
 * 0-100 score for a list of findings.
 *
 * Mirrors `platform/backend/modules/risk_scoring.py`: same per-severity penalty
 * and at most four findings of a severity counted, so a long list of small
 * problems cannot drive the score to zero on its own. Keeping the tables in step
 * matters because the page takes `min(local, backend)` — a mismatch would make
 * the score jump when the server happened to be reachable.
 */
export function scoreForFindings(findings: Finding[]): number {
  let high: number = 0;
  let medium: number = 0;
  let low: number = 0;
  for (let i = 0; i < findings.length; i++) {
    const level: string = findings[i].riskLevel;
    if (level === 'high') {
      high++;
    } else if (level === 'medium') {
      medium++;
    } else {
      low++;
    }
  }
  if (high > 4) {
    high = 4;
  }
  if (medium > 4) {
    medium = 4;
  }
  if (low > 4) {
    low = 4;
  }
  const penalty: number = high * penaltyPerFinding('high')
    + medium * penaltyPerFinding('medium')
    + low * penaltyPerFinding('low');
  return Math.max(0, 100 - penalty);
}

/** One-line rendering of what the device understood from the brief. */
export function describeLocalRequirements(parsed: LocalRequirements): string {
  const parts: string[] = [];
  if (parsed.formatLabels.length > 0) {
    parts.push(`格式 ${parsed.formatLabels.join('、')}`);
  }
  if (parsed.materials.length > 0) {
    parts.push(`材料 ${parsed.materials.join('、')}`);
  }
  if (parsed.namingRule.length > 0) {
    if (parsed.namingTemplate.recognised) {
      parts.push(`命名 ${describeTemplate(parsed.namingTemplate)}`);
    } else {
      parts.push(`命名规则「${parsed.namingRule}」需人工确认`);
    }
  }
  return parts.join('；');
}

/** Result of the naming half of the audit. */
interface NamingAudit {
  findings: Finding[];
  note: string;
  checkedNames: number;
}

/** Judge every file name against a recognised naming template. */
function auditNaming(template: NamingTemplate, rule: string,
  fileNames: string[]): NamingAudit {
  const findings: Finding[] = [];
  let checkedNames: number = 0;

  if (!template.recognised) {
    // Honest rather than silent: the old checker passed every file whenever the
    // rule could not be parsed, which is how `只要一张图片` looked "satisfied".
    findings.push({
      title: '命名规则无法自动校验，需人工确认',
      evidence: `提交要求里的「${rule}」读不出分段模板，端内没有对文件名做命名判定。`,
      suggestion: '把要求写成 学号_姓名_课程名称 这样的分段模板，或在提交前人工核对每个文件名。',
      riskLevel: 'low'
    });
    return { findings: findings, note: '命名规则需人工确认', checkedNames: checkedNames };
  }

  const advice: string = `按「${describeTemplate(template)}」重命名后再提交`;
  for (let i = 0; i < fileNames.length; i++) {
    const result: NamingCheckResult = checkNaming(fileNames[i], template);
    if (result.checked) {
      checkedNames++;
    }
    if (result.problems.length === 0) {
      continue;
    }
    findings.push({
      title: `【${fileNames[i]}】命名不符合要求`,
      evidence: describeProblems(result.problems, template).join('；'),
      suggestion: advice,
      riskLevel: 'medium'
    });
  }

  return {
    findings: findings,
    note: `端内按命名模板校验了 ${checkedNames} 个文件名`,
    checkedNames: checkedNames
  };
}

/** Check the selected extensions against the formats the brief demands. */
function auditFormats(parsed: LocalRequirements, fileNames: string[]): Finding[] {
  const findings: Finding[] = [];
  if (parsed.formats.length === 0) {
    return findings;
  }

  const result: FormatCheckResult = checkFormats(parsed.formats, fileNames);

  for (let i = 0; i < result.missing.length; i++) {
    const canonical: string = result.missing[i];
    const at: number = parsed.formats.indexOf(canonical);
    const label: string = at >= 0 && at < parsed.formatLabels.length
      ? parsed.formatLabels[at] : canonical.toUpperCase();
    findings.push({
      title: `缺少要求的 ${label} 格式材料`,
      evidence: `提交要求指定了 ${label}，所选文件里没有任何一个符合该格式（含可互换后缀）。`,
      suggestion: `补充或转换出一份 ${label} 文件后再提交。`,
      riskLevel: 'medium'
    });
  }

  if (result.offList.length > 0) {
    findings.push({
      title: `有 ${result.offList.length} 个文件的格式不在提交要求内`,
      evidence: result.offList.join('、'),
      suggestion: '确认这些文件是否确属本次提交；若不属于，请从材料中移除。',
      riskLevel: 'medium'
    });
  }

  return findings;
}

/**
 * Compare the selected materials against the submission brief.
 *
 * @param brief     the exact text the user is submitting against
 * @param fileNames the names of the selected files (content is never read here)
 */
export function auditRequirement(brief: string, fileNames: string[]): RequirementAudit {
  const parsed: LocalRequirements = parseRequirement(brief);
  const findings: Finding[] = [];
  const notes: string[] = [];

  let checkedNames: number = 0;
  if (parsed.namingRule.length > 0) {
    const naming: NamingAudit = auditNaming(parsed.namingTemplate, parsed.namingRule, fileNames);
    for (let i = 0; i < naming.findings.length; i++) {
      findings.push(naming.findings[i]);
    }
    checkedNames = naming.checkedNames;
    if (naming.note.length > 0) {
      notes.push(naming.note);
    }
  }

  const formatFindings: Finding[] = auditFormats(parsed, fileNames);
  for (let i = 0; i < formatFindings.length; i++) {
    findings.push(formatFindings[i]);
  }
  if (parsed.formats.length > 0 && formatFindings.length === 0) {
    notes.push(`${parsed.formatLabels.join('、')} 格式符合要求`);
  }

  let note: string = '';
  if (notes.length > 0) {
    note = `${notes.join('；')}。`;
  }
  if (findings.length === 0 && parsed.namingRule.length === 0 && parsed.formats.length === 0) {
    note = '提交要求里没有可端内比对的命名或格式条款，未做命名/格式判定。';
  }

  return {
    findings: findings,
    note: note,
    echo: describeLocalRequirements(parsed),
    checkedNames: checkedNames
  };
}
