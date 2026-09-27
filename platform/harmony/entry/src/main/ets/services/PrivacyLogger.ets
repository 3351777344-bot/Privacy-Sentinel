import { hilog } from '@kit.PerformanceAnalysisKit';

/** No free-form content, URIs, filenames or exception messages are accepted. */
export class PrivacyLogger {
  static logShareReceived(count: number, hasText: boolean): void {
    hilog.info(0x4748, 'GuardianHub.Share',
      'share_received item_count=%{public}d has_text=%{public}d', count, hasText ? 1 : 0);
  }

  static logScanError(): void {
    hilog.error(0x4748, 'GuardianHub.Share', 'share_view_failed');
  }
}
