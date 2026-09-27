import { promptAction } from '@kit.ArkUI';

export { ProcessingMode } from './ScanPolicy';

export class NetworkConsent {
  static async require(data: string): Promise<void> {
    const answer = await promptAction.showDialog({
      title: '联网检查确认',
      message: `${data}\n同意后，相关内容会通过网络发送给 GuardianHub 服务，用于在线安全检查；若检查使用在线 AI，相关内容也可能由 AI 服务处理。不同意则不会上传，并保留本地检查结果。`,
      buttons: [
        { text: '暂不联网', color: '#64748B' },
        { text: '同意并继续', color: '#2563EB' }
      ]
    });
    if (answer.index !== 1) {
      throw new Error('你选择了不联网，已保留本地检查结果。');
    }
  }
}
