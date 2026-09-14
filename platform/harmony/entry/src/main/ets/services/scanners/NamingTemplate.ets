/**
 * Doc Shield — ordered naming-rule templates (pure, platform-free).
 *
 * The old checker was four keyword heuristics: "rule mentions 学号 → filename
 * needs 6+ digits", "rule mentions _ → filename needs an underscore". That
 * accepted almost anything — with the rule `学号_姓名_课程名称` the filename
 * `2024001_张三.pdf` passed despite missing a whole segment, and `张三_2024001_
 * 数据结构.pdf` passed despite the segments being in the wrong order.
 *
 * A rule is now parsed into an **ordered template**:
 *
 *     学号_姓名_课程名称      -> [studentId] _ [name] _ [course]
 *     班级-姓名-实验名称.pdf  -> [class] - [name] - [any], extension pdf
 *
 * and a filename is judged by segment count, segment order, each segment's
 * shape, the separator, and the extension. A rule may also *list* its fields
 * (`学号、姓名、课程名称`): list punctuation splits the rule into fields but is
 * never demanded back in the file name. A rule that cannot be read as a
 * template reports `recognised: false` so callers can say "needs manual
 * confirmation" instead of silently passing everything.
 *
 * Behaviour is pinned by platform/contracts/requirement_cases.json, which the
 * Python checker also reads — the two implementations must not drift.
 */

/** Canonical field kinds. `any` only requires a non-empty, non-numeric segment. */
export type NamingKind =
  | 'studentId' | 'name' | 'course' | 'class' | 'major'
  | 'college' | 'title' | 'date' | 'serial' | 'any';

export interface NamingTemplate {
  /** False when the rule could not be read as a template. */
  recognised: boolean;
  /** Separator the filename must contain, `''` when the template has none. */
  separator: string;
  /** One entry per segment, in order. */
  kinds: NamingKind[];
  /** Lower-case extension demanded by the template, `''` when unspecified. */
  extension: string;
  /** Original segment labels, for display. */
  labels: string[];
}

export interface NamingCheckResult {
  /** False when the template was not recognised — nothing was judged. */
  checked: boolean;
  ok: boolean;
  /** Stable codes, asserted as a set by the contract tests. */
  problems: string[];
}

/** Extensions recognised when the template itself ends in one. */
const KNOWN_EXTENSIONS: string[] = [
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx',
  'txt', 'md', 'zip', 'rar', '7z', 'png', 'jpg', 'jpeg'
];

/**
 * Separators accepted inside a file name. Only these can become the separator a
 * template demands, because only these can legitimately appear in a file name.
 */
const FILE_SEPARATORS: string[] = ['_', '-', '\u2014', '\uFF0D'];

/**
 * Separators that additionally delimit fields when a rule *lists* them, e.g.
 * `学号、姓名、课程名称`. They split the rule into fields but never become the
 * demanded separator — nobody writes `2024001、张三、数据结构.pdf`.
 */
const LIST_SEPARATORS: string[] = ['\u3001', '\uFF0C', ',', '+'];

interface KindRule {
  needles: string[];
  kind: NamingKind;
}

/**
 * Ordered label -> kind table. Order matters: `课程名称` must be tested before
 * any generic `课程`, and `学生姓名` must resolve to name rather than being
 * caught by an earlier rule.
 */
const KIND_RULES: KindRule[] = [
  { needles: ['课程名称', '课程名', '课名', '课程'], kind: 'course' },
  { needles: ['学号'], kind: 'studentId' },
  { needles: ['姓名', '名字'], kind: 'name' },
  { needles: ['班级', '班号'], kind: 'class' },
  { needles: ['专业'], kind: 'major' },
  { needles: ['学院'], kind: 'college' },
  { needles: ['论文题目', '论文名', '题目', '标题'], kind: 'title' },
  { needles: ['日期'], kind: 'date' },
  { needles: ['序号', '编号', '版本'], kind: 'serial' }
];

/** Lower-case extension without the dot, `''` when the name has none. */
export function extensionOf(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  if (dot <= 0 || dot === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).toLowerCase();
}

/** Stem of a filename, i.e. everything before the final extension. */
export function stemOf(fileName: string): string {
  const ext: string = extensionOf(fileName);
  if (ext.length === 0) {
    return fileName;
  }
  return fileName.substring(0, fileName.length - ext.length - 1);
}

/** True when `ch` may be demanded as the separator of a file name. */
function isFileSeparator(ch: string): boolean {
  for (let i = 0; i < FILE_SEPARATORS.length; i++) {
    if (FILE_SEPARATORS[i] === ch) {
      return true;
    }
  }
  return false;
}

/** True when `ch` splits fields in a rule or in a file name. */
function isSeparator(ch: string): boolean {
  if (isFileSeparator(ch)) {
    return true;
  }
  for (let i = 0; i < LIST_SEPARATORS.length; i++) {
    if (LIST_SEPARATORS[i] === ch) {
      return true;
    }
  }
  return false;
}

/**
 * Split on any separator run, dropping empties (`a__b` -> `a`, `b`).
 *
 * Dropping is right for the *rule* side — a brief may end with punctuation
 * (`..._课程名称。`) — but it also means a stray separator in a file name would
 * vanish, so `checkNaming` flags those separately via `hasEmptySegment`.
 */
function splitSegments(text: string): string[] {
  const out: string[] = [];
  let current: string = '';
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (isSeparator(ch)) {
      if (current.length > 0) {
        out.push(current);
        current = '';
      }
    } else {
      current += ch;
    }
  }
  if (current.length > 0) {
    out.push(current);
  }
  return out;
}

/**
 * Every *file-name* separator occurring in `text`, in order.
 *
 * Deliberately narrower than `isSeparator`: a rule written as a list
 * (`学号、姓名、课程名称`) must not end up demanding `、` in the file name.
 */
function separatorsIn(text: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (isFileSeparator(ch)) {
      out.push(ch);
    }
  }
  return out;
}

/** Most frequent separator, first-seen wins on a tie. `''` when none. */
function dominantSeparator(found: string[]): string {
  if (found.length === 0) {
    return '';
  }
  let best: string = found[0];
  let bestCount: number = 0;
  for (let i = 0; i < found.length; i++) {
    let count: number = 0;
    for (let j = 0; j < found.length; j++) {
      if (found[j] === found[i]) {
        count++;
      }
    }
    if (count > bestCount) {
      bestCount = count;
      best = found[i];
    }
  }
  return best;
}

/** Classify one template label into a field kind. */
export function classifyLabel(label: string): NamingKind {
  const lower: string = label.trim().toLowerCase();
  for (let i = 0; i < KIND_RULES.length; i++) {
    const rule: KindRule = KIND_RULES[i];
    for (let j = 0; j < rule.needles.length; j++) {
      if (lower.indexOf(rule.needles[j]) >= 0) {
        return rule.kind;
      }
    }
  }
  return 'any';
}

/** True when the string is only digits. Implemented by scan, not regex. */
function isAllDigits(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/**
 * Read a naming rule as an ordered template.
 *
 * A rule counts as a template when it has two or more segments, or a single
 * segment whose label names a concrete field (e.g. `学号`). Rules like
 * `只要一张图片` or `报告` are prose, not templates, and are reported as
 * unrecognised rather than quietly matching everything.
 */
export function parseNamingTemplate(rule: string): NamingTemplate {
  const trimmed: string = rule.trim();
  let body: string = trimmed;
  let extension: string = '';

  const dot: number = trimmed.lastIndexOf('.');
  if (dot > 0) {
    const tail: string = trimmed.substring(dot + 1).toLowerCase();
    if (KNOWN_EXTENSIONS.indexOf(tail) >= 0) {
      extension = tail;
      body = trimmed.substring(0, dot);
    }
  }

  const labels: string[] = splitSegments(body);
  const separator: string = dominantSeparator(separatorsIn(body));
  const kinds: NamingKind[] = [];
  let hasConcreteKind: boolean = false;
  for (let i = 0; i < labels.length; i++) {
    const kind: NamingKind = classifyLabel(labels[i]);
    if (kind !== 'any') {
      hasConcreteKind = true;
    }
    kinds.push(kind);
  }

  const recognised: boolean = labels.length >= 2 || hasConcreteKind;
  const template: NamingTemplate = {
    recognised: recognised,
    separator: recognised ? separator : '',
    kinds: recognised ? kinds : [],
    extension: recognised ? extension : '',
    labels: recognised ? labels : []
  };
  return template;
}

/** True when `segment` looks like the declared kind. */
export function matchesKind(segment: string, kind: NamingKind): boolean {
  const value: string = segment.trim();
  if (value.length === 0) {
    return false;
  }
  if (kind === 'any') {
    return true;
  }
  if (kind === 'studentId') {
    return /^\d{6,20}$/.test(value);
  }
  if (kind === 'name') {
    if (/^[\u4e00-\u9fa5\u00b7]{2,8}$/.test(value)) {
      return true;
    }
    return /^[A-Za-z][A-Za-z .'-]{1,29}$/.test(value);
  }
  if (kind === 'class') {
    return /^[\u4e00-\u9fa5A-Za-z0-9]{2,20}$/.test(value);
  }
  if (kind === 'date') {
    if (/^\d{4}[-./]?\d{2}[-./]?\d{2}$/.test(value)) {
      return true;
    }
    return /^\d{6,8}$/.test(value);
  }
  if (kind === 'serial') {
    return /^[A-Za-z0-9]{1,20}$/.test(value);
  }
  // course / title / major / college: free text, but a bare number is not a name.
  return !isAllDigits(value);
}

/**
 * True when `stem` has an empty field: a leading, trailing or doubled
 * separator, e.g. `_2024001_张三.pdf` or `2024001__张三.pdf`.
 *
 * Without this the stray separator disappears in `splitSegments` and the name
 * is reported as compliant — the same class of false pass the ordered template
 * was introduced to remove.
 */
function hasEmptySegment(stem: string): boolean {
  if (stem.length === 0) {
    return false;
  }
  if (isSeparator(stem.charAt(0)) || isSeparator(stem.charAt(stem.length - 1))) {
    return true;
  }
  for (let i = 1; i < stem.length; i++) {
    if (isSeparator(stem.charAt(i)) && isSeparator(stem.charAt(i - 1))) {
      return true;
    }
  }
  return false;
}

/**
 * Judge a filename against a parsed template.
 *
 * `problems` uses stable codes so the shared contract can assert them:
 * `empty-segment`, `segment-count`, `field:<kind>`, `separator`, `extension`.
 *
 * `empty-segment` and `segment-count` are mutually exclusive: when a separator
 * is stray the segment count is off for a reason already reported, so counting
 * it again would only add noise.
 */
export function checkNaming(fileName: string, template: NamingTemplate): NamingCheckResult {
  if (!template.recognised) {
    const skipped: NamingCheckResult = { checked: false, ok: true, problems: [] };
    return skipped;
  }

  const actualExtension: string = extensionOf(fileName);
  const stem: string = stemOf(fileName);
  const parts: string[] = splitSegments(stem);
  const problems: string[] = [];

  if (hasEmptySegment(stem)) {
    problems.push('empty-segment');
  } else if (parts.length !== template.kinds.length) {
    problems.push('segment-count');
  } else {
    for (let i = 0; i < parts.length; i++) {
      if (!matchesKind(parts[i], template.kinds[i])) {
        problems.push(`field:${template.kinds[i]}`);
      }
    }
  }

  if (template.separator.length > 0 && stem.indexOf(template.separator) < 0) {
    problems.push('separator');
  }
  if (template.extension.length > 0 && actualExtension !== template.extension) {
    problems.push('extension');
  }

  const result: NamingCheckResult = {
    checked: true,
    ok: problems.length === 0,
    problems: problems
  };
  return result;
}

/** Human-readable template summary, e.g. `学号_姓名_课程名称（3 段，分隔符 _）`. */
export function describeTemplate(template: NamingTemplate): string {
  if (!template.recognised) {
    return '';
  }
  const sep: string = template.separator.length > 0 ? template.separator : '无分隔符';
  const ext: string = template.extension.length > 0 ? `，扩展名 .${template.extension}` : '';
  return `${template.labels.join(template.separator.length > 0 ? template.separator : '_')}`
    + `（${template.kinds.length} 段，分隔符 ${sep}${ext}）`;
}

/**
 * Turn problem codes into Chinese advice shown next to the file name.
 * Unknown codes pass through unchanged so nothing is silently dropped.
 */
export function describeProblems(problems: string[], template: NamingTemplate): string[] {
  const out: string[] = [];
  for (let i = 0; i < problems.length; i++) {
    const code: string = problems[i];
    if (code === 'segment-count') {
      out.push(`命名应有 ${template.kinds.length} 段（${template.labels.join(template.separator.length > 0 ? template.separator : '_')}），`
        + '实际段数不符');
    } else if (code === 'empty-segment') {
      out.push('分隔符使用有误（出现了多余、连续或首尾分隔符）');
    } else if (code === 'separator') {
      out.push(`命名规则要求使用「${template.separator}」作为分隔符`);
    } else if (code === 'extension') {
      out.push(`扩展名应为 .${template.extension}`);
    } else if (code.indexOf('field:') === 0) {
      const kind: string = code.substring('field:'.length);
      out.push(`${kindLabel(kind)}段格式不符`);
    } else {
      out.push(code);
    }
  }
  return out;
}

/** Chinese label for a field kind, used in messages. */
export function kindLabel(kind: string): string {
  if (kind === 'studentId') {
    return '学号';
  }
  if (kind === 'name') {
    return '姓名';
  }
  if (kind === 'course') {
    return '课程名称';
  }
  if (kind === 'class') {
    return '班级';
  }
  if (kind === 'major') {
    return '专业';
  }
  if (kind === 'college') {
    return '学院';
  }
  if (kind === 'title') {
    return '题目';
  }
  if (kind === 'date') {
    return '日期';
  }
  if (kind === 'serial') {
    return '序号';
  }
  return '内容';
}
