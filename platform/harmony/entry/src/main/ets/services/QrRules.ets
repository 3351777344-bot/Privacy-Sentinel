import { Finding } from '../models/SecurityModels';
import { LocalRuleEngine } from './LocalRuleEngine';
import { ScanPolicy } from './ScanPolicy';

export interface QrRect { left: number; top: number; right: number; bottom: number; }
export interface DecodedQr { payload: string; rect?: QrRect; }
export interface QrClassification {
  found: boolean;
  label: string;
  riskLevel: string;
  text: string;
  suggestion: string;
  /** Raw URL is memory-only and must not be displayed, logged, or persisted. */
  url: string;
  sensitive: boolean;
  rect?: QrRect;
}
export interface QrImageReport {
  status: 'decoded' | 'not_found' | 'failed';
  codes: QrClassification[];
  findings: Finding[];
  uploadBlocked: boolean;
  note: string;
}

export class QrRules {
  static display(value: string): string {
    // URLs retain only the origin for display; query, fragment and path can all contain credentials.
    if (/^https?:\/\//i.test(value)) {
      const match = value.match(/^https?:\/\/([^/?#]+)/i);
      return match ? `${match[0].replace(/\/\/[^/]*@/, '//***@')}/…（完整内容仅供端侧分析）` : '链接内容已隐藏';
    }
    return '二维码内容已隐藏';
  }

  static classify(payload: string): QrClassification {
    const value = payload.trim();
    let label = '文本二维码';
    let sensitive = false;
    let risk = 'low';
    let suggestion = '确认来源后再使用；未命中不代表安全。';
    if (/qr\.alipay\.com|render\.alipay\.com|wxp:\/\/|weixin:\/\/wxpay|alipays:\/\//i.test(value) || /^\d{16,32}$/.test(value)) {
      label = '支付凭证二维码'; sensitive = true; risk = 'high';
    } else if (/WIFI:|BEGIN:VCARD/i.test(value) ||
      /(?:token|secret|password|session|auth|api[_-]?key|code)\s*[=:]|login|oauth|identity|credential/i.test(value) ||
      /(^|\D)1[3-9]\d{9}(?!\d)|\d{15,19}|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i.test(value)) {
      label = '含凭证或个人信息的二维码'; sensitive = true; risk = 'high';
    } else if (/^https?:\/\//i.test(value)) {
      label = '链接二维码';
      risk = ScanPolicy.risk(LocalRuleEngine.scanLink(value, '二维码').findings);
    } else if (value.length === 0) {
      label = '无法读取二维码内容'; sensitive = true; risk = 'medium';
    }
    if (sensitive) { suggestion = '禁止上传原图。请先在端侧遮挡，再复核和分享。'; }
    return { found: true, label: label, riskLevel: risk, text: QrRules.display(value),
      suggestion: suggestion, url: /^https?:\/\//i.test(value) ? value : '', sensitive: sensitive };
  }

  static analyze(decoded: DecodedQr[], failed: boolean = false): QrImageReport {
    const codes: QrClassification[] = [];
    const findings: Finding[] = [];
    decoded.forEach((item: DecodedQr, index: number) => {
      const code = QrRules.classify(item.payload);
      code.rect = item.rect;
      codes.push(code);
      findings.push({ title: `二维码 ${index + 1} · ${code.label}`, evidence: code.text,
        suggestion: code.suggestion,
        riskLevel: code.riskLevel === 'high' ? 'high' : (code.riskLevel === 'medium' ? 'medium' : 'low') });
      if (code.url.length > 0) {
        findings.push(...LocalRuleEngine.scanLink(code.url, '二维码').findings);
      }
    });
    return { status: failed ? 'failed' : (codes.length > 0 ? 'decoded' : 'not_found'),
      codes: codes, findings: findings,
      uploadBlocked: failed || codes.some((code: QrClassification): boolean => code.sensitive),
      note: failed ? '二维码解析失败，不能当作无二维码；原图增强已阻断。' :
        (codes.length > 0 ? `已检查全部 ${codes.length} 枚二维码。` : '未识别到二维码，不代表图片无隐私。') };
  }
}
