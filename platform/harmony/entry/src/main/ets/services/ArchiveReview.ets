import { readZipDirectory, ZipEntry } from './scanners/ZipReader';
import { ThreatScanReport } from '../models/ThreatModels';

export interface ArchivePreview {
  fileCount: number;
  bytes: number;
  expandedBytes: number;
  sensitiveFiles: string[];
  summary: string;
  canEnhance: boolean;
}

export class ArchiveReview {
  static inspect(data: Uint8Array, report: ThreatScanReport): ArchivePreview {
    const directory = readZipDirectory(data);
    const files = directory.entries.filter((item: ZipEntry): boolean => !item.directory);
    const sensitive = files.filter((item: ZipEntry): boolean =>
      /(^|\/)(\.env(?:\..*)?|id_rsa|id_ed25519|credentials|[^/]*(?:token|secret)[^/]*)$|\.(pem|key|p12|pfx|cer|crt)$/i.test(item.name));
    // No file paths, raw findings/evidence, extracted text, or archive bytes leave the device.
    const ids = report.findings.map((item): string => item.id).filter((id: string): boolean => /^[a-z0-9.-]{1,80}$/i.test(id));
    const summary = JSON.stringify({ kind: 'archive-static-summary', fileCount: files.length,
      compressedBytes: data.length, expandedBytes: directory.declaredTotal,
      sensitiveFileCount: sensitive.length, findingIds: ids.slice(0, 100), verdict: report.verdict });
    return { fileCount: files.length, bytes: data.length, expandedBytes: directory.declaredTotal,
      sensitiveFiles: sensitive.map((item: ZipEntry): string => item.name.replace(/[\r\n\x00-\x1f]/g, '').slice(0, 160)),
      summary: summary, canEnhance: directory.ok && !directory.entryLimitHit };
  }

  static describe(preview: ArchivePreview): string {
    return `包内文件 ${preview.fileCount} 个 · 原包 ${preview.bytes} 字节 · 声明展开 ${preview.expandedBytes} 字节\n` +
      `敏感文件 ${preview.sensitiveFiles.length} 个：${preview.sensitiveFiles.slice(0, 20).join('、') || '未命中名称规则'}\n` +
      '增强仅发送计数、规则编号和风险结论，不发送原ZIP、路径、源码或凭据。';
  }
}
