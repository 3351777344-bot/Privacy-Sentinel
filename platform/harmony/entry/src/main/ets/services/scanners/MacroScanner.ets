/**
 * L1 — macro malware detector (surface level).
 *
 * Scope is deliberately bounded. A full MS-OVBA implementation (CFB stream
 * walk, p-code decompilation, compressed-source inflate) is a multi-thousand
 * line port with no Python runtime to lean on, so this scanner answers the
 * three questions that actually drive a submission decision:
 *
 *   1. Is this a macro-capable container at all?
 *   2. Is a VBA project physically present?
 *   3. Does the payload reference auto-exec triggers or host-abuse APIs?
 *
 * Keyword matching works on two lower-cased *views* of the payload — one read
 * as ASCII, one read as UTF-16LE — instead of searching for byte patterns.
 * That is required for correctness, not just tidiness: OLE stream names and VBA
 * string literals are stored wide, and a byte-level search for `autoopen` would
 * never match the `A u t o O p e n` sequence actually on disk.
 */

import type { ThreatFinding } from '../../models/ThreatModels';
import type { ZipEntry } from './ZipReader';

const SOURCE: string = 'MacroScanner';

export const MACRO_EXTENSIONS: string[] = [
  'docm', 'dotm', 'xlsm', 'xltm', 'xlam', 'pptm', 'potm', 'ppam', 'sldm'
];

export const LEGACY_OLE_EXTENSIONS: string[] = [
  'doc', 'dot', 'xls', 'xlt', 'ppt', 'pot', 'vsd', 'msg', 'mdb', 'one'
];

/** Entry names that prove a VBA project is embedded in an OOXML package. */
const VBA_PROJECT_PATHS: string[] = [
  'word/vbaproject.bin', 'xl/vbaproject.bin', 'ppt/vbaproject.bin',
  'word/vbadata.xml', 'xl/vbadata.xml', 'ppt/vbadata.xml'
];

/** OLE stream names that indicate macros (compared lower-cased). */
const OLE_STREAM_MARKERS: string[] = [
  'vba', '_vba_project', 'macros', 'thisdocument', 'module1',
  'project', 'vbaproject', 'worddocument'
];

/** Entry-name prefixes used by embedded object sidecars. */
const ACTIVE_X_PREFIXES: string[] = ['word/activex/', 'xl/activex/', 'ppt/activex/'];

const AUTO_EXEC_TRIGGERS: string[] = [
  'autoopen', 'auto_open', 'autoclose', 'auto_close', 'autoexec', 'auto_exec',
  'autonew', 'auto_new', 'autoexit', 'workbook_open', 'workbook_beforeclose',
  'workbook_activate', 'workbook_sheetchange', 'worksheet_activate',
  'worksheet_change', 'document_open', 'document_close', 'document_new',
  'documentbeforeclose', 'documentbeforesave', 'documentbeforeprint',
  'presentation_open', 'presentation_close', 'application_workbookopen'
];

const HOST_ABUSE_APIS: string[] = [
  'wscript.shell', 'shell.application', 'createobject', 'getobject',
  'urldownloadtofile', 'winexec', 'shellexecute',
  'adodb.stream', 'msxml2.xmlhttp', 'winhttp.winhttprequest',
  'xmlhttp', 'declare ptrsafe function', 'declare function',
  'frombase64string', 'system.privateprofilestring', 'shell(', 'environ(',
  'deletefile', 'filecopy'
];

/** Tokens whose presence in a macro body implies execution power. */
const EXECUTION_TOKENS: string[] = [
  'powershell', 'cmd.exe', 'cmd /c', 'wscript',
  'mshta', 'rundll32', 'certutil', '-encodedcommand'
];

/** Character budget for each search view, to bound work on large containers. */
const MAX_VIEW_CHARS: number = 4 * 1024 * 1024;

export interface MacroFormatInfo {
  /** True for docm/xlsm/pptm and friends. */
  macroCapableExtension: boolean;
  /** True when the container is OLE2 (legacy Office, MSI, MSG...). */
  oleContainer: boolean;
  /** True when a vbaProject.bin / VBA stream was located. */
  vbaProjectPresent: boolean;
  /** Paths or markers that proved the presence. */
  evidencePaths: string[];
}

export interface MacroScanResult {
  format: MacroFormatInfo;
  findings: ThreatFinding[];
}

interface SearchViews {
  /** Lower-cased printable-ASCII reading, non-printables replaced by newlines. */
  ascii: string;
  /** Lower-cased UTF-16LE reading — where wide strings actually live. */
  wide: string;
}

function hasAnyExtension(fileName: string, extensions: string[]): boolean {
  const lower: string = fileName.toLowerCase();
  for (let i = 0; i < extensions.length; i++) {
    if (lower.endsWith(`.${extensions[i]}`)) {
      return true;
    }
  }
  return false;
}

/** True when the buffer carries the OLE2 compound-file signature. */
export function isOleContainer(data: Uint8Array): boolean {
  if (data.length < 8) {
    return false;
  }
  const signature: number[] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  for (let i = 0; i < signature.length; i++) {
    if (data[i] !== signature[i]) {
      return false;
    }
  }
  return true;
}

function asciiView(data: Uint8Array): string {
  const limit: number = data.length > MAX_VIEW_CHARS ? MAX_VIEW_CHARS : data.length;
  const chunks: string[] = [];
  for (let i = 0; i < limit; i++) {
    const b: number = data[i];
    chunks.push(b >= 0x20 && b <= 0x7E ? String.fromCharCode(b) : '\n');
  }
  return chunks.join('').toLowerCase();
}

function wideView(data: Uint8Array): string {
  const limit: number = data.length > MAX_VIEW_CHARS * 2 ? MAX_VIEW_CHARS * 2 : data.length;
  const chunks: string[] = [];
  for (let i = 0; i + 1 < limit; i += 2) {
    const code: number = data[i] | (data[i + 1] << 8);
    chunks.push(code >= 0x20 && code < 0x7F ? String.fromCharCode(code) : '\n');
  }
  return chunks.join('').toLowerCase();
}

function buildViews(data: Uint8Array): SearchViews {
  return { ascii: asciiView(data), wide: wideView(data) };
}

function viewsContain(views: SearchViews, token: string): boolean {
  if (views.ascii.indexOf(token) >= 0) {
    return true;
  }
  return views.wide.indexOf(token) >= 0;
}

/** Every token present in the payload, capped for report readability. */
function findTokens(views: SearchViews, tokens: string[], cap: number): string[] {
  const found: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    if (viewsContain(views, tokens[i])) {
      found.push(tokens[i]);
    }
    if (found.length >= cap) {
      break;
    }
  }
  return found;
}

/**
 * Identify the container and whether it carries a VBA project.
 *
 * @param zipEntries central directory of the package, when the file is a ZIP
 *        container (`docm`/`xlsm`/`pptm` are ZIPs with an OOXML layout).
 */
export function inspectMacroFormat(fileName: string, data: Uint8Array,
  zipEntries: ZipEntry[] | undefined): MacroFormatInfo {
  const info: MacroFormatInfo = {
    macroCapableExtension: hasAnyExtension(fileName, MACRO_EXTENSIONS),
    oleContainer: isOleContainer(data),
    vbaProjectPresent: false,
    evidencePaths: []
  };

  if (zipEntries !== undefined) {
    for (let i = 0; i < zipEntries.length; i++) {
      const entry: ZipEntry = zipEntries[i];
      const lowerName: string = entry.name.toLowerCase();

      for (let k = 0; k < VBA_PROJECT_PATHS.length; k++) {
        if (lowerName === VBA_PROJECT_PATHS[k] ||
          lowerName.endsWith(`/${VBA_PROJECT_PATHS[k]}`)) {
          info.vbaProjectPresent = true;
          if (info.evidencePaths.indexOf(entry.name) < 0) {
            info.evidencePaths.push(entry.name);
          }
        }
      }

      // ActiveX and embedded OLE objects are a common macro delivery sidecar.
      for (let p = 0; p < ACTIVE_X_PREFIXES.length; p++) {
        if (lowerName.startsWith(ACTIVE_X_PREFIXES[p])) {
          if (info.evidencePaths.indexOf(entry.name) < 0) {
            info.evidencePaths.push(entry.name);
          }
        }
      }
      if (lowerName.endsWith('oleobject1.bin') || lowerName.endsWith('oleobject2.bin')) {
        if (info.evidencePaths.indexOf(entry.name) < 0) {
          info.evidencePaths.push(entry.name);
        }
      }
    }
  }

  if (info.oleContainer) {
    const markers: string[] = findTokens(buildViews(data), OLE_STREAM_MARKERS, 8);
    if (markers.length > 0) {
      // `vba` / `_vba_project` are conclusive on their own; `project` is weak,
      // so it only counts for an Office container where macros are plausible.
      const strong: boolean = markers.indexOf('vba') >= 0 ||
        markers.indexOf('_vba_project') >= 0 ||
        markers.indexOf('vbaproject') >= 0 ||
        markers.indexOf('macros') >= 0;
      const officeContainer: boolean = hasAnyExtension(fileName, LEGACY_OLE_EXTENSIONS) ||
        hasAnyExtension(fileName, MACRO_EXTENSIONS);
      if (strong || (officeContainer && markers.indexOf('project') >= 0)) {
        info.vbaProjectPresent = true;
        for (let i = 0; i < markers.length; i++) {
          const label: string = `OLE 流:${markers[i]}`;
          if (info.evidencePaths.indexOf(label) < 0) {
            info.evidencePaths.push(label);
          }
        }
      }
    }
  }

  return info;
}

/** Scan a decoded macro payload (vbaProject.bin or an OLE body). */
export function scanMacroPayload(data: Uint8Array, origin: string): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  if (data.length === 0) {
    return findings;
  }
  const views: SearchViews = buildViews(data);

  const triggers: string[] = findTokens(views, AUTO_EXEC_TRIGGERS, 8);
  const apis: string[] = findTokens(views, HOST_ABUSE_APIS, 8);
  const executors: string[] = findTokens(views, EXECUTION_TOKENS, 6);

  if (triggers.length > 0) {
    findings.push({
      id: 'macro.auto-exec-trigger',
      category: 'macro',
      label: '宏包含自动执行入口',
      detail: 'AutoOpen / Document_Open 等入口会在打开文档时自动运行，' +
        '无需用户点击任何按钮。',
      level: 'high',
      source: SOURCE,
      evidence: `${origin}: ${triggers.join(', ')}`
    });
  }
  if (apis.length > 0) {
    findings.push({
      id: 'macro.host-abuse-api',
      category: 'macro',
      label: '宏调用宿主滥用接口',
      detail: 'WScript.Shell / ShellExecute / ADODB.Stream 等接口可在文档内' +
        '启动程序或下载文件。',
      level: 'high',
      source: SOURCE,
      evidence: `${origin}: ${apis.join(', ')}`
    });
  }
  if (executors.length > 0) {
    findings.push({
      id: 'macro.execution-command',
      category: 'macro',
      label: '宏内嵌命令行调用',
      detail: '宏正文中直接出现 shell 命令行，通常用于投放下一阶段载荷。',
      level: 'high',
      source: SOURCE,
      evidence: `${origin}: ${executors.join(', ')}`
    });
  }

  return findings;
}

/** Full macro assessment for one file. */
export function scanMacros(fileName: string, data: Uint8Array,
  zipEntries: ZipEntry[] | undefined,
  vbaPayloads: Uint8Array[]): MacroScanResult {
  const format: MacroFormatInfo = inspectMacroFormat(fileName, data, zipEntries);
  const findings: ThreatFinding[] = [];

  if (format.macroCapableExtension && !format.vbaProjectPresent) {
    findings.push({
      id: 'macro.enabled-format',
      category: 'macro',
      label: '启用宏的文档格式',
      detail: '该扩展名专为携带 VBA 宏而设计。本次未在包内找到 vbaProject.bin，' +
        '但仍建议确认文件来源。',
      level: 'medium',
      source: SOURCE,
      evidence: fileName
    });
  }

  if (format.vbaProjectPresent) {
    findings.push({
      id: 'macro.vba-project-present',
      category: 'macro',
      label: '文档内嵌 VBA 宏工程',
      detail: '已确认文包含有 VBA 工程，宏代码可在打开文档时执行。',
      level: 'high',
      source: SOURCE,
      evidence: format.evidencePaths.join(', ')
    });
    if (zipEntries !== undefined) {
      findings.push({
        id: 'macro.strip-before-submit',
        category: 'macro',
        label: '提交前应移除宏',
        detail: '建议另存为 .docx/.xlsx/.pptx（无宏格式）后再提交。',
        level: 'medium',
        source: SOURCE,
        evidence: fileName
      });
    }
  }

  let scannedPayloads: number = 0;
  for (let i = 0; i < vbaPayloads.length; i++) {
    const payload: Uint8Array = vbaPayloads[i];
    if (payload.length === 0) {
      continue;
    }
    scannedPayloads++;
    findings.push(...scanMacroPayload(payload, `VBA 工程 #${scannedPayloads}`));
  }

  // Fall back to the whole container when the project could not be isolated —
  // legacy OLE stores macro streams inline rather than as a separate entry.
  if (scannedPayloads === 0 && format.vbaProjectPresent && format.oleContainer) {
    findings.push(...scanMacroPayload(data, 'OLE 文档'));
  }

  return { format: format, findings: findings };
}
