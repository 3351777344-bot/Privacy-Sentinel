/**
 * L1 — credential and sensitive-information scanner.
 *
 * Runs over any decodable text payload: plain documents, source files and the
 * decompressed members of an archive. Results are deliberately masked so the
 * report never becomes a second copy of the secret it just found.
 */

import { ThreatFinding, ThreatLevel } from '../../models/ThreatModels';

const SOURCE: string = 'RegexScanner';

export interface RegexRule {
  id: string;
  label: string;
  detail: string;
  level: ThreatLevel;
  pattern: string;
  flags: string;
  /** Capture group holding the secret; 0 means the entire match. */
  group: number;
  /** Post-validation hook; see `validateMatch`. */
  validator: string;
  category: 'credential-leak' | 'privacy-leak';
}

const PRIVATE_IP_PREFIXES: string[] = ['10.', '127.', '192.168.', '169.254.', '0.'];
const RESERVED_DOMAINS: string[] = [
  'example.com', 'example.org', 'example.net', 'localhost', 'test.com',
  'invalid', 'domain.com', 'yourcompany.com', 'acme.com'
];

const PLACEHOLDER_TOKENS: string[] = [
  'example', 'sample', 'dummy', 'placeholder', 'changeme', 'change_me',
  'your_', 'yourkey', 'your-key', 'test', 'fake', 'redacted', 'xxx',
  'abcd1234', 'todo', 'none', 'null', 'undefined', 'secret_here', 'insert'
];

export const CREDENTIAL_RULES: RegexRule[] = [
  {
    id: 'cred.aws-access-key',
    label: 'AWS Access Key ID',
    detail: '疑似亚马逊云访问密钥，可用于调用云资源。',
    level: 'high',
    pattern: '\\b(AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.github-token',
    label: 'GitHub 访问令牌',
    detail: '疑似 GitHub 个人令牌或应用令牌，可读写代码仓库。',
    level: 'high',
    pattern: '\\bgh[pousr]_[A-Za-z0-9]{36,255}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.gitlab-token',
    label: 'GitLab 访问令牌',
    detail: '疑似 GitLab 个人访问令牌。',
    level: 'high',
    pattern: '\\bglpat-[A-Za-z0-9_\\-]{20,}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.slack-token',
    label: 'Slack 令牌',
    detail: '疑似 Slack 机器人或用户令牌。',
    level: 'high',
    pattern: '\\bxox[baprs]-[A-Za-z0-9\\-]{10,}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.slack-webhook',
    label: 'Slack Webhook 地址',
    detail: '疑似 Slack 消息推送地址，泄露后可被用于发送钓鱼消息。',
    level: 'medium',
    pattern: 'https://hooks\\.slack\\.com/services/T[A-Za-z0-9_]+/B[A-Za-z0-9_]+/[A-Za-z0-9_]+',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.google-api-key',
    label: 'Google API Key',
    detail: '疑似谷歌云 API 密钥。',
    level: 'high',
    pattern: '\\bAIza[0-9A-Za-z_\\-]{35}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.stripe-key',
    label: 'Stripe 密钥',
    detail: '疑似 Stripe 支付密钥，泄露可能造成资金风险。',
    level: 'high',
    pattern: '\\b(sk|rk)_(live|test)_[A-Za-z0-9]{20,}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.sendgrid-key',
    label: 'SendGrid API Key',
    detail: '疑似邮件发送服务密钥。',
    level: 'high',
    pattern: '\\bSG\\.[A-Za-z0-9_\\-]{22}\\.[A-Za-z0-9_\\-]{43}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.azure-account-key',
    label: 'Azure 存储账户密钥',
    detail: '疑似 Azure 存储连接串中的账户密钥。',
    level: 'high',
    pattern: 'AccountKey=[A-Za-z0-9+/=]{40,}',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.private-key-block',
    label: '私钥文件内容',
    detail: '检测到 PEM 私钥块，泄露后可直接冒用身份。',
    level: 'high',
    pattern: '-----BEGIN[ ](?:(?:RSA|EC|DSA|OPENSSH|PGP|ENCRYPTED)[ ])?PRIVATE KEY(?: BLOCK)?-----',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.putty-key',
    label: 'PuTTY 私钥',
    detail: '检测到 PuTTY 格式私钥文件标注。',
    level: 'high',
    pattern: 'PuTTY-User-Key-File-[0-9]:',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.jwt',
    label: 'JWT 令牌',
    detail: '检测到结构化 JWT，可能包含可复用的登录凭据。',
    level: 'medium',
    pattern: '\\beyJ[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\b',
    flags: 'g',
    group: 0,
    validator: 'jwt',
    category: 'credential-leak'
  },
  {
    id: 'cred.url-basic-auth',
    label: 'URL 内嵌账号密码',
    detail: '链接中直接携带用户名与密码，任何日志都会记录它们。',
    level: 'high',
    pattern: 'https?://[A-Za-z0-9._%+-]+:[^\\s/@:]{4,}@[A-Za-z0-9.-]+',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'credential-leak'
  },
  {
    id: 'cred.generic-assignment',
    label: '疑似硬编码密钥',
    detail: '赋值语句中出现高熵的密钥类字段名。',
    level: 'medium',
    pattern: '\\b(api[_-]?key|apikey|secret[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key|db[_-]?password|db[_-]?passwd)\\b\\s*[:=]\\s*["\']?([A-Za-z0-9_\\-+/=]{16,})["\']?',
    flags: 'gi',
    group: 2,
    validator: 'entropy',
    category: 'credential-leak'
  },
  {
    id: 'cred.password-literal',
    label: '明文口令赋值',
    detail: '密码字段被直接赋值为字符串常量。',
    level: 'medium',
    pattern: '\\b(password|passwd|pwd)\\b\\s*[:=]\\s*["\']([^"\']{6,64})["\']',
    flags: 'gi',
    group: 2,
    validator: 'password',
    category: 'credential-leak'
  }
];

export const PRIVACY_RULES: RegexRule[] = [
  {
    id: 'priv.public-ip',
    label: '公网 IP 地址',
    detail: '文档中出现公网 IP，可能泄露服务器或内网出口地址。',
    level: 'medium',
    pattern: '\\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\b',
    flags: 'g',
    group: 0,
    validator: 'public-ip',
    category: 'privacy-leak'
  },
  {
    id: 'priv.server-path',
    label: '服务器绝对路径',
    detail: '暴露了服务端目录结构，便于攻击者推断部署方式。',
    level: 'medium',
    pattern: '(?:[A-Za-z]:\\\\[A-Za-z0-9_.$ \\\\-]{6,}|/(?:var/www|etc|home|root|opt|srv)/[A-Za-z0-9_./\\-]{3,})',
    flags: 'g',
    group: 0,
    validator: 'server-path',
    category: 'privacy-leak'
  },
  {
    id: 'priv.phpinfo',
    label: 'phpinfo 调试页面地址',
    detail: 'phpinfo 会输出完整环境变量与配置，属高危信息泄露。',
    level: 'high',
    pattern: '\\b(?:phpinfo\\.php|php_info\\(\\)|phpinfo\\s*\\()',
    flags: 'gi',
    group: 0,
    validator: 'none',
    category: 'privacy-leak'
  },
  {
    id: 'priv.db-connection',
    label: '数据库连接信息',
    detail: '包含数据库连接串或账号信息。',
    level: 'high',
    pattern: '(?:(?:jdbc|mongodb|mysql|postgres(?:ql)?|redis|mssql):\\/\\/[^\\s"\']{6,}|(?:db|database)[_-]?(?:user|host|name)\\s*[:=]\\s*\\S{3,})',
    flags: 'gi',
    group: 0,
    validator: 'none',
    category: 'privacy-leak'
  },
  {
    id: 'priv.software-version',
    label: '服务器软件版本',
    detail: '暴露精确版本号，便于攻击者匹配已公开漏洞。',
    level: 'low',
    pattern: '\\b(?:Apache|nginx|PHP|MySQL|MariaDB|OpenSSL|Tengine|Tomcat|IIS|Jetty|WebLogic)/[0-9][0-9A-Za-z._\\-]{1,20}',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'privacy-leak'
  },
  {
    id: 'priv.china-id',
    label: '身份证号',
    detail: '检测到 18 位居民身份证号。',
    level: 'high',
    pattern: '\\b[1-9][0-9]{5}(?:19|20)[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9Xx]\\b',
    flags: 'g',
    group: 0,
    validator: 'china-id',
    category: 'privacy-leak'
  },
  {
    id: 'priv.china-phone',
    label: '手机号',
    detail: '检测到中国大陆手机号码。',
    level: 'medium',
    pattern: '\\b1(?:3[0-9]|4[5-9]|5[0-35-9]|6[2567]|7[0-8]|8[0-9]|9[0-35-9])[0-9]{8}\\b',
    flags: 'g',
    group: 0,
    validator: 'none',
    category: 'privacy-leak'
  },
  {
    id: 'priv.email',
    label: '电子邮箱',
    detail: '文档中包含邮箱地址，可能被用于精准钓鱼。',
    level: 'low',
    pattern: '\\b[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,255}\\.[A-Za-z]{2,24}\\b',
    flags: 'g',
    group: 0,
    validator: 'email',
    category: 'privacy-leak'
  }
];

/** Show just enough of a secret to locate it, never the whole value. */
export function maskSecret(value: string): string {
  if (value.length <= 8) {
    return value.charAt(0) + '***';
  }
  if (value.length <= 16) {
    return `${value.substring(0, 3)}***${value.substring(value.length - 2)}`;
  }
  return `${value.substring(0, 6)}...${value.substring(value.length - 4)}`;
}

function looksLikePlaceholder(value: string): boolean {
  const lower: string = value.toLowerCase();
  for (let i = 0; i < PLACEHOLDER_TOKENS.length; i++) {
    if (lower.indexOf(PLACEHOLDER_TOKENS[i]) >= 0) {
      return true;
    }
  }
  // A single repeated character is filler, not a secret.
  let allSame: boolean = true;
  for (let i = 1; i < value.length; i++) {
    if (value.charAt(i) !== value.charAt(0)) {
      allSame = false;
      break;
    }
  }
  return allSame;
}

/**
 * Whether the documentation-filler filter applies to this rule.
 *
 * It is a question about *secrets*: an AWS key that reads `…EXAMPLE` is a doc
 * sample, and reporting it is noise. Asking the same question of a privacy rule
 * is wrong — an address like `zhangsan@example.edu.cn` is a real finding whose
 * local part merely happens to contain a filler-looking word.
 */
function appliesPlaceholderFilter(rule: RegexRule): boolean {
  return rule.category === 'credential-leak';
}

/** Shannon entropy of a short string, used to reject readable words. */
function shannonBitsPerChar(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  const counts: number[] = [];
  for (let i = 0; i < 256; i++) {
    counts.push(0);
  }
  for (let i = 0; i < value.length; i++) {
    const code: number = value.charCodeAt(i);
    counts[code & 0xFF]++;
  }
  let entropy: number = 0;
  for (let i = 0; i < 256; i++) {
    if (counts[i] === 0) {
      continue;
    }
    const p: number = counts[i] / value.length;
    entropy -= p * (Math.log(p) / Math.LN2);
  }
  return entropy;
}

function isValidChinaId(value: string): boolean {
  const weights: number[] = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  const checks: string = '10X98765432';
  let sum: number = 0;
  for (let i = 0; i < 17; i++) {
    sum += (value.charCodeAt(i) - 48) * weights[i];
  }
  return checks.charAt(sum % 11) === value.charAt(17).toUpperCase();
}

function validateMatch(validator: string, value: string): boolean {
  if (validator === 'none') {
    return true;
  }
  if (validator === 'jwt') {
    // A real JWT header decodes to a JSON object naming an algorithm.
    try {
      const header: string = base64UrlDecode(value.split('.')[0]);
      return header.indexOf('{') >= 0 && header.indexOf('alg') >= 0;
    } catch (error) {
      return false;
    }
  }
  if (validator === 'entropy') {
    return shannonBitsPerChar(value) >= 3.0;
  }
  if (validator === 'password') {
    const lower: string = value.toLowerCase();
    if (lower === 'password' || lower === 'passwd' || lower === '123456' ||
      lower === '12345678' || lower === 'admin' || lower === 'root' ||
      lower === 'qwerty' || lower === 'letmein' || lower === 'changeme') {
      return false;
    }
    return !looksLikePlaceholder(value);
  }
  if (validator === 'public-ip') {
    for (let i = 0; i < PRIVATE_IP_PREFIXES.length; i++) {
      if (value.startsWith(PRIVATE_IP_PREFIXES[i])) {
        return false;
      }
    }
    const firstOctet: number = parseInt(value.split('.')[0], 10);
    // Multicast / reserved / documentation ranges.
    if (firstOctet >= 224) {
      return false;
    }
    if (firstOctet === 198 && (value.startsWith('198.51.') || value.startsWith('198.18.') ||
      value.startsWith('198.19.'))) {
      return false;
    }
    if (value.startsWith('203.0.113.') || value.startsWith('192.0.2.')) {
      return false;
    }
    return true;
  }
  if (validator === 'server-path') {
    // Ignore generic API routes and MIME-ish fragments.
    if (/^\/(?:etc|var\/www|home|root|opt|srv)\/[A-Za-z0-9_.-]{2,}$/.test(value)) {
      return value.indexOf('://') < 0;
    }
    return true;
  }
  if (validator === 'china-id') {
    return isValidChinaId(value);
  }
  if (validator === 'email') {
    const lower: string = value.toLowerCase();
    for (let i = 0; i < RESERVED_DOMAINS.length; i++) {
      if (lower.endsWith(`@${RESERVED_DOMAINS[i]}`) || lower.endsWith(`.${RESERVED_DOMAINS[i]}`)) {
        return false;
      }
    }
    // Reject hex blobs that merely look like `user@host`.
    return !/^[0-9a-f]{16,}@/i.test(value);
  }
  return true;
}

function base64UrlDecode(input: string): string {
  let normalized: string = input.replace(/-/g, '+').replace(/_/g, '/');
  while (normalized.length % 4 !== 0) {
    normalized += '=';
  }
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out: string = '';
  let buffer: number = 0;
  let bits: number = 0;
  for (let i = 0; i < normalized.length; i++) {
    const ch: string = normalized.charAt(i);
    if (ch === '=') {
      break;
    }
    const index: number = alphabet.indexOf(ch);
    if (index < 0) {
      continue;
    }
    buffer = (buffer << 6) | index;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out += String.fromCharCode((buffer >> bits) & 0xFF);
    }
  }
  return out;
}

export interface RegexScanOptions {
  maxPerRule: number;
  maxTotal: number;
}

const DEFAULT_OPTIONS: RegexScanOptions = { maxPerRule: 4, maxTotal: 30 };

function scanWithRules(text: string, rules: RegexRule[], source: string,
  options: RegexScanOptions): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  if (text.length === 0) {
    return findings;
  }

  for (let r = 0; r < rules.length; r++) {
    if (findings.length >= options.maxTotal) {
      break;
    }
    const rule: RegexRule = rules[r];
    const hits: string[] = [];
    let regex: RegExp;
    try {
      regex = new RegExp(rule.pattern, rule.flags);
    } catch (error) {
      continue;
    }
    let match: RegExpExecArray | null = regex.exec(text);
    let guard: number = 0;
    while (match !== null && guard < 512) {
      guard++;
      const raw: string = rule.group > 0 && match.length > rule.group
        ? match[rule.group]
        : match[0];
      let isFiller: boolean = false;
      if (raw !== undefined && raw.length > 0 && appliesPlaceholderFilter(rule)) {
        isFiller = looksLikePlaceholder(raw);
      }
      if (raw !== undefined && raw.length > 0 && !isFiller &&
        validateMatch(rule.validator, raw)) {
        if (hits.indexOf(raw) < 0) {
          hits.push(raw);
        }
      }
      if (hits.length >= options.maxPerRule) {
        break;
      }
      if (regex.lastIndex === match.index) {
        regex.lastIndex++;
      }
      match = regex.exec(text);
    }

    if (hits.length === 0) {
      continue;
    }
    const masked: string[] = [];
    for (let i = 0; i < hits.length; i++) {
      masked.push(maskSecret(hits[i]));
    }
    findings.push({
      id: rule.id,
      category: rule.category,
      label: rule.label,
      detail: `${rule.detail}（发现 ${hits.length} 处）`,
      level: rule.level,
      source: source,
      evidence: masked.join(', ')
    });
  }
  return findings;
}

/** Scan decoded text for credentials and sensitive information. */
export function scanSensitiveText(text: string,
  options: RegexScanOptions = DEFAULT_OPTIONS): ThreatFinding[] {
  const credentials: ThreatFinding[] =
    scanWithRules(text, CREDENTIAL_RULES, SOURCE, options);
  const remaining: number = options.maxTotal - credentials.length;
  if (remaining <= 0) {
    return credentials;
  }
  const privacyOptions: RegexScanOptions = {
    maxPerRule: options.maxPerRule,
    maxTotal: remaining
  };
  const privacy: ThreatFinding[] = scanWithRules(text, PRIVACY_RULES, SOURCE, privacyOptions);
  return credentials.concat(privacy);
}
