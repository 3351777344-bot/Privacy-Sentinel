import { Finding, RiskLevel } from '../models/SecurityModels';

export type ProcessingMode = 'local_only' | 'hybrid' | 'online';
export type TransferState = 'not_sent' | 'awaiting_consent' | 'rejected' | 'sending' | 'sent' | 'failed';
export type Verdict = 'safe' | 'low' | 'medium' | 'high' | 'blocked' | 'unknown';

/** Per-operation state, never a global consent flag. No implicit retry. */
export class TransferSession {
  mode: ProcessingMode;
  state: TransferState = 'not_sent';
  constructor(mode: ProcessingMode = 'hybrid') { this.mode = mode; }

  async run<T>(consent: () => Promise<void>, send: () => Promise<T>): Promise<T> {
    if (this.mode === 'local_only') { throw new Error('仅本地模式禁止联网，请切换处理模式。'); }
    if (this.state !== 'not_sent') { throw new Error('本次请求已处理；再次分析需重新授权。'); }
    this.state = 'awaiting_consent';
    try { await consent(); } catch (_) {
      this.state = 'rejected';
      throw new Error('已拒绝本次上传，保留本地结果。');
    }
    this.state = 'sending';
    try {
      const result: T = await send();
      this.state = 'sent';
      return result;
    } catch (_) {
      this.state = 'failed';
      throw new Error('已尝试发送，服务器可能已收到数据；结果未完成，未自动重试。');
    }
  }

  describe(): string {
    switch (this.state) {
      case 'awaiting_consent': return '等待本次联网授权 · 尚未发送';
      case 'rejected': return '已拒绝授权 · 未发送';
      case 'sending': return '已授权 · 正在发送';
      case 'sent': return '已授权发送 · 已收到远程结果';
      case 'failed': return '已尝试发送 · 数据可能已到达服务器 · 未自动重试';
      default: return this.mode === 'local_only' ? '仅本地 · 未发送' : '本地检测完成 · 未发送 · 可主动增强';
    }
  }
}

export class ScanPolicy {
  static shouldEnhance(mode: ProcessingMode, clicked: boolean): boolean {
    return mode !== 'local_only' && (mode === 'online' || clicked);
  }

  static risk(findings: Finding[]): RiskLevel {
    if (findings.some((item: Finding): boolean => item.riskLevel === 'high')) { return 'high'; }
    return findings.some((item: Finding): boolean => item.riskLevel === 'medium') ? 'medium' : 'low';
  }

  static score(findings: Finding[]): number {
    return Math.max(0, 100 - findings.reduce((sum: number, item: Finding): number =>
      sum + (item.riskLevel === 'high' ? 28 : (item.riskLevel === 'medium' ? 16 : 7)), 0));
  }

  static verdict(findings: Finding[], complete: boolean, blocked: boolean = false): Verdict {
    if (blocked) { return 'blocked'; }
    if (findings.length > 0) { return ScanPolicy.risk(findings); }
    return complete ? 'safe' : 'unknown';
  }

  static label(verdict: Verdict): string {
    switch (verdict) {
      case 'safe': return '已检查范围未发现风险';
      case 'low': return '低风险';
      case 'medium': return '中风险';
      case 'high': return '高风险';
      case 'blocked': return '阻断原内容增强';
      default: return '未知或未完成';
    }
  }
}
