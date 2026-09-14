/**
 * L1 — PDF structural analysis (pdfid-style keyword census).
 *
 * A PDF is not scanned for meaning, it is scanned for *capability declarations*.
 * Each risky keyword in the object graph names something the reader may be
 * asked to do — run JavaScript, open a URL, launch a program, decode with a
 * historically vulnerable codec. Counting those declarations, plus looking for
 * high-entropy streams hiding them, gives a reliable risk picture without
 * implementing a full PDF parser.
 */

import { ThreatFinding } from '../../models/ThreatModels';
import { shannonEntropy } from './EntropyScan';
import { decodeTextPayload } from './TextExtract';

const SOURCE: string = 'PdfAnalyzer';

interface PdfKeyword {
  token: string;
  label: string;
  detail: string;
  level: 'high' | 'medium' | 'low' | 'info';
  category: 'dangerous-script' | 'pe-structure' | 'entropy' | 'ioc';
}

const KEYWORDS: PdfKeyword[] = [
  {
    token: '/javascript', label: '内嵌 JavaScript',
    detail: 'PDF 内嵌脚本，打开文档即可执行。',
    level: 'high', category: 'dangerous-script'
  },
  {
    token: '/js', label: '脚本动作',
    detail: '指向 JavaScript 动作对象。',
    level: 'high', category: 'dangerous-script'
  },
  {
    token: '/openaction', label: '打开时自动动作',
    detail: '文档打开时自动触发，无需用户点击。',
    level: 'high', category: 'dangerous-script'
  },
  {
    token: '/aa', label: '附加动作',
    detail: '在翻页、关闭等事件上挂载动作。',
    level: 'high', category: 'dangerous-script'
  },
  {
    token: '/launch', label: '启动外部程序',
    detail: '尝试调用本地程序打开目标，属最高风险动作。',
    level: 'high', category: 'dangerous-script'
  },
  {
    token: '/submitform', label: '自动提交表单',
    detail: '把表单数据发往外部地址，常用于窃取填写内容。',
    level: 'high', category: 'dangerous-script'
  },
  {
    token: '/jbig2decode', label: 'JBIG2 解码器',
    detail: '该解码器历史漏洞密集（如 CVE-2021-30860）。',
    level: 'high', category: 'pe-structure'
  },
  {
    token: '/embeddedfile', label: '内嵌文件',
    detail: '文档中附带其他文件，可能藏有可执行载荷。',
    level: 'high', category: 'pe-structure'
  },
  {
    token: '/richmedia', label: '富媒体对象',
    detail: 'Flash / 视频嵌入，历史上是主要漏洞入口。',
    level: 'high', category: 'pe-structure'
  },
  {
    token: '/flash', label: 'Flash 内容',
    detail: 'PDF 内嵌 Flash，属高风险历史技术。',
    level: 'high', category: 'pe-structure'
  },
  {
    token: '/goto', label: '远程跳转',
    detail: '跳转到其他 PDF 或远程文档，可用于跟踪与钓鱼。',
    level: 'medium', category: 'ioc'
  },
  {
    token: '/xfa', label: 'XFA 表单',
    detail: 'XML 表单可被滥用为脚本载体。',
    level: 'medium', category: 'dangerous-script'
  },
  {
    token: '/acroform', label: '交互表单',
    detail: '配合提交动作时可用于窃取填写内容。',
    level: 'medium', category: 'pe-structure'
  },
  {
    token: '/encrypt', label: '文档加密',
    detail: '加密会隐藏对象内容，使静态检查失效。',
    level: 'medium', category: 'pe-structure'
  },
  {
    token: '/objstm', label: '对象流压缩',
    detail: '对象被压缩存储，常规关键字扫描可能漏看内部对象。',
    level: 'medium', category: 'pe-structure'
  },
  {
    token: '/uri', label: '外部链接',
    detail: '文档中包含可点击或自动访问的网址。',
    level: 'low', category: 'ioc'
  },
  {
    token: '/javascript', label: 'JavaScript 引用',
    detail: '存在 JavaScript 名称对象。',
    level: 'medium', category: 'dangerous-script'
  },
  {
    token: '/richmedia', label: 'RichMedia',
    detail: '富媒体注解。',
    level: 'medium', category: 'pe-structure'
  }
];

export interface PdfAnalysis {
  isPdf: boolean;
  version: string;
  keywordCounts: Map<string, number>;
  pageCount: number;
  hasEncryption: boolean;
  hasJavaScript: boolean;
  hasAutoAction: boolean;
  streamCount: number;
  encryptedStreamCount: number;
  overallEntropy: number;
  /** Highest entropy seen in a decoded-looking stream. */
  maxStreamEntropy: number;
  /** Uncompressed script bodies lifted out of the file. */
  embeddedScript: string;
  findings: ThreatFinding[];
}

/** True when the buffer starts with the `%PDF-` header. */
export function isPdfFile(data: Uint8Array): boolean {
  if (data.length < 5) {
    return false;
  }
  return data[0] === 0x25 && data[1] === 0x50 && data[2] === 0x44 && data[3] === 0x46 &&
    data[4] === 0x2D;
}

/**
 * Does the token appear as a real PDF key rather than inside text?
 * PDF keys are delimited by whitespace or a delimiter character.
 */
function isDelimitedBy(haystack: string, index: number, tokenLength: number): boolean {
  const before: number = index === 0 ? 32 : haystack.charCodeAt(index - 1);
  const afterIndex: number = index + tokenLength;
  const after: number = afterIndex >= haystack.length ? 32 : haystack.charCodeAt(afterIndex);
  return isPdfDelimiter(before) && isPdfDelimiter(after);
}

function isPdfDelimiter(code: number): boolean {
  // PDF whitespace: 0,9,10,12,13,32. Delimiters: ( ) < > [ ] { } / %
  if (code === 0 || code === 9 || code === 10 || code === 12 || code === 13 || code === 32) {
    return true;
  }
  if (code === 0x28 || code === 0x29 || code === 0x3C || code === 0x3E) {
    return true;
  }
  if (code === 0x5B || code === 0x5D || code === 0x7B || code === 0x7D) {
    return true;
  }
  return code === 0x2F || code === 0x25;
}

function countDelimited(lower: string, token: string, cap: number): number {
  let count: number = 0;
  let from: number = 0;
  while (count < cap) {
    const index: number = lower.indexOf(token, from);
    if (index < 0) {
      break;
    }
    if (isDelimitedBy(lower, index, token.length)) {
      count++;
    }
    from = index + 1;
  }
  return count;
}

/** Extract `stream ... endstream` bodies that are already plain text. */
function extractPlainStreams(data: Uint8Array, limit: number): string {
  let out: string = '';
  const needle: number[] = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6D]; // 'stream'
  let offset: number = 0;
  while (offset < data.length && out.length < limit) {
    const start: number = indexOfBytes(data, needle, offset);
    if (start < 0) {
      break;
    }
    let bodyStart: number = start + needle.length;
    if (bodyStart < data.length && data[bodyStart] === 0x0D) {
      bodyStart++;
    }
    if (bodyStart < data.length && data[bodyStart] === 0x0A) {
      bodyStart++;
    }
    const end: number = indexOfBytes(data, [0x65, 0x6E, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D], bodyStart);
    if (end < 0) {
      break;
    }
    const body: Uint8Array = data.subarray(bodyStart, end);
    if (body.length > 0 && body.length < 256 * 1024) {
      const text: string = decodeTextPayload(body);
      if (text.length > 0 && looksScriptish(text)) {
        out += text;
        out += '\n';
      }
    }
    offset = end + 9;
  }
  return out;
}

function looksScriptish(text: string): boolean {
  const lower: string = text.toLowerCase();
  const markers: string[] = [
    'this.', 'app.', 'eval(', 'function', 'var ', 'new ', 'typeof',
    'util.', 'global', 'openaction', 'submitform'
  ];
  let hits: number = 0;
  for (let i = 0; i < markers.length; i++) {
    if (lower.indexOf(markers[i]) >= 0) {
      hits++;
    }
  }
  return hits >= 2;
}

function isPdfWhitespaceByte(byte: number): boolean {
  return byte === 0x00 || byte === 0x09 || byte === 0x0A || byte === 0x0C ||
    byte === 0x0D || byte === 0x20;
}

/**
 * Read a PDF literal string starting at `openParenIndex`.
 *
 * PDF literal strings escape `(`, `)` and `\` with a backslash and may nest
 * parentheses, so a depth counter is required rather than a search for the
 * next `)`.
 */
function extractLiteralAt(data: Uint8Array, openParenIndex: number,
  maxLength: number): string {
  let depth: number = 1;
  const bytes: number[] = [];
  for (let i = openParenIndex + 1; i < data.length && bytes.length < maxLength; i++) {
    const b: number = data[i];
    if (b === 0x5C) {
      const next: number = i + 1 < data.length ? data[i + 1] : 0;
      if (next === 0x6E) {
        bytes.push(0x0A);
      } else if (next === 0x72) {
        bytes.push(0x0D);
      } else if (next === 0x74) {
        bytes.push(0x09);
      } else if (next === 0x62) {
        bytes.push(0x08);
      } else if (next === 0x66) {
        bytes.push(0x0C);
      } else {
        bytes.push(next);
      }
      i++;
      continue;
    }
    if (b === 0x28) {
      depth++;
      bytes.push(b);
      continue;
    }
    if (b === 0x29) {
      depth--;
      if (depth === 0) {
        break;
      }
      bytes.push(b);
      continue;
    }
    bytes.push(b);
  }
  return decodeTextPayload(new Uint8Array(bytes));
}

/**
 * Collect script bodies held as `/JS (...)` literals.
 *
 * Uncompressed PDFs commonly carry their JavaScript this way rather than in a
 * stream, and skipping this case would miss exactly the simple, hand-crafted
 * documents that are easiest for an attacker to produce.
 */
function extractInlineScripts(data: Uint8Array, limit: number): string {
  let out: string = '';
  // PDF keys are case-sensitive in the spec but appear in the wild in both
  // casings, so every variant is searched rather than normalising the buffer.
  const tokens: string[] = ['/JavaScript', '/javascript', '/JS', '/js'];
  for (let t = 0; t < tokens.length; t++) {
    const needle: number[] = [];
    for (let c = 0; c < tokens[t].length; c++) {
      needle.push(tokens[t].charCodeAt(c));
    }
    let from: number = 0;
    let guard: number = 0;
    while (guard < 64 && out.length < limit) {
      guard++;
      const index: number = indexOfBytes(data, needle, from);
      if (index < 0) {
        break;
      }
      // A key must be followed by a delimiter, not continue a longer name.
      const afterIndex: number = index + needle.length;
      if (afterIndex < data.length && !isPdfWhitespaceByte(data[afterIndex]) &&
        data[afterIndex] !== 0x28 && data[afterIndex] !== 0x2F) {
        from = index + 1;
        continue;
      }
      let cursor: number = afterIndex;
      while (cursor < data.length && isPdfWhitespaceByte(data[cursor])) {
        cursor++;
      }
      if (cursor < data.length && data[cursor] === 0x28) {
        const literal: string = extractLiteralAt(data, cursor, limit - out.length);
        if (literal.length > 0 && looksScriptish(literal)) {
          out += literal;
          out += '\n';
        }
      }
      from = index + 1;
    }
  }
  return out;
}

function indexOfBytes(haystack: Uint8Array, needle: number[], from: number): number {
  if (needle.length === 0 || haystack.length < needle.length) {
    return -1;
  }
  const limit: number = haystack.length - needle.length;
  for (let i = Math.max(0, from); i <= limit; i++) {
    let matched: boolean = true;
    for (let k = 0; k < needle.length; k++) {
      if (haystack[i + k] !== needle[k]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }
  return -1;
}

export function analyzePdf(data: Uint8Array): PdfAnalysis {
  const empty: PdfAnalysis = {
    isPdf: false, version: '', keywordCounts: new Map<string, number>(),
    pageCount: 0, hasEncryption: false, hasJavaScript: false, hasAutoAction: false,
    streamCount: 0, encryptedStreamCount: 0, overallEntropy: 0, maxStreamEntropy: 0,
    embeddedScript: '', findings: []
  };
  if (!isPdfFile(data)) {
    return empty;
  }

  // Work on a Latin-1 reading of the head plus tail; PDF keys are ASCII.
  const header: string = decodeTextPayload(data.subarray(0, Math.min(data.length, 4096)));
  const versionMatch: RegExpMatchArray | null = header.match(/%PDF-([0-9]\.[0-9])/);
  const version: string = versionMatch !== null && versionMatch.length > 1 ? versionMatch[1] : '';

  const probe: string = decodeTextPayload(
    data.subarray(0, Math.min(data.length, 8 * 1024 * 1024))
  ).toLowerCase();

  const counts: Map<string, number> = new Map<string, number>();
  const seenTokens: string[] = [];
  for (let i = 0; i < KEYWORDS.length; i++) {
    const token: string = KEYWORDS[i].token;
    if (seenTokens.indexOf(token) >= 0) {
      continue;
    }
    seenTokens.push(token);
    const count: number = countDelimited(probe, token, 500);
    if (count > 0) {
      counts.set(token, count);
    }
  }

  const pageCount: number = countDelimited(probe, '/page', 2000);
  const streamCount: number = countDelimited(probe, 'stream', 500);
  const flateCount: number = countDelimited(probe, '/flatedecode', 500);
  const hasEncryption: boolean = counts.has('/encrypt');
  const hasJavaScript: boolean = counts.has('/javascript') || counts.has('/js');
  const hasAutoAction: boolean = counts.has('/openaction') || counts.has('/aa');

  const embeddedScript: string = extractPlainStreams(data, 128 * 1024) +
    extractInlineScripts(data, 128 * 1024);

  // ------------------------------------------------------------------ findings
  const findings: ThreatFinding[] = [];

  for (let i = 0; i < KEYWORDS.length; i++) {
    const keyword: PdfKeyword = KEYWORDS[i];
    const count: number = counts.get(keyword.token) ?? 0;
    if (count === 0) {
      continue;
    }
    findings.push({
      id: `pdf.keyword.${keyword.token.substring(1)}`,
      category: keyword.category,
      label: keyword.label,
      detail: `${keyword.detail}（出现 ${count} 次）`,
      level: keyword.level,
      source: SOURCE,
      evidence: `${keyword.token} x${count}`
    });
  }

  if (hasJavaScript && flateCount > 0) {
    findings.push({
      id: 'pdf.compressed-script',
      category: 'dangerous-script',
      label: '脚本被压缩存储',
      detail: '文档使用了 FlateDecode 压缩并包含脚本，脚本内容需解压后才能阅读，' +
        '常用于躲避文本检测。',
      level: 'high',
      source: SOURCE,
      evidence: `FlateDecode x${flateCount}`
    });
  }

  if (hasEncryption && (hasJavaScript || hasAutoAction)) {
    findings.push({
      id: 'pdf.encrypted-with-actions',
      category: 'pe-structure',
      label: '加密文档同时包含自动动作',
      detail: '文档既加密又挂载了自动动作，静态检查无法覆盖其真实行为。',
      level: 'high',
      source: SOURCE,
      evidence: 'Encrypt + OpenAction/AA'
    });
  }

  if (embeddedScript.length > 0) {
    findings.push({
      id: 'pdf.inline-script',
      category: 'dangerous-script',
      label: '提取到内联脚本正文',
      detail: '从文档流中还原出脚本内容，交由脚本规则进一步判定。',
      level: 'medium',
      source: SOURCE,
      evidence: `${embeddedScript.length} 字符`
    });
  }

  let maxStreamEntropy: number = 0;
  let highEntropyStreams: number = 0;
  const streamNeedle: number[] = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6D];
  let cursor: number = 0;
  let guard: number = 0;
  while (guard < 200) {
    guard++;
    const start: number = indexOfBytes(data, streamNeedle, cursor);
    if (start < 0) {
      break;
    }
    const bodyStart: number = start + 6;
    const end: number = indexOfBytes(data, [0x65, 0x6E, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D], bodyStart);
    if (end < 0) {
      break;
    }
    const length: number = end - bodyStart;
    if (length >= 512) {
      const entropy: number = shannonEntropy(data, bodyStart, end);
      if (entropy > maxStreamEntropy) {
        maxStreamEntropy = entropy;
      }
      if (entropy >= 7.9) {
        highEntropyStreams++;
      }
    }
    cursor = end + 9;
  }

  if (highEntropyStreams >= 3) {
    findings.push({
      id: 'pdf.encrypted-streams',
      category: 'entropy',
      label: '存在多个高熵数据流',
      detail: `检测到 ${highEntropyStreams} 个接近随机分布的数据流，` +
        '可能是加密载荷或嵌套容器。',
      level: 'medium',
      source: SOURCE,
      evidence: `高熵流 ${highEntropyStreams} 个，最高熵 ${maxStreamEntropy.toFixed(2)}`
    });
  }

  if (pageCount === 0 && streamCount > 0) {
    findings.push({
      id: 'pdf.no-page-tree',
      category: 'pe-structure',
      label: '缺少页面树',
      detail: '文档包含数据流却没有页面对象，结构异常，可能是伪装的容器。',
      level: 'medium',
      source: SOURCE,
      evidence: `流 ${streamCount} 个`
    });
  }

  return {
    isPdf: true,
    version: version,
    keywordCounts: counts,
    pageCount: pageCount,
    hasEncryption: hasEncryption,
    hasJavaScript: hasJavaScript,
    hasAutoAction: hasAutoAction,
    streamCount: streamCount,
    encryptedStreamCount: highEntropyStreams,
    overallEntropy: shannonEntropy(data, 0, data.length),
    maxStreamEntropy: maxStreamEntropy,
    embeddedScript: embeddedScript,
    findings: findings
  };
}
