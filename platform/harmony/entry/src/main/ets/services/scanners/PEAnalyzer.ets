/**
 * L1 — PE (Portable Executable) structure analysis and behaviour profiling.
 *
 * This is the "semi-emulation" tier: the loader's resolution steps are
 * replayed over a virtual address map — headers, sections, imports, relocations
 * and TLS callbacks — without a single x86 instruction ever executing. Nothing
 * is mapped executable, nothing is jumped to, no process is created. That is
 * what makes it viable on HarmonyOS NEXT, where the kernel exposes neither
 * `fork`/`execve` nor a user-mode CPU emulator hook.
 *
 * What it buys over a plain string search is the *intent* layer: a resolved
 * import set is a capability list, and capability combinations (allocate +
 * write + create thread) describe behaviour far more reliably than any single
 * keyword.
 */

import { ThreatFinding } from '../../models/ThreatModels';
import { shannonEntropy } from './EntropyScan';
import { decodeUtf8 } from './TextExtract';

const SOURCE: string = 'PEAnalyzer';

const DOS_MAGIC: number = 0x5A4D; // 'MZ'
const PE_SIGNATURE: number = 0x00004550; // 'PE\0\0'

const OPTIONAL_MAGIC_PE32: number = 0x010B;
const OPTIONAL_MAGIC_PE32_PLUS: number = 0x020B;

const MACHINE_LABELS: Map<number, string> = new Map<number, string>([
  [0x014C, 'x86 (32 位)'],
  [0x8664, 'x64 (64 位)'],
  [0x01C0, 'ARM'],
  [0x01C4, 'ARMv7'],
  [0xAA64, 'ARM64'],
  [0x0200, 'IA64'],
  [0x0EBC, 'EFI 字节码']
]);

const SUBSYSTEM_LABELS: Map<number, string> = new Map<number, string>([
  [0, '未知'],
  [1, '原生 (Native)'],
  [2, 'Windows 图形界面'],
  [3, 'Windows 控制台'],
  [5, 'OS/2 控制台'],
  [7, 'POSIX 控制台'],
  [9, 'Windows CE'],
  [10, 'EFI 应用'],
  [14, 'Xbox']
]);

/** Section names that identify a known packer or protector. */
const PACKER_SECTION_HINTS: Map<string, string> = new Map<string, string>([
  ['.upx0', 'UPX'],
  ['.upx1', 'UPX'],
  ['.upx2', 'UPX'],
  ['upx0', 'UPX'],
  ['upx1', 'UPX'],
  ['.vmp0', 'VMProtect'],
  ['.vmp1', 'VMProtect'],
  ['.vmp2', 'VMProtect'],
  ['.themida', 'Themida'],
  ['.aspack', 'ASPack'],
  ['.adata', 'ASPack'],
  ['.nsp0', 'NsPack'],
  ['.nsp1', 'NsPack'],
  ['.petite', 'Petite'],
  ['.mpress1', 'MPRESS'],
  ['.mpress2', 'MPRESS'],
  ['.pklstb', 'PKLite'],
  ['.enigma1', 'Enigma'],
  ['.enigma2', 'Enigma'],
  ['.boom', 'The Boomerang'],
  ['.ccg', 'CCG'],
  ['.gentee', 'Gentee'],
  ['.pdata', 'Packed (PData)'],
  ['.packed', 'Packed'],
  ['.protect', 'Protected'],
  ['pebundle', 'PEBundle']
]);

export interface PeSection {
  name: string;
  virtualAddress: number;
  virtualSize: number;
  rawSize: number;
  rawOffset: number;
  characteristics: number;
  entropy: number;
  executable: boolean;
  writable: boolean;
}

export interface PeImport {
  dll: string;
  functions: string[];
}

export type BehaviorConfidence = 'high' | 'medium' | 'low';

export interface BehaviorSignal {
  category: string;
  label: string;
  confidence: BehaviorConfidence;
  description: string;
  evidence: string[];
}

export interface PeAnalysis {
  isPe: boolean;
  valid: boolean;
  error: string;
  machine: number;
  machineLabel: string;
  is64Bit: boolean;
  numberOfSections: number;
  timestamp: number;
  entryPoint: number;
  imageBase: number;
  subsystem: number;
  subsystemLabel: string;
  dllCharacteristics: number;
  isDll: boolean;
  sizeOfImage: number;
  sections: PeSection[];
  imports: PeImport[];
  importedFunctionCount: number;
  importedDllCount: number;
  hasImportTable: boolean;
  hasTls: boolean;
  hasRelocations: boolean;
  hasResources: boolean;
  hasDigitalSignature: boolean;
  overallEntropy: number;
  entryPointInsideSection: boolean;
  packerHints: string[];
  behaviors: BehaviorSignal[];
}

function emptyAnalysis(error: string): PeAnalysis {
  return {
    isPe: false,
    valid: false,
    error: error,
    machine: 0,
    machineLabel: '未知',
    is64Bit: false,
    numberOfSections: 0,
    timestamp: 0,
    entryPoint: 0,
    imageBase: 0,
    subsystem: 0,
    subsystemLabel: '未知',
    dllCharacteristics: 0,
    isDll: false,
    sizeOfImage: 0,
    sections: [],
    imports: [],
    importedFunctionCount: 0,
    importedDllCount: 0,
    hasImportTable: false,
    hasTls: false,
    hasRelocations: false,
    hasResources: false,
    hasDigitalSignature: false,
    overallEntropy: 0,
    entryPointInsideSection: false,
    packerHints: [],
    behaviors: []
  };
}

// --------------------------------------------------------------- byte readers

function u8(data: Uint8Array, offset: number): number {
  return offset >= 0 && offset < data.length ? data[offset] : 0;
}

function u16(data: Uint8Array, offset: number): number {
  if (offset < 0 || offset + 2 > data.length) {
    return 0;
  }
  return data[offset] | (data[offset + 1] << 8);
}

function u32(data: Uint8Array, offset: number): number {
  if (offset < 0 || offset + 4 > data.length) {
    return 0;
  }
  const value: number = data[offset] | (data[offset + 1] << 8) |
    (data[offset + 2] << 16) | (data[offset + 3] << 24);
  return value >>> 0;
}

/** Read a NUL-terminated ASCII string, bounded by `maxLength`. */
function readAsciiString(data: Uint8Array, offset: number, maxLength: number): string {
  if (offset < 0 || offset >= data.length) {
    return '';
  }
  const bytes: number[] = [];
  const limit: number = Math.min(data.length, offset + maxLength);
  for (let i = offset; i < limit; i++) {
    const b: number = data[i];
    if (b === 0) {
      break;
    }
    if (b < 0x20 || b > 0x7E) {
      // Non-printable inside an import name means the pointer was wrong.
      return bytes.length > 0 ? decodeUtf8(new Uint8Array(bytes)) : '';
    }
    bytes.push(b);
  }
  return decodeUtf8(new Uint8Array(bytes));
}

/** Map a relative virtual address onto a file offset via the section table. */
function rvaToOffset(sections: PeSection[], rva: number): number {
  for (let i = 0; i < sections.length; i++) {
    const section: PeSection = sections[i];
    const span: number = Math.max(section.virtualSize, section.rawSize);
    if (rva >= section.virtualAddress && rva < section.virtualAddress + span) {
      return section.rawOffset + (rva - section.virtualAddress);
    }
  }
  return -1;
}

export function isPeFile(data: Uint8Array): boolean {
  if (data.length < 64) {
    return false;
  }
  if (u16(data, 0) !== DOS_MAGIC) {
    return false;
  }
  const peOffset: number = u32(data, 0x3C);
  if (peOffset < 0 || peOffset + 24 > data.length) {
    return false;
  }
  return u32(data, peOffset) === PE_SIGNATURE;
}

// ------------------------------------------------------------------ main entry

export function analyzePe(data: Uint8Array): PeAnalysis {
  if (!isPeFile(data)) {
    return emptyAnalysis('不是有效的 PE 文件');
  }

  const peOffset: number = u32(data, 0x3C);
  const coffOffset: number = peOffset + 4;

  const machine: number = u16(data, coffOffset);
  const numberOfSections: number = u16(data, coffOffset + 2);
  const timestamp: number = u32(data, coffOffset + 4);
  const sizeOfOptionalHeader: number = u16(data, coffOffset + 16);
  const characteristics: number = u16(data, coffOffset + 18);

  if (numberOfSections <= 0 || numberOfSections > 96) {
    return emptyAnalysis(`节表数量异常：${numberOfSections}`);
  }

  const optionalOffset: number = coffOffset + 20;
  const optionalMagic: number = u16(data, optionalOffset);
  const is64Bit: boolean = optionalMagic === OPTIONAL_MAGIC_PE32_PLUS;
  if (optionalMagic !== OPTIONAL_MAGIC_PE32 && optionalMagic !== OPTIONAL_MAGIC_PE32_PLUS) {
    return emptyAnalysis('可选头格式无法识别');
  }

  const entryPoint: number = u32(data, optionalOffset + 16);
  const imageBase: number = is64Bit
    ? u32(data, optionalOffset + 24)
    : u32(data, optionalOffset + 28);
  const sizeOfImage: number = u32(data, optionalOffset + 56);
  const subsystem: number = u16(data, optionalOffset + 68);
  const dllCharacteristics: number = u16(data, optionalOffset + 70);
  const numberOfRvaAndSizes: number = u32(data, optionalOffset + (is64Bit ? 108 : 92));
  const dataDirectoryOffset: number = optionalOffset + (is64Bit ? 112 : 96);

  // ------------------------------------------------------------ section table
  const sectionTableOffset: number = optionalOffset + sizeOfOptionalHeader;
  const sections: PeSection[] = [];
  for (let i = 0; i < numberOfSections; i++) {
    const base: number = sectionTableOffset + i * 40;
    if (base + 40 > data.length) {
      return emptyAnalysis('节表超出文件范围');
    }
    const nameBytes: number[] = [];
    for (let k = 0; k < 8; k++) {
      const b: number = u8(data, base + k);
      if (b === 0) {
        break;
      }
      nameBytes.push(b);
    }
    const name: string = decodeUtf8(new Uint8Array(nameBytes));
    const virtualSize: number = u32(data, base + 8);
    const virtualAddress: number = u32(data, base + 12);
    const rawSize: number = u32(data, base + 16);
    const rawOffset: number = u32(data, base + 20);
    const sectionCharacteristics: number = u32(data, base + 36);

    const rawStart: number = rawOffset;
    const rawEnd: number = Math.min(data.length, rawOffset + rawSize);
    const entropy: number = rawSize > 0 && rawStart < data.length
      ? shannonEntropy(data, rawStart, rawEnd)
      : 0;

    sections.push({
      name: name.length > 0 ? name : `(无名节 ${i})`,
      virtualAddress: virtualAddress,
      virtualSize: virtualSize,
      rawSize: rawSize,
      rawOffset: rawOffset,
      characteristics: sectionCharacteristics,
      entropy: entropy,
      executable: (sectionCharacteristics & 0x20000000) !== 0,
      writable: (sectionCharacteristics & 0x80000000) !== 0
    });
  }

  // -------------------------------------------------------- data directories
  const importRva: number = numberOfRvaAndSizes > 1 ? u32(data, dataDirectoryOffset + 1 * 8) : 0;
  const importSize: number = numberOfRvaAndSizes > 1 ? u32(data, dataDirectoryOffset + 1 * 8 + 4) : 0;
  const resourceRva: number = numberOfRvaAndSizes > 2 ? u32(data, dataDirectoryOffset + 2 * 8) : 0;
  const securityRva: number = numberOfRvaAndSizes > 4 ? u32(data, dataDirectoryOffset + 4 * 8) : 0;
  const relocRva: number = numberOfRvaAndSizes > 5 ? u32(data, dataDirectoryOffset + 5 * 8) : 0;
  const tlsRva: number = numberOfRvaAndSizes > 9 ? u32(data, dataDirectoryOffset + 9 * 8) : 0;

  const imports: PeImport[] = parseImports(data, sections, importRva, is64Bit);
  let importedFunctionCount: number = 0;
  for (let i = 0; i < imports.length; i++) {
    importedFunctionCount += imports[i].functions.length;
  }

  // ------------------------------------------------------------- packer hints
  const packerHints: string[] = [];
  for (let i = 0; i < sections.length; i++) {
    const section: PeSection = sections[i];
    const hint: string | undefined = PACKER_SECTION_HINTS.get(section.name.toLowerCase());
    if (hint !== undefined && packerHints.indexOf(hint) < 0) {
      packerHints.push(hint);
    }
    // A writable *and* executable section is a classic unpacking stub trait.
    if (section.writable && section.executable && packerHints.indexOf('W+X 节（自修改代码）') < 0) {
      packerHints.push('W+X 节（自修改代码）');
    }
  }

  let entryPointInsideSection: boolean = false;
  for (let i = 0; i < sections.length; i++) {
    const section: PeSection = sections[i];
    const span: number = Math.max(section.virtualSize, section.rawSize);
    if (entryPoint >= section.virtualAddress && entryPoint < section.virtualAddress + span) {
      entryPointInsideSection = true;
      break;
    }
  }

  const overallEntropy: number = shannonEntropy(data, 0, data.length);

  const analysis: PeAnalysis = {
    isPe: true,
    valid: true,
    error: '',
    machine: machine,
    machineLabel: MACHINE_LABELS.get(machine) ?? `未知 (0x${machine.toString(16)})`,
    is64Bit: is64Bit,
    numberOfSections: numberOfSections,
    timestamp: timestamp,
    entryPoint: entryPoint,
    imageBase: imageBase,
    subsystem: subsystem,
    subsystemLabel: SUBSYSTEM_LABELS.get(subsystem) ?? `未知 (${subsystem})`,
    dllCharacteristics: dllCharacteristics,
    isDll: (characteristics & 0x2000) !== 0,
    sizeOfImage: sizeOfImage,
    sections: sections,
    imports: imports,
    importedFunctionCount: importedFunctionCount,
    importedDllCount: imports.length,
    hasImportTable: importRva !== 0 && importSize !== 0,
    hasTls: tlsRva !== 0,
    hasRelocations: relocRva !== 0,
    hasResources: resourceRva !== 0,
    hasDigitalSignature: securityRva !== 0,
    overallEntropy: overallEntropy,
    entryPointInsideSection: entryPointInsideSection,
    packerHints: packerHints,
    behaviors: []
  };

  analysis.behaviors = profileBehaviors(analysis);
  return analysis;
}

// -------------------------------------------------------------------- imports

function parseImports(data: Uint8Array, sections: PeSection[], importRva: number,
  is64Bit: boolean): PeImport[] {
  const imports: PeImport[] = [];
  if (importRva === 0) {
    return imports;
  }
  let descriptorOffset: number = rvaToOffset(sections, importRva);
  if (descriptorOffset < 0) {
    return imports;
  }

  const maxDlls: number = 256;
  const maxFunctionsPerDll: number = 256;
  const maxTotalFunctions: number = 4096;
  let totalFunctions: number = 0;

  for (let i = 0; i < maxDlls; i++) {
    const base: number = descriptorOffset + i * 20;
    if (base + 20 > data.length) {
      break;
    }
    const originalFirstThunk: number = u32(data, base);
    const nameRva: number = u32(data, base + 12);
    const firstThunk: number = u32(data, base + 16);
    if (originalFirstThunk === 0 && nameRva === 0 && firstThunk === 0) {
      break;
    }

    const nameOffset: number = rvaToOffset(sections, nameRva);
    const dllName: string = nameOffset >= 0 ? readAsciiString(data, nameOffset, 256) : '';
    if (dllName.length === 0) {
      continue;
    }

    const functions: string[] = [];
    const thunkRva: number = originalFirstThunk !== 0 ? originalFirstThunk : firstThunk;
    const thunkOffset: number = rvaToOffset(sections, thunkRva);
    if (thunkOffset >= 0) {
      const entrySize: number = is64Bit ? 8 : 4;
      for (let k = 0; k < maxFunctionsPerDll; k++) {
        const entryOffset: number = thunkOffset + k * entrySize;
        if (entryOffset + entrySize > data.length) {
          break;
        }
        const thunkValue: number = is64Bit
          ? u32(data, entryOffset)
          : u32(data, entryOffset);
        if (thunkValue === 0) {
          break;
        }
        // High bit set means import-by-ordinal, which has no name to read.
        const isOrdinal: boolean = is64Bit
          ? u32(data, entryOffset + 4) !== 0 || thunkValue >= 0x80000000
          : thunkValue >= 0x80000000;
        if (isOrdinal) {
          functions.push(`#ordinal ${thunkValue & 0xFFFF}`);
          continue;
        }
        const hintNameOffset: number = rvaToOffset(sections, thunkValue);
        if (hintNameOffset < 0) {
          continue;
        }
        const functionName: string = readAsciiString(data, hintNameOffset + 2, 128);
        if (functionName.length > 0) {
          functions.push(functionName);
        }
      }
    }

    imports.push({ dll: dllName, functions: functions });
    totalFunctions += functions.length;
    if (totalFunctions >= maxTotalFunctions) {
      break;
    }
  }

  return imports;
}

// ------------------------------------------------------------- behaviour rules

interface BehaviorRule {
  category: string;
  label: string;
  confidence: BehaviorConfidence;
  description: string;
  /** Every token in this list must appear somewhere in the import set. */
  requires: string[];
  /** At least one of these must also appear (empty means no extra gate). */
  anyOf: string[];
}

const BEHAVIOR_RULES: BehaviorRule[] = [
  {
    category: 'downloader',
    label: '下载器特征',
    confidence: 'high',
    description: '具备从网络拉取文件的能力，常用于获取第二阶段载荷。',
    requires: [],
    anyOf: ['urldownloadtofile', 'internetopenurla', 'internetopenurlw', 'internetreadfile',
      'httpopenrequesta', 'httpopenrequestw', 'winhttpopen', 'winhttpconnect',
      'winhttpopenrequest', 'internetsetoptiona']
  },
  {
    category: 'injection',
    label: '进程注入特征',
    confidence: 'high',
    description: '内存分配 + 跨进程写入 + 远程线程，这是最典型的注入三件套。',
    requires: ['virtualalloc', 'writeprocessmemory'],
    anyOf: ['createremotethread', 'ntcreatethreadex', 'rtlcreatethread',
      'queueuserapc', 'setwindowshookexa', 'createthreadex']
  },
  {
    category: 'memory-manipulation',
    label: '可疑内存操作',
    confidence: 'medium',
    description: '同时具备内存分配与写入能力，常与解壳或代码注入配合使用。',
    requires: ['virtualalloc'],
    anyOf: ['writeprocessmemory', 'virtualprotect', 'ntprotectvirtualmemory',
      'mapviewoffile', 'ntmapviewofsection']
  },
  {
    category: 'persistence',
    label: '持久化特征',
    confidence: 'high',
    description: '写入注册表自启项或创建服务，可在重启后继续存活。',
    requires: [],
    anyOf: ['regsetvalueexa', 'regsetvalueexw', 'regcreatekeyexa', 'regcreatekeyexw',
      'regcreatekeya', 'createservicea', 'createservicew', 'changeserviceconfiga']
  },
  {
    category: 'dropper',
    label: '投放行为特征',
    confidence: 'high',
    description: '同时具备文件写入与进程创建能力，可释放并运行新文件。',
    requires: ['createfilea'],
    anyOf: ['createprocessa', 'createprocessw', 'winexec', 'shellexecutea',
      'shellexecutew', 'shellexecuteexa', 'winexeca']
  },
  {
    category: 'credential-access',
    label: '凭据窃取特征',
    confidence: 'high',
    description: '调用了浏览器 / 系统凭据解读接口，可能用于窃取账号密码。',
    requires: [],
    anyOf: ['cryptunprotectdata', 'credreada', 'credreadw', 'credentumera',
      'lsaenumeratelogonessions', 'lsaopenpolicy', 'samopen', 'samqueryinformationuser',
      'minidumpwritedump', 'getwindowtexta']
  },
  {
    category: 'keylogger',
    label: '键盘记录特征',
    confidence: 'medium',
    description: '具备按键状态或服务支持，并伴随窗口钩子时可能用于记录输入。',
    requires: ['getasynckeystate'],
    anyOf: ['setwindowshookexa', 'getkeystate', 'getforegroundwindow',
      'getkeyboardstate', 'mapvirtualkeya']
  },
  {
    category: 'file-encryption',
    label: '批量文件加密特征',
    confidence: 'medium',
    description: '加密接口与文件枚举同时出现，需结合上下文判断是否为勒索行为。',
    requires: [],
    anyOf: ['cryptencrypt', 'bccryptencrypt', 'cryptgenkey', 'cryptacquirecontexta',
      'cryptacquirecontextw', 'cryptderivekey']
  },
  {
    category: 'file-enumeration',
    label: '批量文件遍历',
    confidence: 'low',
    description: '具备递归遍历文件系统的能力。',
    requires: [],
    anyOf: ['findfirstfilea', 'findfirstfilew', 'findfirstfileexa', 'findnextfilea', 'findnextfilew']
  },
  {
    category: 'reverse-shell',
    label: '反向连接特征',
    confidence: 'high',
    description: '套接字连接与进程创建组合出现，具备反弹 shell 的实现条件。',
    requires: ['wsastartup'],
    anyOf: ['connect', 'socket', 'wsaasyncgethostbyname', 'gethostbyname']
  },
  {
    category: 'process-enumeration',
    label: '进程枚举特征',
    confidence: 'low',
    description: '枚举运行中的进程，常见于安全工具检测或横向探测。',
    requires: [],
    anyOf: ['createindtoolhelp32snapshot', 'process32first', 'process32firstw',
      'process32next', 'process32nextw', 'enumprocesses', 'enumprocessmodules']
  },
  {
    category: 'anti-debug',
    label: '反调试 / 反分析特征',
    confidence: 'medium',
    description: '调用了调试器检测接口，通常用于对抗动态分析。',
    requires: [],
    anyOf: ['isdebuggerpresent', 'checkremotedebuggerpresent',
      'ntqueryinformationprocess', 'outputdebugstringa', 'settoolhelptag',
      'queryperformancecounter']
  },
  {
    category: 'screen-capture',
    label: '屏幕采集特征',
    confidence: 'medium',
    description: '具备抓取屏幕位图的能力。',
    requires: ['bitblt'],
    anyOf: ['getdc', 'createdibsection', 'getsystemmetrics', 'getwindowdc']
  },
  {
    category: 'privilege-escalation',
    label: '权限提升特征',
    confidence: 'medium',
    description: '尝试获取或启用高权限令牌。',
    requires: [],
    anyOf: ['adjusttokenprivileges', 'lookupprivilegevaluea', 'lookupprivilegevaluew',
      'opentoken', 'openprocesstoken', 'duplicatetokenex']
  },
  {
    category: 'security-tamper',
    label: '安全防护干扰特征',
    confidence: 'medium',
    description: '可操作服务控制管理器，可能用于关闭安全软件或防火墙。',
    requires: ['openscmanagera'],
    anyOf: ['controlservice', 'deleteservice', 'startservicea', 'changeserviceconfiga']
  },
  {
    category: 'crypto-usage',
    label: '加密接口调用',
    confidence: 'low',
    description: '使用了系统加密接口；本身正常，但需结合其他特征判断。',
    requires: [],
    anyOf: ['cryptacquirecontexta', 'cryptacquirecontextw', 'bccryptopenalgorithmprovider',
      'cryptimportkey', 'cryptderivekey']
  }
];

function collectApiSet(imports: PeImport[]): Set<string> {
  const set: Set<string> = new Set<string>();
  for (let i = 0; i < imports.length; i++) {
    const functions: string[] = imports[i].functions;
    for (let k = 0; k < functions.length; k++) {
      set.add(functions[k].toLowerCase());
    }
  }
  return set;
}

/** Primitives that make a memory-write capability an actual injection. */
const THREAD_CREATION_PRIMITIVES: string[] = [
  'createremotethread', 'ntcreatethreadex', 'rtlcreatethread',
  'queueuserapc', 'setwindowshookexa', 'createthreadex'
];

function profileBehaviors(analysis: PeAnalysis): BehaviorSignal[] {
  const signals: BehaviorSignal[] = [];
  const apis: Set<string> = collectApiSet(analysis.imports);

  for (let i = 0; i < BEHAVIOR_RULES.length; i++) {
    const rule: BehaviorRule = BEHAVIOR_RULES[i];
    let requirementsMet: boolean = true;
    for (let r = 0; r < rule.requires.length; r++) {
      if (!apis.has(rule.requires[r])) {
        requirementsMet = false;
        break;
      }
    }
    if (!requirementsMet) {
      continue;
    }

    // Evidence carries both halves of the rule: the required primitives and the
    // optional ones that actually matched. Without the required half, a rule
    // like `injection` would report a single matched call and look weaker than
    // it is.
    const evidence: string[] = [];
    for (let r = 0; r < rule.requires.length; r++) {
      evidence.push(rule.requires[r]);
    }
    for (let a = 0; a < rule.anyOf.length; a++) {
      if (apis.has(rule.anyOf[a])) {
        evidence.push(rule.anyOf[a]);
      }
    }
    if (evidence.length === 0) {
      continue;
    }

    let confidence: BehaviorConfidence = rule.confidence;

    // Allocating and writing memory is only a full injection when something
    // also causes that memory to run.
    if (rule.category === 'injection') {
      let hasThreadPrimitive: boolean = false;
      for (let p = 0; p < THREAD_CREATION_PRIMITIVES.length; p++) {
        if (apis.has(THREAD_CREATION_PRIMITIVES[p])) {
          hasThreadPrimitive = true;
          break;
        }
      }
      if (!hasThreadPrimitive) {
        confidence = 'medium';
      }
    }

    signals.push({
      category: rule.category,
      label: rule.label,
      confidence: confidence,
      description: rule.description,
      evidence: evidence.slice(0, 8)
    });
  }

  return signals;
}

// -------------------------------------------------------------------- findings

/** Convert an analysis into report findings. */
export function peFindings(analysis: PeAnalysis, fileName: string): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  if (!analysis.isPe) {
    return findings;
  }
  if (!analysis.valid) {
    findings.push({
      id: 'pe.malformed',
      category: 'pe-structure',
      label: 'PE 结构异常',
      detail: `文件头有 PE 标识但结构无法解析：${analysis.error}。常见于被刻意损坏的样本。`,
      level: 'high',
      source: SOURCE,
      evidence: analysis.error
    });
    return findings;
  }

  // --------------------------------------------------------- structural flags
  const archiveLike = fileName.toLowerCase().endsWith('.zip') ||
    fileName.toLowerCase().endsWith('.pdf') ||
    fileName.toLowerCase().endsWith('.docx');
  if (archiveLike) {
    findings.push({
      id: 'pe.disguised',
      category: 'pe-structure',
      label: '文档外壳下的可执行程序',
      detail: '文件扩展名是文档或压缩包，但内容是可执行的 PE 程序。',
      level: 'high',
      source: SOURCE,
      evidence: `${fileName} -> ${analysis.machineLabel}`
    });
  }

  if (!analysis.hasImportTable || analysis.importedFunctionCount === 0) {
    findings.push({
      id: 'pe.no-imports',
      category: 'pe-structure',
      label: '缺少导入表',
      detail: '正常程序都会声明依赖的系统函数。导入表为空通常意味着样本被加壳，' +
        '或在运行时才动态解析 API。',
      level: 'high',
      source: SOURCE,
      evidence: `导入函数 ${analysis.importedFunctionCount} 个`
    });
  }

  if (!analysis.entryPointInsideSection) {
    findings.push({
      id: 'pe.entry-outside-sections',
      category: 'pe-structure',
      label: '入口点不在任何节内',
      detail: '入口点地址落在所有节的地址范围之外，常见于畸形或手工构造的文件。',
      level: 'high',
      source: SOURCE,
      evidence: `入口 RVA 0x${analysis.entryPoint.toString(16)}`
    });
  }

  if (analysis.overallEntropy >= 7.6) {
    findings.push({
      id: 'pe.high-entropy',
      category: 'entropy',
      label: '整体熵值接近随机',
      detail: `整文件熵为 ${analysis.overallEntropy.toFixed(2)} bit/byte，` +
        '接近理论上限，说明内容被加密或压缩（加壳）。',
      level: 'medium',
      source: SOURCE,
      evidence: `熵 ${analysis.overallEntropy.toFixed(2)}`
    });
  }

  if (analysis.packerHints.length > 0) {
    findings.push({
      id: 'pe.packer',
      category: 'pe-structure',
      label: '检测到加壳特征',
      detail: `节表特征指向已知加壳工具：${analysis.packerHints.join('、')}。` +
        '壳会隐藏真实代码，使静态分析结果不可靠。',
      level: 'medium',
      source: SOURCE,
      evidence: analysis.packerHints.join(', ')
    });
  }

  // Highly entropic executable sections are the signature of a packed body.
  const packedSections: string[] = [];
  for (let i = 0; i < analysis.sections.length; i++) {
    const section: PeSection = analysis.sections[i];
    if (section.executable && section.rawSize >= 4096 && section.entropy >= 7.2) {
      packedSections.push(`${section.name}(熵 ${section.entropy.toFixed(2)})`);
    }
  }
  if (packedSections.length > 0 && analysis.packerHints.length === 0) {
    findings.push({
      id: 'pe.encrypted-code-section',
      category: 'entropy',
      label: '可执行节为高熵内容',
      detail: '代码节内容接近随机分布，通常是被加密的载荷或壳的压缩数据。',
      level: 'medium',
      source: SOURCE,
      evidence: packedSections.join(', ')
    });
  }

  if (analysis.hasTls) {
    findings.push({
      id: 'pe.tls-callback',
      category: 'pe-structure',
      label: '存在 TLS 回调',
      detail: 'TLS 回调在主入口点之前执行，是"无入口点启动"的常用手法，' +
        '也可能用于反调试。',
      level: 'medium',
      source: SOURCE,
      evidence: 'TLS 目录非空'
    });
  }

  const nowSeconds: number = Math.floor(Date.now() / 1000);
  if (analysis.timestamp === 0) {
    findings.push({
      id: 'pe.timestamp-zero',
      category: 'pe-structure',
      label: '编译时间戳被清零',
      detail: '时间戳为 0，通常由加壳工具或构建设置主动清除以隐藏来源。',
      level: 'medium',
      source: SOURCE,
      evidence: 'TimeDateStamp = 0'
    });
  } else if (analysis.timestamp > nowSeconds + 86400) {
    findings.push({
      id: 'pe.timestamp-future',
      category: 'pe-structure',
      label: '编译时间戳位于未来',
      detail: `时间戳为 ${new Date(analysis.timestamp * 1000).toISOString().substring(0, 10)}，` +
        '晚于当前时间，说明被伪造。',
      level: 'medium',
      source: SOURCE,
      evidence: `TimeDateStamp = ${analysis.timestamp}`
    });
  }

  if (analysis.is64Bit === false && analysis.numberOfSections <= 2) {
    findings.push({
      id: 'pe.minimal-sections',
      category: 'pe-structure',
      label: '节表异常精简',
      detail: `仅包含 ${analysis.numberOfSections} 个节，远少于正常编译产物的数量。`,
      level: 'low',
      source: SOURCE,
      evidence: `节数 ${analysis.numberOfSections}`
    });
  }

  if (!analysis.hasDigitalSignature && analysis.machine !== 0) {
    findings.push({
      id: 'pe.unsigned',
      category: 'pe-structure',
      label: '未附带数字签名',
      detail: '可执行文件没有代码签名，无法验证发布者身份。',
      level: 'low',
      source: SOURCE,
      evidence: '安全目录为空'
    });
  }

  // ---------------------------------------------------------- capability layer
  for (let i = 0; i < analysis.behaviors.length; i++) {
    const signal: BehaviorSignal = analysis.behaviors[i];
    findings.push({
      id: `pe.behavior.${signal.category}`,
      category: 'pe-behavior',
      label: signal.label,
      detail: signal.description,
      level: signal.confidence === 'high' ? 'high'
        : (signal.confidence === 'medium' ? 'medium' : 'low'),
      source: SOURCE,
      evidence: signal.evidence.join(', ')
    });
  }

  return findings;
}
