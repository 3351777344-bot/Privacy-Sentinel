/**
 * L1 — script content scanner.
 *
 * Targets the delivery formats that survive on a phone: `.ps1` / `.bat` /
 * `.sh` / `.vbs` / `.js` attachments and any script body found inside an
 * archive entry. Emphasis is on the *capability* keywords — download, decode,
 * execute, persist — rather than on any single malware family's strings.
 */

import { ThreatFinding, ThreatLevel } from '../../models/ThreatModels';

const SOURCE: string = 'ScriptScanner';

export const SCRIPT_EXTENSIONS: string[] = [
  'ps1', 'psm1', 'psd1', 'bat', 'cmd', 'sh', 'bash', 'zsh', 'ksh',
  'vbs', 'vbe', 'js', 'jse', 'wsf', 'wsh', 'hta', 'py', 'pl', 'rb',
  'php', 'asp', 'aspx', 'jsp', 'jar', 'scr', 'sct', 'reg', 'inf', 'lnk'
];

interface ScriptRule {
  id: string;
  label: string;
  detail: string;
  level: ThreatLevel;
  pattern: string;
  flags: string;
  /** Maximum findings reported for this rule. */
  cap: number;
}

const RULES: ScriptRule[] = [
  // ------------------------------------------------------------ download & exec
  {
    id: 'script.download-string',
    label: '脚本远程下载并执行',
    detail: 'DownloadString / DownloadFile 常被用来拉取第二阶段载荷。',
    level: 'high',
    pattern: '\\bDownload(?:String|File|Data|DataAsync)\\s*\\(',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.invoke-expression',
    label: '动态执行表达式',
    detail: 'Invoke-Expression / iex 会把字符串当代码执行，是混淆脚本的标配。',
    level: 'high',
    pattern: '\\b(?:Invoke-Expression|iex)\\b|\\biex\\s*[\\(\\[]',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.pipe-to-shell',
    label: '管道直通解释器',
    detail: '下载内容直接管道给 shell 执行，看不到任何落地文件。',
    level: 'high',
    pattern: '(?:curl|wget|Invoke-WebRequest|iwr|Invoke-RestMethod)\\b[^\\n|]{0,200}\\|\\s*(?:sudo\\s+)?(?:ba|z|k)?sh\\b',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.encoded-command',
    label: 'PowerShell 编码命令',
    detail: '-EncodedCommand 携带 base64 载荷，用于绕过纯文本检测。',
    level: 'high',
    pattern: '(?:-|/)(?:enc|encodedcommand|e)\\s+[A-Za-z0-9+/=]{40,}',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.hidden-window',
    label: '隐藏窗口执行',
    detail: '隐藏窗口 / 无配置文件参数用于静默执行,避免用户察觉。',
    level: 'high',
    pattern: '(?:-|/)(?:w(?:indowstyle)?\\s+hidden|nop|noprofile|noninteractive)\\b|WindowStyle\\s+Hidden',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.execution-policy-bypass',
    label: '绕过执行策略',
    detail: 'Bypass / Unrestricted 会关闭脚本执行限制。',
    level: 'high',
    pattern: 'ExecutionPolicy\\s+(?:Bypass|Unrestricted|RemoteSigned\\s+-Force)|-ExecutionPolicy\\s+Bypass',
    flags: 'gi',
    cap: 2
  },
  {
    id: 'script.from-base64',
    label: 'Base64 解码后执行',
    detail: 'FromBase64String 配合执行调用是典型的载荷还原手法。',
    level: 'high',
    pattern: '(?:FromBase64String|base64\\s+(?:-d|--decode)|Convert\\.FromBase64String)',
    flags: 'gi',
    cap: 3
  },
  // ------------------------------------------------------------------ LOLBins
  {
    id: 'script.lolbin-certutil',
    label: '滥用系统工具下载 / 解码',
    detail: 'certutil 常被滥用为下载器和 base64 解码器。',
    level: 'high',
    pattern: 'certutil(?:\\.exe)?[^\\n]{0,120}(?:-urlcache|-decode|-encode|-f\\s+https?://)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.lolbin-proxy-exec',
    label: '系统程序代理执行',
    detail: 'rundll32 / mshta / regsvr32 / msiexec 常被用来代理执行载荷。',
    level: 'high',
    pattern: '\\b(?:rundll32(?:\\.exe)?\\s+\\S+\\s*,\\s*\\w|mshta(?:\\.exe)?\\s+(?:https?://|vbscript:|javascript:|about:)|regsvr32(?:\\.exe)?\\s+[^\\n]{0,80}(?:/s\\s+)?/i:https?://|msiexec(?:\\.exe)?\\s+/[iq]\\s+https?://)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.lolbin-bitsadmin',
    label: 'BITS 后台传输',
    detail: 'bitsadmin / Start-BitsTransfer 可在后台静默下载。',
    level: 'medium',
    pattern: '\\b(?:bitsadmin(?:\\.exe)?\\s+/transfer|Start-BitsTransfer\\b)',
    flags: 'gi',
    cap: 2
  },
  {
    id: 'script.process-spawn',
    label: '直接派生进程',
    detail: '脚本显式启动 cmd / powershell / wscript 等进程。',
    level: 'medium',
    pattern: '\\b(?:cmd(?:\\.exe)?\\s*/c|powershell(?:\\.exe)?\\s+-|wscript(?:\\.exe)?\\s+|cscript(?:\\.exe)?\\s+|/bin/(?:ba)?sh\\s+-c)\\b',
    flags: 'gi',
    cap: 3
  },
  // --------------------------------------------------------------- persistence
  {
    id: 'script.persistence-run-key',
    label: '写入开机自启项',
    detail: '注册表 Run 键 / 启动目录写入是典型持久化手法。',
    level: 'high',
    pattern: '(?:CurrentVersion\\\\Run|New-ItemProperty[^\\n]{0,120}(?:Run|RunOnce)|Startup[^\\n]{0,60}\\.lnk)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.persistence-scheduler',
    label: '创建计划任务 / 定时任务',
    detail: 'schtasks / at / crontab 用于在固定时间重新拉起载荷。',
    level: 'high',
    pattern: '\\b(?:schtasks(?:\\.exe)?\\s+/create|Register-ScheduledTask\\b|New-ScheduledTask\\b|crontab\\s+-|systemctl\\s+(?:enable|start)\\s+\\S+\\.service)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.registry-write',
    label: '修改注册表',
    detail: '注册表写入可能用于关闭安全策略或植入持久化。',
    level: 'medium',
    pattern: '\\b(?:reg\\s+add\\b|New-ItemProperty[^\\n]{0,80}HKLM:|Set-ItemProperty[^\\n]{0,80}HKLM:|reg\\.exe\\s+add)',
    flags: 'gi',
    cap: 3
  },
  // ------------------------------------------------------------ defense evasion
  {
    id: 'script.disable-defender',
    label: '尝试关闭安全防护',
    detail: '关闭实时防护 / 添加排除项会让后续载荷畅通无阻。',
    level: 'high',
    pattern: '(?:Set-MpPreference[^\\n]{0,120}Disable|Add-MpPreference[^\\n]{0,120}Exclusion|netsh\\s+advfirewall\\s+set\\s+\\S+\\s+state\\s+off|vssadmin\\s+delete\\s+shadows)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.amsi-bypass',
    label: 'AMSI / 日志规避',
    detail: '篡改 AMSI 或清理事件日志属于明确的对抗行为。',
    level: 'high',
    pattern: '(?:amsiInitFailed|AmsiUtils|amsi\\.dll|Wevtutil\\s+cl|Clear-EventLog|Remove-EventLog)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.reverse-shell',
    label: '反弹 Shell',
    detail: '通过 /dev/tcp 或 nc 建立反向连接,用于远程控制。',
    level: 'high',
    pattern: '(?:/dev/(?:tcp|udp)/|\\bnc(?:\\.exe)?\\s+(?:-[a-z]*e|--exec)\\s|\\bncat\\b[^\\n]{0,40}-e\\s|socat\\s+exec:)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.eval-dynamic',
    label: '动态代码求值',
    detail: 'eval / Function / ActiveXObject 可执行运行时拼接的代码。',
    level: 'medium',
    pattern: '\\b(?:eval\\s*\\(|new\\s+Function\\s*\\(|ActiveXObject\\s*\\(|WScript\\.CreateObject\\s*\\(|CreateObject\\s*\\(\\s*["\'](?:WScript\\.Shell|Shell\\.Application|Scripting\\.FileSystemObject))',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.shell-object',
    label: '脚本宿主对象调用',
    detail: 'WScript.Shell / ShellExecute 可在宿主环境启动任意程序。',
    level: 'medium',
    pattern: '(?:WScript\\.Shell|ShellApplication|ShellExecute\\s*\\(|\\.Run\\s*\\([^\\n]{0,60},\\s*0\\s*,\\s*(?:true|false)\\))',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.hta-application',
    label: 'HTA 应用声明',
    detail: 'HTA 以本地可信应用身份运行,常被用来直接执行命令。',
    level: 'medium',
    pattern: 'hta:application|WScript\\.Shell[^\\n]{0,120}\\.Run',
    flags: 'gi',
    cap: 2
  },
  // -------------------------------------------------------------- obfuscation
  {
    id: 'script.char-array-obfuscation',
    label: '字符数组拼接混淆',
    detail: '[char] 数组 / -join 拼接用于在运行时还原关键字,规避文本匹配。',
    level: 'medium',
    // Quotes inside the character class are written as \x27 / \x22 so the
    // TypeScript string literal is not terminated by the single quote.
    pattern: '(?:\\[char\\]\\s*\\d{1,3}|\\[char\\[\\]\\]|\\[convert\\]::FromBase64String|-join\\s*[\\(\\[\\x27\\x22]|\\[array\\]::Reverse)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.string-splitting',
    label: '字符串拆分绕过',
    detail: '把敏感关键字拆成多段再拼接,常见于混淆脚本。',
    level: 'medium',
    pattern: '(?:(?:["\'][A-Za-z]{2,10}["\']\\s*\\+\\s*){3,}|(?:\\(\\s*["\'][^"\']{1,8}["\']\\s*\\)\\s*\\+\\s*){2,})',
    flags: 'g',
    cap: 3
  },
  {
    id: 'script.wmi-exec',
    label: 'WMI / 远程执行',
    detail: '通过 WMI 启动进程常被用于横向移动和无文件落地执行。',
    level: 'medium',
    pattern: '(?:Win32_Process[^\\n]{0,80}Create|Invoke-WmiMethod|wmic\\s+process\\s+call\\s+create|Invoke-CimMethod)',
    flags: 'gi',
    cap: 3
  },
  {
    id: 'script.download-exec-combo',
    label: '下载并执行组合',
    detail: '同一份脚本中同时存在下载与执行调用,风险显著提升。',
    level: 'high',
    pattern: '(?:Invoke-WebRequest|iwr|curl|wget|DownloadFile|DownloadString)[\\s\\S]{0,400}?(?:Start-Process|Invoke-Item|&\\s*\\.\\/|sh\\s+-c|bash\\s+-c)',
    flags: 'gi',
    cap: 2
  }
];

function countMatches(text: string, pattern: string, flags: string, cap: number): string[] {
  const hits: string[] = [];
  let regex: RegExp;
  try {
    regex = new RegExp(pattern, flags);
  } catch (error) {
    return hits;
  }
  let match: RegExpExecArray | null = regex.exec(text);
  let guard: number = 0;
  while (match !== null && guard < 256) {
    guard++;
    const token: string = match[0].length > 90 ? `${match[0].substring(0, 90)}…` : match[0];
    if (hits.indexOf(token) < 0) {
      hits.push(token);
    }
    if (hits.length >= cap) {
      break;
    }
    if (regex.lastIndex === match.index) {
      regex.lastIndex++;
    }
    match = regex.exec(text);
  }
  return hits;
}

/** Long base64 runs are a strong signal of an encoded embedded payload. */
function detectBase64Payload(text: string): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  const pattern: string = '[A-Za-z0-9+/]{160,}={0,2}';
  let regex: RegExp;
  try {
    regex = new RegExp(pattern, 'g');
  } catch (error) {
    return findings;
  }
  const samples: string[] = [];
  let match: RegExpExecArray | null = regex.exec(text);
  let guard: number = 0;
  while (match !== null && guard < 64) {
    guard++;
    const blob: string = match[0];
    if (isHighEntropyBlob(blob)) {
      samples.push(`长度 ${blob.length}`);
    }
    if (samples.length >= 3) {
      break;
    }
    if (regex.lastIndex === match.index) {
      regex.lastIndex++;
    }
    match = regex.exec(text);
  }
  if (samples.length > 0) {
    findings.push({
      id: 'script.base64-blob',
      category: 'dangerous-script',
      label: '内嵌编码载荷',
      detail: '发现高熵 base64 数据块，通常是被编码的真实载荷（发现 ' +
        `${samples.length} 处）。`,
      level: 'high',
      source: SOURCE,
      evidence: samples.join(', ')
    });
  }
  return findings;
}

function isHighEntropyBlob(blob: string): boolean {
  const sample: string = blob.length > 512 ? blob.substring(0, 512) : blob;
  const counts: number[] = [];
  for (let i = 0; i < 256; i++) {
    counts.push(0);
  }
  for (let i = 0; i < sample.length; i++) {
    counts[sample.charCodeAt(i) & 0xFF]++;
  }
  let entropy: number = 0;
  for (let i = 0; i < 256; i++) {
    if (counts[i] === 0) {
      continue;
    }
    const p: number = counts[i] / sample.length;
    entropy -= p * (Math.log(p) / Math.LN2);
  }
  // base64 of text sits near 5.0-5.5; of encrypted data near 6.0.
  return entropy >= 5.0;
}

/** Scan a decoded script / source payload. */
export function scanScriptText(text: string): ThreatFinding[] {
  const findings: ThreatFinding[] = [];
  if (text.length === 0) {
    return findings;
  }
  for (let i = 0; i < RULES.length; i++) {
    const rule: ScriptRule = RULES[i];
    const hits: string[] = countMatches(text, rule.pattern, rule.flags, rule.cap);
    if (hits.length === 0) {
      continue;
    }
    findings.push({
      id: rule.id,
      category: 'dangerous-script',
      label: rule.label,
      detail: rule.detail,
      level: rule.level,
      source: SOURCE,
      evidence: hits.join(' | ')
    });
  }
  findings.push(...detectBase64Payload(text));
  return findings;
}

/** Cheap pre-filter so binary buffers skip the script rules entirely. */
export function looksLikeScript(text: string): boolean {
  if (text.length < 12) {
    return false;
  }
  const head: string = text.substring(0, 2048).toLowerCase();
  const markers: string[] = [
    '#!', '<?php', '<script', 'function ', 'wscript', 'createobject',
    'invoke-', 'net.webclient', 'import ', 'def ', 'sub ', 'echo off'
  ];
  for (let i = 0; i < markers.length; i++) {
    if (head.indexOf(markers[i]) >= 0) {
      return true;
    }
  }
  return false;
}
