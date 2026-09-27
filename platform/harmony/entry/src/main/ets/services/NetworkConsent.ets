import { promptAction } from '@kit.ArkUI';

export { ProcessingMode } from './ScanPolicy';

export class NetworkConsent {
  static async require(data: string): Promise<void> {
    const answer = await promptAction.showDialog({
      title: '本次增强分析授权',
      message: `${data}\n将发送至配置的后端；联网模型可能接收内容。拒绝后保留本地结果，不重试上传。`,
      buttons: [
        { text: '拒绝上传', color: '#64748B' },
        { text: '同意本次上传', color: '#2563EB' }
      ]
    });
    if (answer.index !== 1) {
      throw new Error('未授权上传，保留本地结果。');
    }
  }
}
