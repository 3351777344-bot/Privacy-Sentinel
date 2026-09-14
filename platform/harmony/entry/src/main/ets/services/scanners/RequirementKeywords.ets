/**
 * Doc Shield — local mirror of the server's requirement parser (pure).
 *
 * `parse_requirement()` on the server recognises formats, materials, a naming
 * rule, a length rule and a deadline by keyword. The device needs the same
 * reading of the same text so naming and format checks can run **offline**, with
 * no file upload — those two checks only need the file name, so there is no
 * privacy cost in doing them on device.
 *
 * Everything here is dependency-free (no `@kit.*`, no models) so it runs both on
 * device and under the Node test harness. Naming/format behaviour is pinned by
 * platform/contracts/requirement_cases.json, shared with the Python checker.
 */

import {
  NamingTemplate,
  classifyLabel,
  describeTemplate,
  parseNamingTemplate
} from './NamingTemplate';

export interface RequirementHint {
  /** `ok` when at least one rule will be extracted, `weak` when none will. */
  level: string;
  /** One-line explanation suitable for a status row. */
  message: string;
  /** Human-readable list of what was recognised, e.g. `['PDF','封面','命名规则']`. */
  tags: string[];
}

/** What the local parser read out of the brief. Mirrors the server's schema. */
export interface LocalRequirements {
  /** Server canonical keys, e.g. `['pdf','png']`. */
  formats: string[];
  /** Display labels for the same, e.g. `['PDF','图片']`. */
  formatLabels: string[];
  /** Material keywords, in the server's canonical order. */
  materials: string[];
  /** Raw naming rule text, `''` when the brief states none. */
  namingRule: string;
  /** The naming rule read as an ordered template. */
  namingTemplate: NamingTemplate;
  lengthRequirement: string;
  deadline: string;
}

export interface FormatCheckResult {
  /** Required formats that no uploaded file satisfies. */
  missing: string[];
  /** Uploaded files whose extension is outside the required formats. */
  offList: string[];
}

interface FormatAlias {
  /** Canonical key, identical to the server's `FORMAT_ALIASES` key. */
  canonical: string;
  /** Display label used in messages. */
  label: string;
  aliases: string[];
}

const FORMAT_ALIASES: FormatAlias[] = [
  { canonical: 'pdf', label: 'PDF', aliases: ['pdf'] },
  { canonical: 'docx', label: 'Word', aliases: ['docx', 'word', 'doc'] },
  { canonical: 'zip', label: '压缩包', aliases: ['zip', 'rar', '压缩包'] },
  { canonical: 'png', label: '图片', aliases: ['png', '图片', '截图'] },
  { canonical: 'jpg', label: 'JPG', aliases: ['jpg', 'jpeg'] },
  { canonical: 'txt', label: 'TXT', aliases: ['txt'] },
  { canonical: 'md', label: 'Markdown', aliases: ['md', 'markdown'] },
  { canonical: 'ppt', label: 'PPT', aliases: ['ppt', 'pptx', '演示文稿'] }
];

/**
 * Extensions accepted for each canonical format. Mirrors the server's
 * `FORMAT_EXTENSION_GROUPS`; a format absent from this table accepts itself.
 */
interface ExtensionGroup {
  canonical: string;
  extensions: string[];
}

const EXTENSION_GROUPS: ExtensionGroup[] = [
  { canonical: 'docx', extensions: ['doc', 'docx'] },
  { canonical: 'ppt', extensions: ['ppt', 'pptx'] },
  { canonical: 'zip', extensions: ['zip', 'rar'] }
];

/** Mirrors the server's MATERIAL_KEYWORDS. */
const MATERIAL_KEYWORDS: string[] = [
  '封面', '摘要', '正文', '参考文献', '源码', '源代码',
  '截图', 'PPT', '答辩PPT', '课程论文', '报告', '附件'
];

/**
 * Phrases that introduce a naming rule. Mirrors the server's parser — note that
 * the bundled sample brief says `文件名使用学号_姓名_课程名称`, so plain `文件名`
 * plus `使用`/`须为`/`必须` has to count, otherwise that brief silently yields no
 * naming rule at all.
 */
const NAMING_MARKERS: string[] = [
  '命名规则', '文件命名', '命名格式', '文件名格式', '命名方式', '命名要求',
  '文件名使用', '文件名须为', '文件名应为', '文件名必须', '文件名称为'
];

/** Filler words stripped from the front of a captured naming rule. */
const NAMING_FILLERS: string[] = [
  '必须严格等于', '严格等于', '严格为', '必须为', '必须是', '须为', '应为',
  '等于', '使用', '格式为', '为', '是'
];

/** Markers that make the server extract a length rule (a number must follow). */
const LENGTH_MARKERS: string[] = ['不少于', '不低于', '至少', '约', '控制在', '限制'];

/** Markers that make the server extract a deadline. */
const DEADLINE_MARKERS: string[] = ['截止', '截至', '提交时间', 'deadline'];

function isAsciiWordChar(code: number): boolean {
  const isDigit: boolean = code >= 48 && code <= 57;
  const isLower: boolean = code >= 97 && code <= 122;
  const isUpper: boolean = code >= 65 && code <= 90;
  return isDigit || isLower || isUpper;
}

/**
 * ASCII alias match that refuses to fire inside a longer word, so `doc` does not
 * match `docker` and `md` does not match `cmd`. Implemented as a scan rather
 * than a lookbehind regex because ArkTS is stricter about regex features.
 */
export function containsAlias(lowerText: string, alias: string): boolean {
  if (alias.length === 0) {
    return false;
  }
  const isAsciiWord: boolean = alias.charCodeAt(0) < 128;
  let from: number = 0;
  while (true) {
    const at: number = lowerText.indexOf(alias, from);
    if (at < 0) {
      return false;
    }
    if (!isAsciiWord) {
      return true;
    }
    const before: number = at - 1;
    const after: number = at + alias.length;
    const badBefore: boolean = before >= 0 && isAsciiWordChar(lowerText.charCodeAt(before));
    const badAfter: boolean = after < lowerText.length && isAsciiWordChar(lowerText.charCodeAt(after));
    if (!badBefore && !badAfter) {
      return true;
    }
    from = at + 1;
  }
}

/** True when the text contains any marker (plain substring match). */
export function containsAny(text: string, markers: string[]): boolean {
  for (let i = 0; i < markers.length; i++) {
    if (text.indexOf(markers[i]) >= 0) {
      return true;
    }
  }
  return false;
}

/** True when the text pairs a length marker with a number and a unit. */
export function hasLengthRule(text: string): boolean {
  if (!containsAny(text, LENGTH_MARKERS)) {
    return false;
  }
  const hasNumber: boolean = /[0-9]{1,5}/.test(text);
  const hasUnit: boolean = containsAny(text, ['字', '页', 'word', 'words', 'page', 'pages']);
  return hasNumber && hasUnit;
}

/** True when the text looks like it carries a concrete date. */
export function hasDeadline(text: string): boolean {
  if (containsAny(text, DEADLINE_MARKERS)) {
    return /[0-9]{4}\s*[年/-]\s*[0-9]{1,2}/.test(text)
      || /[0-9]{1,2}\s*月\s*[0-9]{1,2}\s*[日号]/.test(text);
  }
  return /[0-9]{4}\s*年\s*[0-9]{1,2}\s*月\s*[0-9]{1,2}\s*[日号]/.test(text);
}

/** Canonical format keys recognised in the text, e.g. `['pdf','png']`. */
export function recognisedFormats(lowerText: string): string[] {
  const found: string[] = [];
  for (let i = 0; i < FORMAT_ALIASES.length; i++) {
    const entry: FormatAlias = FORMAT_ALIASES[i];
    for (let j = 0; j < entry.aliases.length; j++) {
      if (containsAlias(lowerText, entry.aliases[j].toLowerCase())) {
        found.push(entry.canonical);
        break;
      }
    }
  }
  return found;
}

/** Display labels for a list of canonical format keys. */
export function formatLabelsOf(canonicals: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < canonicals.length; i++) {
    let label: string = canonicals[i].toUpperCase();
    for (let j = 0; j < FORMAT_ALIASES.length; j++) {
      if (FORMAT_ALIASES[j].canonical === canonicals[i]) {
        label = FORMAT_ALIASES[j].label;
        break;
      }
    }
    out.push(label);
  }
  return out;
}

/** Material keywords present in the text, in the server's canonical order. */
export function recognisedMaterials(lowerText: string): string[] {
  const found: string[] = [];
  for (let i = 0; i < MATERIAL_KEYWORDS.length; i++) {
    const keyword: string = MATERIAL_KEYWORDS[i];
    if (lowerText.indexOf(keyword.toLowerCase()) >= 0) {
      found.push(keyword);
    }
  }
  return found;
}

/** Strip filler words and stray punctuation from a captured naming rule. */
function stripNamingFiller(captured: string): string {
  let out: string = captured.trim();
  let changed: boolean = true;
  while (changed && out.length > 0) {
    changed = false;
    const head: string = out.charAt(0);
    if (head === ' ' || head === ':' || head === '：' || head === '　') {
      out = out.substring(1).trim();
      changed = true;
      continue;
    }
    for (let i = 0; i < NAMING_FILLERS.length; i++) {
      const filler: string = NAMING_FILLERS[i];
      if (out.substring(0, filler.length) === filler) {
        out = out.substring(filler.length).trim();
        changed = true;
        break;
      }
    }
  }
  return out;
}

/** Characters that always end a naming rule. */
const NAMING_STOPS: string[] = ['\n', '。', '；', ';'];

/** Comma-like characters: they end a rule unless another field follows. */
const NAMING_LIST_COMMAS: string[] = ['\uFF0C', ','];

/** Earliest index of any rule delimiter, `-1` when there is none. */
function indexOfAnyDelimiter(text: string): number {
  let best: number = -1;
  for (let i = 0; i < NAMING_STOPS.length; i++) {
    const at: number = text.indexOf(NAMING_STOPS[i]);
    if (at >= 0 && (best < 0 || at < best)) {
      best = at;
    }
  }
  for (let i = 0; i < NAMING_LIST_COMMAS.length; i++) {
    const at: number = text.indexOf(NAMING_LIST_COMMAS[i]);
    if (at >= 0 && (best < 0 || at < best)) {
      best = at;
    }
  }
  return best;
}

/** True when `ch` is a comma-like character. */
function isListComma(ch: string): boolean {
  for (let i = 0; i < NAMING_LIST_COMMAS.length; i++) {
    if (NAMING_LIST_COMMAS[i] === ch) {
      return true;
    }
  }
  return false;
}

/**
 * Read the rule out of everything that follows a marker.
 *
 * `。`/`；`/newline always end it. A comma ends it too — unless the chunk after
 * the comma is another field label, because a brief may *list* the fields that
 * way (`文件名使用学号，姓名，课程名称`). Without that look-ahead the rule would
 * be read as just `学号` and every correctly named file would then be reported
 * as having the wrong segment count.
 */
function collectRule(rest: string): string {
  let remaining: string = rest;
  let kept: string = '';
  for (let guard = 0; guard < 12; guard++) {
    const at: number = indexOfAnyDelimiter(remaining);
    if (at < 0) {
      kept += remaining;
      break;
    }
    const delimiter: string = remaining.charAt(at);
    const head: string = remaining.substring(0, at);
    if (!isListComma(delimiter)) {
      kept += head;
      break;
    }
    const tail: string = remaining.substring(at + 1);
    const nextAt: number = indexOfAnyDelimiter(tail);
    const chunk: string = (nextAt >= 0 ? tail.substring(0, nextAt) : tail).trim();
    if (chunk.length > 0 && classifyLabel(chunk) !== 'any') {
      kept += `${head}\uFF0C`;
      remaining = tail;
      continue;
    }
    kept += head;
    break;
  }
  return stripNamingFiller(kept);
}

/**
 * Extract the raw naming rule, `''` when the brief states none.
 *
 * The two patterns mirror the server: an explicit marker followed by the rule,
 * or `按/按照/以 <...> 命名`.
 */
export function extractNamingRule(text: string): string {
  for (let i = 0; i < NAMING_MARKERS.length; i++) {
    const marker: string = NAMING_MARKERS[i];
    const at: number = text.indexOf(marker);
    if (at < 0) {
      continue;
    }
    const cleaned: string = collectRule(text.substring(at + marker.length));
    if (cleaned.length > 0) {
      return cleaned;
    }
  }

  // `按照/按/以 <evidence> 命名`
  const byAt: number = Math.max(
    text.lastIndexOf('按照'), Math.max(text.lastIndexOf('按'), text.lastIndexOf('以'))
  );
  if (byAt >= 0) {
    const tail: string = text.substring(byAt);
    const named: number = tail.indexOf('命名');
    if (named > 0) {
      let middle: string = tail.substring(0, named);
      const lead: number = Math.max(middle.indexOf('按'), middle.indexOf('以'));
      if (lead >= 0) {
        middle = middle.substring(lead + 1);
      }
      const cleaned: string = stripNamingFiller(middle);
      if (cleaned.length > 0) {
        return cleaned;
      }
    }
  }
  return '';
}

/** Read the whole brief the same way the server's `parse_requirement()` does. */
export function parseRequirement(text: string): LocalRequirements {
  const trimmed: string = text.trim();
  const lower: string = trimmed.toLowerCase();
  const formats: string[] = recognisedFormats(lower);
  const namingRule: string = extractNamingRule(trimmed);

  const result: LocalRequirements = {
    formats: formats,
    formatLabels: formatLabelsOf(formats),
    materials: recognisedMaterials(lower),
    namingRule: namingRule,
    namingTemplate: parseNamingTemplate(namingRule),
    lengthRequirement: hasLengthRule(trimmed) ? trimmed : '',
    deadline: hasDeadline(trimmed) ? trimmed : ''
  };
  return result;
}

/** Accepted extensions for a canonical format; a format accepts itself by default. */
function acceptedExtensions(canonical: string): string[] {
  for (let i = 0; i < EXTENSION_GROUPS.length; i++) {
    if (EXTENSION_GROUPS[i].canonical === canonical) {
      return EXTENSION_GROUPS[i].extensions;
    }
  }
  return [canonical];
}

/** Lower-case extension without the dot, `''` when the name has none. */
export function fileExtension(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  if (dot <= 0 || dot === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).toLowerCase();
}

/**
 * Check uploaded file names against the required formats. Needs only the names,
 * which is why this can run on device without touching file content.
 */
export function checkFormats(formats: string[], fileNames: string[]): FormatCheckResult {
  const missing: string[] = [];
  const offList: string[] = [];
  if (formats.length === 0) {
    const none: FormatCheckResult = { missing: [], offList: [] };
    return none;
  }

  const allowed: string[] = [];
  for (let i = 0; i < formats.length; i++) {
    const accepted: string[] = acceptedExtensions(formats[i]);
    for (let j = 0; j < accepted.length; j++) {
      if (allowed.indexOf(accepted[j]) < 0) {
        allowed.push(accepted[j]);
      }
    }
    let satisfied: boolean = false;
    for (let k = 0; k < fileNames.length; k++) {
      if (accepted.indexOf(fileExtension(fileNames[k])) >= 0) {
        satisfied = true;
        break;
      }
    }
    if (!satisfied) {
      missing.push(formats[i]);
    }
  }

  for (let i = 0; i < fileNames.length; i++) {
    if (allowed.indexOf(fileExtension(fileNames[i])) < 0) {
      offList.push(fileNames[i]);
    }
  }

  const result: FormatCheckResult = { missing: missing, offList: offList };
  return result;
}

const WEAK_MESSAGE: string =
  '这段文字里没有可识别的格式、材料、命名或字数关键字，服务端只会给出'
  + '「未识别到明确材料清单」等通用结论。想触发具体检查，请写入 '
  + 'PDF/Word/压缩包、封面/正文/参考文献/源码/截图/PPT、命名规则：学号_姓名、'
  + '不少于 3000 字、截止 2026年12月31日 这类原词。';

/** Advisory pre-check of a submission brief. */
export function precheck(text: string): RequirementHint {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    const empty: RequirementHint = {
      level: 'weak',
      message: '提交要求为空，无法进行完整性比对。',
      tags: []
    };
    return empty;
  }

  const parsed: LocalRequirements = parseRequirement(trimmed);
  const tags: string[] = [];
  for (let i = 0; i < parsed.formatLabels.length; i++) {
    tags.push(parsed.formatLabels[i]);
  }
  for (let i = 0; i < parsed.materials.length; i++) {
    if (tags.indexOf(parsed.materials[i]) < 0) {
      tags.push(parsed.materials[i]);
    }
  }

  // A naming rule is only useful if it reads as a template; say so explicitly,
  // because a recognised-but-empty rule used to pass every file silently.
  let namingNote: string = '';
  if (parsed.namingRule.length > 0) {
    if (parsed.namingTemplate.recognised) {
      tags.push('命名规则');
      namingNote = ` 端内可校验的命名模板：${describeTemplate(parsed.namingTemplate)}。`;
    } else {
      namingNote = ` 命名规则「${parsed.namingRule}」无法解析为可校验的模板，`
        + '只会提示人工确认；写成 学号_姓名_课程名称 这样的分段模板才能自动校验。';
    }
  }

  if (hasLengthRule(trimmed)) {
    tags.push('字数/页数');
  }
  if (hasDeadline(trimmed)) {
    tags.push('截止时间');
  }

  if (tags.length === 0 && namingNote.length === 0) {
    const weak: RequirementHint = {
      level: 'weak',
      message: WEAK_MESSAGE,
      tags: []
    };
    return weak;
  }

  if (tags.length === 0) {
    const weak: RequirementHint = {
      level: 'weak',
      message: namingNote.trim(),
      tags: []
    };
    return weak;
  }

  const ok: RequirementHint = {
    level: 'ok',
    message: `已识别 ${tags.length} 类要求：${tags.join('、')}。${namingNote}`,
    tags: tags
  };
  return ok;
}
