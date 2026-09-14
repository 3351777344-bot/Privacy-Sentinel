/**
 * L1 — file type verification.
 *
 * Answers two questions the extension alone cannot: "what is this really?"
 * and "does the name lie about it?".
 */

import { ThreatFinding } from '../../models/ThreatModels';
import {
  DANGEROUS_EXTENSIONS,
  DOUBLE_EXTENSION_TARGETS,
  FileKind,
  MAGIC_SIGNATURES,
  MagicSignature,
  detectSignature,
  extensionOf,
  labelForKind,
  matchesSignature,
  trailingExtensions
} from './MagicBytesTable';

const SOURCE: string = 'TypeDetector';

/** Extensions that only ever appear as the *decoy* half of `a.pdf.exe`. */
const DECOY_EXTENSIONS: string[] = [
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'rtf',
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'mp3', 'mp4', 'avi', 'mkv', 'zip',
  'rar', '7z', 'csv', 'html', 'htm', 'xml', 'json', 'log', 'dat'
];

/** Characters attackers hide inside file names to flip the rendered text. */
const BIDI_CONTROL_CODES: number[] = [
  0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069
];

export interface TypeDetectResult {
  detectedLabel: string;
  declaredLabel: string;
  container: string;
  consistent: boolean;
  executablePayload: boolean;
  findings: ThreatFinding[];
}

function finding(
  id: string,
  label: string,
  detail: string,
  level: 'high' | 'medium' | 'low' | 'info',
  evidence?: string
): ThreatFinding {
  return {
    id: id,
    category: 'type-spoof',
    label: label,
    detail: detail,
    level: level,
    source: SOURCE,
    evidence: evidence
  };
}

/** Detect bidi / control characters that make a name render backwards. */
function scanNameControls(fileName: string): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  for (let i = 0; i < fileName.length; i++) {
    const code: number = fileName.charCodeAt(i);
    if (BIDI_CONTROL_CODES.indexOf(code) >= 0) {
      findings.push(finding(
        'type.bidi-override',
        '文件名包含方向覆写字符',
        '文件名为视觉欺骗，实际扩展名与显示的可能完全相反。',
        'high',
        `U+${code.toString(16).toUpperCase()}`
      ));
      return findings;
    }
    if (code < 0x20 && code !== 0x09) {
      findings.push(finding(
        'type.control-char',
        '文件名包含控制字符',
        '控制字符常用于截断或伪造文件类型显示。',
        'medium',
        `0x${code.toString(16).toUpperCase()}`
      ));
      return findings;
    }
  }
  return findings;
}

function isDecoy(ext: string): boolean {
  return DECOY_EXTENSIONS.indexOf(ext) >= 0;
}

function firstMatchingSignatureLabel(data: Uint8Array, kind: FileKind): string {
  for (let i = 0; i < MAGIC_SIGNATURES.length; i++) {
    const signature: MagicSignature = MAGIC_SIGNATURES[i];
    if (signature.kind === kind && matchesSignature(signature, data)) {
      return signature.label;
    }
  }
  return '';
}

export class TypeDetector {
  /** Runs every type-related check for one file. */
  static scan(fileName: string, data: Uint8Array): TypeDetectResult {
    const findings: ThreatFinding[] = [];
    const declaredExtension: string = extensionOf(fileName);
    const extensions: string[] = trailingExtensions(fileName);
    const detected: MagicSignature | undefined = detectSignature(data);

    const detectedLabel: string = detected !== undefined
      ? detected.label
      : '未识别的二进制 / 纯文本';
    const kindLabel: string = detected !== undefined
      ? labelForKind(detected.kind)
      : '未知类型';
    const declaredLabel: string = declaredExtension.length > 0
      ? `.${declaredExtension} 文件`
      : '无扩展名';

    let consistent: boolean = true;
    let executablePayload: boolean = false;

    findings.push(...scanNameControls(fileName));

    if (detected !== undefined) {
      executablePayload = detected.executable;
      const allowsDeclared: boolean = detected.extensions.indexOf(declaredExtension) >= 0;
      if (!allowsDeclared) {
        consistent = false;
        if (detected.executable) {
          findings.push(finding(
            'type.spoof-executable',
            '文件类型与扩展名不符（可执行载荷）',
            `扩展名声称是 ${declaredLabel}，实际内容为${detectedLabel}。` +
              '这是典型的"换名投递"，双击后执行的是程序而不是文档。',
            'high',
            `${declaredLabel} -> ${detected.label}`
          ));
        } else if (declaredExtension.length === 0) {
          findings.push(finding(
            'type.missing-extension',
            '文件缺少扩展名',
            `内容实际为${detectedLabel}，但没有扩展名可供判断。`,
            'low',
            detected.label
          ));
        } else {
          findings.push(finding(
            'type.mismatch-benign',
            '文件类型与扩展名不一致',
            `扩展名声称是 ${declaredLabel}，实际内容为${detectedLabel}。`,
            'low',
            `${declaredLabel} -> ${detected.label}`
          ));
        }
      }
    } else {
      // No signature matched. Flag it only when the extension promises binary.
      if (declaredExtension.length > 0 && !isTextExtension(declaredExtension)) {
        findings.push(finding(
          'type.signature-missing',
          '扩展名声称二进制格式但缺少文件头',
          `扩展名为 .${declaredExtension}，但文件头不符合任何已知格式。` +
            '可能是被截断、被加壳，或扩展名是伪造的。',
          'medium',
          declaredExtension
        ));
      }
    }

    // ------------------------------------------------------- double extension
    if (extensions.length >= 2) {
      const last: string = extensions[extensions.length - 1];
      const decoy: string = extensions[extensions.length - 2];
      if (DOUBLE_EXTENSION_TARGETS.indexOf(last) >= 0 && isDecoy(decoy)) {
        findings.push(finding(
          'type.double-extension',
          '双扩展名（伪装的执行文件）',
          `文件名以 .${decoy}.${last} 结尾。资源管理器只显示 .${decoy} 图标，` +
            `实际双击运行的是 .${last}。`,
          'high',
          `.${decoy}.${last}`
        ));
      }
    }

    // ------------------------------------------------- dangerous declared type
    if (DANGEROUS_EXTENSIONS.indexOf(declaredExtension) >= 0) {
      const label: string = firstMatchingSignatureLabel(data, 'executable');
      findings.push(finding(
        'type.executable-extension',
        '材料中混入可执行文件',
        `扩展名 .${declaredExtension} 本身即可执行，不应作为提交材料。` +
          (label.length > 0 ? `内容确认为${label}。` : ''),
        'high',
        `.${declaredExtension}`
      ));
    }

    // ------------------------------------------------------- naming hygiene
    if (/[ .]$/.test(fileName)) {
      findings.push(finding(
        'type.trailing-name-char',
        '文件名以空格或点结尾',
        '部分系统会忽略结尾的空格或点，导致实际扩展名被隐藏。',
        'medium',
        fileName
      ));
    }
    if (/[\uFF00-\uFFEF]/.test(fileName)) {
      findings.push(finding(
        'type.fullwidth-lookalike',
        '文件名包含全角字符',
        '全角字符常被用来伪造与常见扩展名相似的名称。',
        'medium',
        fileName
      ));
    }

    return {
      detectedLabel: detectedLabel,
      declaredLabel: kindLabel,
      container: detected !== undefined ? detected.container : 'unknown',
      consistent: consistent,
      executablePayload: executablePayload,
      findings: findings
    };
  }
}

function isTextExtension(extension: string): boolean {
  const textExtensions: string[] = [
    'txt', 'md', 'markdown', 'csv', 'tsv', 'log', 'json', 'xml', 'yaml',
    'yml', 'ini', 'cfg', 'conf', 'env', 'properties', 'sql', 'pem', 'crt',
    'html', 'htm', 'css', 'js', 'ts', 'py', 'java', 'c', 'cpp', 'h',
    'sh', 'bat', 'ps1', 'vbs', 'go', 'rs', 'rb', 'php', 'kt', 'ets'
  ];
  return textExtensions.indexOf(extension) >= 0;
}
