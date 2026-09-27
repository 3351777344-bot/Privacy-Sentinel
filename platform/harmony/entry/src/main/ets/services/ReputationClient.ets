/**
 * L3 — optional cloud reputation lookup.
 *
 * Opt-in second opinion for files whose local verdict is *suspicious* but not
 * conclusive. The privacy boundary is the whole point of this class:
 *
 *  * only a SHA-256 digest plus the local verdict is sent — never file content,
 *    never the file itself, and no domain/URL indicators (the signed feed is a
 *    hash blocklist, so extracted addresses would not be matched anyway);
 *  * the call is only made when the caller opts in, and only for suspicious
 *    files, so a clean scan stays entirely offline;
 *  * every failure is swallowed — the local verdict always stands on its own.
 */

import { http } from '@kit.NetworkKit';
import { ThreatFinding } from '../models/ThreatModels';
import { API_BASE_URL } from './GuardianApi';
import { NetworkConsent } from './NetworkConsent';

/** One file's metadata, matched by `DocReputationQuery` on the server. */
export interface ReputationQuery {
  sha256: string;
  fileName?: string;
  declaredExtension?: string;
  detectedType?: string;
  localVerdict: string;
}

/** Wire format for one query, matching the server's `DocReputationQuery`. */
interface ReputationPayload {
  sha256: string;
  localVerdict: string;
  fileName?: string;
  declaredExtension?: string;
  detectedType?: string;
}

interface ReputationResultDto {
  sha256: string;
  known: boolean;
  family?: string;
  confidence: number;
  notes: string[];
}

interface ReputationResponseDto {
  feedVersion: string;
  entries: number;
  results: ReputationResultDto[];
  message: string;
}

export interface ReputationOutcome {
  /** Findings to fold into the report; empty when nothing was learned. */
  findings: ThreatFinding[];
  /** Server-side feed description, shown as an engine note. */
  message: string;
  /** True when the service answered — false when it was unreachable. */
  reachable: boolean;
}

export class ReputationClient {
  /**
   * Query the reputation service for one file.
   * Never throws: an offline device simply gets `reachable: false`.
   */
  static async lookup(query: ReputationQuery): Promise<ReputationOutcome> {
    const empty: ReputationOutcome = { findings: [], message: '', reachable: false };
    if (query.sha256.length !== 64) {
      return empty;
    }

    const request = http.createHttp();
    try {
      await NetworkConsent.require('只发送文件的数字指纹和本机风险等级，用于查询是否存在已知风险；不会发送文件内容、文件名或链接中的个人信息。');
      const response = await request.request(`${API_BASE_URL}/api/doc/reputation`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'X-Guardian-Consent': 'explicit' },
        extraData: JSON.stringify({ files: [ReputationClient.toPayload(query)] }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 15000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return empty;
      }
      const body = JSON.parse(response.result as string) as ReputationResponseDto;
      if (body.results === undefined || body.results.length === 0) {
        return { findings: [], message: body.message ?? '', reachable: true };
      }
      return {
        findings: ReputationClient.toFindings(body.results[0], query),
        message: body.message ?? '',
        reachable: true
      };
    } catch (_) {
      return empty;
    } finally {
      request.destroy();
    }
  }

  private static toPayload(query: ReputationQuery): ReputationPayload {
    const payload: ReputationPayload = {
      sha256: query.sha256,
      localVerdict: query.localVerdict
    };
    if (query.declaredExtension !== undefined) {
      payload.declaredExtension = query.declaredExtension;
    }
    if (query.detectedType !== undefined) {
      payload.detectedType = query.detectedType;
    }
    return payload;
  }

  private static toFindings(result: ReputationResultDto,
    query: ReputationQuery): ThreatFinding[] {
    if (!result.known) {
      return [];
    }
    const family: string = result.family !== undefined && result.family.length > 0
      ? result.family : '已知恶意样本';
    const notes: string = result.notes.length > 0 ? ` ${result.notes.join(' ')}` : '';

    // The signed feed only carries SHA-256 indicators, so every hit is a hash
    // hit; there is no "infrastructure-only" branch to downgrade.
    return [{
      id: 'reputation.hash-hit',
      category: 'signature-match',
      label: '云端情报库命中该文件',
      detail: `云端情报库记录该文件属于「${family}」。${notes}`,
      level: 'high',
      source: 'ReputationClient',
      evidence: `${query.sha256.substring(0, 16)}…`
    }];
  }
}
