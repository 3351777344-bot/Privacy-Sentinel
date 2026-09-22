/**
 * On-device QR/barcode handling for the share gate's image channel.
 *
 * Two responsibilities, deliberately separated:
 *
 *  1. `decodeImage` — decode a local image with Scan Kit. No server involved,
 *     so a payment code never has to leave the device to be recognised.
 *  2. `classify` — map a decoded payload to a risk level and advice.
 *
 * `classify` does NOT delegate to `LocalRuleEngine.scanLink`: measured against
 * real payloads that produced wrong answers, e.g. `wxp://…` and a 16-digit
 * payment code both scored 72 ("未使用 HTTPS") and `https://qr.alipay.com/…`
 * scored 100 with no findings at all — reporting a live payment credential as
 * "no risk found". Payment semantics are therefore checked first, explicitly.
 */

import { detectBarcode } from '@kit.ScanKit';
import { scanCore } from '@kit.ScanKit';

export interface QrClassification {
  /** True when a code was present at all. */
  found: boolean;
  label: string;
  riskLevel: string;
  /** Short, non-reversible preview suitable for display. */
  text: string;
  suggestion: string;
  /** Decoded destination for HTTP(S) payloads, reused by the link rules. */
  url: string;
}

const PAYMENT_URL = /(qr\.alipay\.com|render\.alipay\.com|wxp:\/\/|weixin:\/\/wxpay|alipays:\/\/)/i;
const PAYMENT_DIGITS = /^\d{16,32}$/;
const HTTP_URL = /^https?:\/\//i;
const WIFI = /^WIFI:/i;
const VCARD = /^BEGIN:VCARD/i;
const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;
const PHONE = /(?<!\d)1[3-9]\d{9}(?!\d)/;
const LONG_DIGITS = /^\d{11,}$/;
const SECRET_QUERY = /((?:token|key|api[_-]?key|secret|password|sign|session|auth|code)=)[^&#\s]+/gi;

function preview(value: string, keep: number = 4): string {
  const compact = value.replace(/\s+/g, '');
  if (compact.length <= keep * 2) {
    return '内容已隐藏';
  }
  return `${compact.substring(0, keep)}…${compact.substring(compact.length - keep)}`;
}

/** Stop the report itself from leaking the credential it warns about. */
function redact(value: string): string {
  return value
    .replace(SECRET_QUERY, '$1***')
    .replace(EMAIL, '***@***')
    .replace(PHONE, '1**********')
    .substring(0, 60);
}

function empty(): QrClassification {
  return {
    found: false,
    label: '',
    riskLevel: 'low',
    text: '',
    suggestion: '',
    url: ''
  };
}

export class QrContentService {
  /**
   * Decode the first code found in a local image. Returns an empty result when
   * the image holds no code, or when Scan Kit is unavailable — detection must
   * never fail because of a missing optional capability.
   */
  static async decodeImage(imageUri: string): Promise<QrClassification> {
    try {
      const results = await detectBarcode.decode(
        { uri: imageUri },
        { scanTypes: [scanCore.ScanType.QR_CODE, scanCore.ScanType.ALL] }
      );
      if (results === undefined || results === null || results.length === 0) {
        return empty();
      }
      const first = results[0];
      const payload: string = first.originalValue ? first.originalValue : '';
      if (payload.length === 0) {
        return empty();
      }
      return QrContentService.classify(payload);
    } catch (error) {
      return empty();
    }
  }

  /** Map a decoded payload to label / risk / advice. Pure, no I/O. */
  static classify(payload: string): QrClassification {
    const value: string = payload ? payload.trim() : '';
    if (value.length === 0) {
      return {
        found: true,
        label: '二维码',
        riskLevel: 'medium',
        text: '二维码内容为空或无法解码',
        suggestion: '未解出内容时无法判断风险，建议遮挡或向发送者确认。',
        url: ''
      };
    }

    // Live payment credential — the case that must never be under-reported.
    if (PAYMENT_DIGITS.test(value) || PAYMENT_URL.test(value)) {
      return {
        found: true,
        label: '收款码/付款码',
        riskLevel: 'high',
        text: preview(value),
        suggestion: '这是支付凭证，他人可凭此向你收款或发起付款，请勿公开分享。',
        url: ''
      };
    }

    if (WIFI.test(value)) {
      return {
        found: true,
        label: 'Wi-Fi 连接码',
        riskLevel: 'high',
        text: '内容已隐藏（含网络口令）',
        suggestion: '该码包含 Wi-Fi 名称与口令，分享后会泄露网络访问权限，建议遮挡。',
        url: ''
      };
    }

    if (VCARD.test(value)) {
      return {
        found: true,
        label: '名片二维码',
        riskLevel: 'medium',
        text: '内容已隐藏（含联系方式）',
        suggestion: '名片码包含姓名与联系方式，会暴露个人账号信息，建议确认后再分享。',
        url: ''
      };
    }

    if (HTTP_URL.test(value)) {
      return {
        found: true,
        label: '链接二维码',
        riskLevel: 'low',
        text: redact(value),
        suggestion: '链接未命中已知风险特征，但二维码可被替换，访问前请确认来源。',
        url: value
      };
    }

    if (PHONE.test(value) || EMAIL.test(value)) {
      return {
        found: true,
        label: '含隐私信息的二维码',
        riskLevel: 'medium',
        text: preview(value),
        suggestion: '二维码内容包含联系方式等个人信息，建议遮挡。',
        url: ''
      };
    }

    if (LONG_DIGITS.test(value)) {
      return {
        found: true,
        label: '数字编码二维码',
        riskLevel: 'medium',
        text: preview(value),
        suggestion: '该码是一串数字编码，可能是账号或订单标识，建议确认用途后再分享。',
        url: ''
      };
    }

    return {
      found: true,
      label: '二维码（文本）',
      riskLevel: 'low',
      text: preview(value),
      suggestion: '检出的二维码为普通文本内容，未发现敏感信息；如非本人预期请遮挡。',
      url: ''
    };
  }
}
