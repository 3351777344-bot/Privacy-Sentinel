/**
 * L1 — indicator-of-compromise extraction and reputation heuristics.
 *
 * Pulls host names, addresses and URLs out of a payload and grades the ones
 * that live on infrastructure almost exclusively used for abuse: dynamic DNS,
 * throw-away paste / file-drop services, raw-IP URLs, punycode lookalikes,
 * onion services and chat-app webhooks. The extracted set is also surfaced to
 * the report so the user can see exactly what the file was pointing at.
 */

import { ThreatFinding } from '../../models/ThreatModels';

const SOURCE: string = 'IocExtractor';

/** Providers whose entire purpose is short-lived, hard-to-trace hosting. */
const DYNAMIC_DNS_SUFFIXES: string[] = [
  'duckdns.org', 'no-ip.org', 'noip.com', 'ddns.net', 'dyndns.org', 'hopto.org',
  'zapto.org', 'sytes.net', 'myftp.biz', 'myvnc.com', 'redirectme.net',
  'servebeer.com', 'servehttp.com', 'serveftp.com', 'dynu.net', 'freeddns.org',
  'ngrok.io', 'ngrok-free.app', 'ngrok.app', 'trycloudflare.com', 'loca.lt',
  'serveo.net', 'localtunnel.me', 'pagekite.me', 'telebit.io', 'portmap.io'
];

const PASTE_AND_DROP_SUFFIXES: string[] = [
  'pastebin.com', 'paste.ee', 'hastebin.com', 'ghostbin.co', 'pastebin.pl',
  'paste.gg', 'termbin.com', 'transfer.sh', 'anonfiles.com', 'file.io',
  'gofile.io', 'uguu.se', 'catbox.moe', '0x0.st', 'temp.sh', 'oshi.at',
  'mega.nz', 'mediafire.com', 'sendspace.com', 'bayfiles.com', 'racaty.net'
];

const SHORTENER_DOMAINS: string[] = [
  'bit.ly', 't.co', 'tinyurl.com', 'goo.gl', 'ow.ly', 'is.gd', 'buff.ly',
  'adf.ly', 'shorte.st', 'rb.gy', 'cutt.ly', 'rebrand.ly', 'tiny.cc',
  'shorturl.at', 's.id', 't.cn', 'dwz.cn', 'urlz.fr', 'bl.ink'
];

const ABUSE_TLDS: string[] = [
  '.tk', '.ml', '.ga', '.cf', '.gq', '.top', '.xyz', '.click', '.work',
  '.link', '.gdn', '.stream', '.download', '.racing', '.loan', '.review',
  '.win', '.bid', '.accountant', '.men', '.bar'
];

export interface IocSet {
  domains: string[];
  ipv4: string[];
  ipv6: string[];
  urls: string[];
  emails: string[];
  hashes: string[];
  wallets: string[];
  /** Distinct indicator count, for the report header. */
  total: number;
}

const MAX_PER_KIND: number = 60;

function collect(text: string, pattern: string, flags: string, cap: number): string[] {
  const out: string[] = [];
  let regex: RegExp;
  try {
    regex = new RegExp(pattern, flags);
  } catch (error) {
    return out;
  }
  let match: RegExpExecArray | null = regex.exec(text);
  let guard: number = 0;
  while (match !== null && guard < 4096) {
    guard++;
    const value: string = match.length > 1 && match[1] !== undefined ? match[1] : match[0];
    if (out.indexOf(value) < 0) {
      out.push(value);
    }
    if (out.length >= cap) {
      break;
    }
    if (regex.lastIndex === match.index) {
      regex.lastIndex++;
    }
    match = regex.exec(text);
  }
  return out;
}

function isPrivateIpv4(value: string): boolean {
  if (value.startsWith('10.') || value.startsWith('127.') ||
    value.startsWith('169.254.') || value.startsWith('0.')) {
    return true;
  }
  if (value.startsWith('192.168.')) {
    return true;
  }
  if (value.startsWith('172.')) {
    const second: number = parseInt(value.split('.')[1], 10);
    return second >= 16 && second <= 31;
  }
  if (value.startsWith('100.')) {
    const second: number = parseInt(value.split('.')[1], 10);
    return second >= 64 && second <= 127;
  }
  const first: number = parseInt(value.split('.')[0], 10);
  return first >= 224;
}

function endsWithAny(value: string, suffixes: string[]): string {
  const lower: string = value.toLowerCase();
  for (let i = 0; i < suffixes.length; i++) {
    const suffix: string = suffixes[i];
    if (lower === suffix || lower.endsWith(`.${suffix}`)) {
      return suffix;
    }
  }
  return '';
}

function isValidDomain(value: string): boolean {
  if (value.length < 4 || value.length > 253) {
    return false;
  }
  if (value.indexOf('.') < 0) {
    return false;
  }
  // Reject version-like and filename-like tokens.
  if (/^[0-9.]+$/.test(value)) {
    return false;
  }
  if (/\.(?:png|jpg|jpeg|gif|svg|css|js|json|html|htm|txt|md|xml|woff2?|ttf|ico|map)$/i.test(value)) {
    return false;
  }
  return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/i.test(value);
}

/** Extract every indicator kind from a decoded text payload. */
export function extractIocs(text: string): IocSet {
  const empty: IocSet = {
    domains: [], ipv4: [], ipv6: [], urls: [],
    emails: [], hashes: [], wallets: [], total: 0
  };
  if (text.length === 0) {
    return empty;
  }
  // Bound the work on very large payloads; indicators cluster early anyway.
  const scope: string = text.length > 2 * 1024 * 1024 ? text.substring(0, 2 * 1024 * 1024) : text;

  const urls: string[] = collect(
    scope,
    '\\bhttps?://[A-Za-z0-9._~:/?#\\[\\]@!$&\'()*+,;=%-]{4,300}',
    'gi',
    MAX_PER_KIND
  );

  const rawDomains: string[] = collect(
    scope,
    '\\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+(?:[a-z]{2,24})\\b',
    'gi',
    MAX_PER_KIND * 3
  );
  const domains: string[] = [];
  for (let i = 0; i < rawDomains.length; i++) {
    const candidate: string = rawDomains[i].toLowerCase();
    if (isValidDomain(candidate) && domains.indexOf(candidate) < 0) {
      domains.push(candidate);
    }
    if (domains.length >= MAX_PER_KIND) {
      break;
    }
  }

  const rawIpv4: string[] = collect(
    scope,
    '\\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\b',
    'g',
    MAX_PER_KIND * 2
  );
  const ipv4: string[] = [];
  for (let i = 0; i < rawIpv4.length; i++) {
    const candidate: string = rawIpv4[i];
    if (!isPrivateIpv4(candidate) && ipv4.indexOf(candidate) < 0) {
      ipv4.push(candidate);
    }
    if (ipv4.length >= MAX_PER_KIND) {
      break;
    }
  }

  const ipv6: string[] = collect(
    scope,
    '\\b(?:[0-9a-fA-F]{1,4}:){2,7}(?:[0-9a-fA-F]{1,4})?\\b',
    'g',
    20
  );

  const emails: string[] = collect(
    scope,
    '\\b[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,200}\\.[A-Za-z]{2,24}\\b',
    'gi',
    MAX_PER_KIND
  );

  const hashes: string[] = collect(
    scope,
    '\\b[a-fA-F0-9]{64}\\b',
    'g',
    MAX_PER_KIND
  );

  const wallets: string[] = collect(
    scope,
    '\\b(?:bc1[a-z0-9]{25,62}|[13][a-km-zA-HJ-NP-Z1-9]{25,34}|0x[a-fA-F0-9]{40}|4[0-9AB][1-9A-HJ-NP-Za-km-z]{93})\\b',
    'g',
    20
  );

  return {
    domains: domains,
    ipv4: ipv4,
    ipv6: ipv6,
    urls: urls,
    emails: emails,
    hashes: hashes,
    wallets: wallets,
    total: domains.length + ipv4.length + ipv6.length + urls.length +
      emails.length + hashes.length + wallets.length
  };
}

/**
 * Network-relevant indicators only, in the order a reputation service cares
 * about. Used when a caller may share metadata with a cloud lookup — never the
 * file itself, and never anything that identifies the sender.
 */
export function indicatorList(iocs: IocSet): string[] {
  const out: string[] = [];
  for (let i = 0; i < iocs.domains.length; i++) {
    out.push(iocs.domains[i]);
  }
  for (let i = 0; i < iocs.urls.length; i++) {
    out.push(iocs.urls[i]);
  }
  for (let i = 0; i < iocs.ipv4.length; i++) {
    out.push(iocs.ipv4[i]);
  }
  for (let i = 0; i < iocs.ipv6.length; i++) {
    out.push(iocs.ipv6[i]);
  }
  return out;
}

/** Grade the extracted indicators and summarise what was found. */
export function assessIocs(iocs: IocSet): ThreatFinding[] {  const findings: ThreatFinding[] = [];

  const dynamicDns: string[] = [];
  const paste: string[] = [];
  const shorteners: string[] = [];
  const abuseTld: string[] = [];
  const punycode: string[] = [];
  const onion: string[] = [];
  const telegram: string[] = [];
  const discord: string[] = [];

  const hostCandidates: string[] = iocs.domains.concat(iocs.urls);
  for (let i = 0; i < hostCandidates.length; i++) {
    const value: string = hostCandidates[i];
    const lower: string = value.toLowerCase();

    if (lower.indexOf('xn--') >= 0) {
      punycode.push(value);
    }
    if (lower.indexOf('.onion') >= 0) {
      onion.push(value);
    }
    if (lower.indexOf('api.telegram.org/bot') >= 0) {
      telegram.push(value);
    }
    if (lower.indexOf('discord.com/api/webhooks') >= 0 ||
      lower.indexOf('discordapp.com/api/webhooks') >= 0) {
      discord.push(value);
    }

    const dynamic: string = endsWithAny(lower, DYNAMIC_DNS_SUFFIXES);
    if (dynamic.length > 0) {
      dynamicDns.push(value);
    }
    const pasteSuffix: string = endsWithAny(lower, PASTE_AND_DROP_SUFFIXES);
    if (pasteSuffix.length > 0) {
      paste.push(value);
    }
    if (endsWithAny(lower, SHORTENER_DOMAINS).length > 0) {
      shorteners.push(value);
    }
    for (let t = 0; t < ABUSE_TLDS.length; t++) {
      const tld: string = ABUSE_TLDS[t];
      if (lower.endsWith(tld) || lower.indexOf(`${tld}/`) >= 0 ||
        lower.indexOf(`${tld}:`) >= 0) {
        abuseTld.push(value);
        break;
      }
    }
  }

  // Raw-IP URLs: no domain to seize and no certificate to inspect.
  const rawIpUrls: string[] = [];
  for (let i = 0; i < iocs.urls.length; i++) {
    if (/^https?:\/\/(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?(?:[/?]|$)/i.test(iocs.urls[i])) {
      rawIpUrls.push(iocs.urls[i]);
    }
  }

  if (dynamicDns.length > 0) {
    findings.push(makeFinding(
      'ioc.dynamic-dns', '动态域名解析服务',
      '动态 DNS 可随时把域名指向新地址，是恶意载荷托管的高发区。',
      'high', dynamicDns
    ));
  }
  if (paste.length > 0) {
    findings.push(makeFinding(
      'ioc.paste-service', '临时文件 / 粘贴服务',
      '此类服务用于中转载荷或外传数据，常出现在脚本下载链中。',
      'high', paste
    ));
  }
  if (rawIpUrls.length > 0) {
    findings.push(makeFinding(
      'ioc.raw-ip-url', '直接使用 IP 的链接',
      '正规服务极少以裸 IP 提供服务，缺少域名与证书可核验。',
      'high', rawIpUrls
    ));
  }
  if (onion.length > 0) {
    findings.push(makeFinding(
      'ioc.onion-service', '暗网地址',
      '文件中包含 .onion 地址，指向匿名网络服务。',
      'high', onion
    ));
  }
  if (discord.length > 0) {
    findings.push(makeFinding(
      'ioc.chat-webhook', '聊天工具 Webhook',
      'Discord / Telegram Webhook 常被用作数据外传与指令下发通道。',
      'high', discord.concat(telegram)
    ));
  } else if (telegram.length > 0) {
    findings.push(makeFinding(
      'ioc.chat-bot-api', '机器人 API 地址',
      'Telegram Bot API 常被用作回传通道。',
      'medium', telegram
    ));
  }
  if (punycode.length > 0) {
    findings.push(makeFinding(
      'ioc.punycode', '同形字域名（Punycode）',
      'Punycode 域名常被用来伪装成知名站点，肉眼极难分辨。',
      'high', punycode
    ));
  }
  if (shorteners.length > 0) {
    findings.push(makeFinding(
      'ioc.shortener', '短链接',
      '短链接隐藏真实目标地址，无法直接判断去向。',
      'medium', shorteners
    ));
  }
  if (abuseTld.length > 0) {
    findings.push(makeFinding(
      'ioc.high-risk-tld', '高风险顶级域名',
      '低成本批量注册的顶级域名，恶意投递占比明显偏高。',
      'medium', abuseTld
    ));
  }
  if (iocs.wallets.length > 0) {
    findings.push(makeFinding(
      'ioc.crypto-wallet', '加密货币钱包地址',
      '文档中出现钱包地址，可能涉及勒索或诈骗收款。',
      'medium', iocs.wallets
    ));
  }

  if (iocs.total > 0) {
    const parts: string[] = [];
    if (iocs.domains.length > 0) {
      parts.push(`域名 ${iocs.domains.length}`);
    }
    if (iocs.urls.length > 0) {
      parts.push(`URL ${iocs.urls.length}`);
    }
    if (iocs.ipv4.length > 0) {
      parts.push(`公网 IP ${iocs.ipv4.length}`);
    }
    if (iocs.hashes.length > 0) {
      parts.push(`文件哈希 ${iocs.hashes.length}`);
    }
    if (iocs.emails.length > 0) {
      parts.push(`邮箱 ${iocs.emails.length}`);
    }
    findings.push({
      id: 'ioc.inventory',
      category: 'ioc',
      label: '可核验指标清单',
      detail: '已提取到外部指标，可用于威胁情报比对。',
      level: 'info',
      source: SOURCE,
      evidence: parts.join('，')
    });
  }

  return findings;
}

function makeFinding(id: string, label: string, detail: string,
  level: 'high' | 'medium' | 'low' | 'info', values: string[]): ThreatFinding {
  const preview: string[] = [];
  for (let i = 0; i < values.length && i < 4; i++) {
    preview.push(values[i].length > 80 ? `${values[i].substring(0, 80)}…` : values[i]);
  }
  return {
    id: id,
    category: 'ioc',
    label: label,
    detail: `${detail}（发现 ${values.length} 处）`,
    level: level,
    source: SOURCE,
    evidence: preview.join(', ')
  };
}
