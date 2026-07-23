import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppHeader } from '../components/AppHeader';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import {
  Finding,
  LinkCheckItem,
  LinkCheckResponse,
  QrDecodeResponse
} from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';

@Entry
@Component
struct LinkPage {
  @State urlText: string = 'http://xn--campus-login.example/login?redirect=payment&token=demo';
  @State sourceText: string = '陌生短信';
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State statusMessage: string = '等待检测';
  @State scanning: boolean = false;

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async scan(): Promise<void> {
    if (this.urlText.trim().length === 0) {
      this.statusMessage = '请先输入链接或从二维码解析链接';
      return;
    }
    this.scanning = true;
    this.statusMessage = '正在执行静态检查，不会访问目标链接…';
    try {
      const report: LinkCheckResponse =
        await GuardianApi.checkLink(this.urlText, this.sourceText);
      const suggestion = report.suggestions.length > 0 ?
        report.suggestions[0] : '打开前再次核对域名和来源。';
      this.findings = report.checks.map((item: LinkCheckItem): Finding => {
        return {
          title: item.label,
          evidence: item.message,
          suggestion: suggestion,
          riskLevel: item.riskLevel
        };
      });
      this.score = report.score;
      this.statusMessage =
        `${report.summary} ${report.shouldOpen ? '可以谨慎打开。' : '不建议继续打开。'}`;
      await HistoryStore.add(this.abilityContext(), {
        module: 'link',
        moduleLabel: '链接卫士',
        riskLevel: report.riskLevel,
        score: report.score,
        summary: report.summary
      });
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '联网检测失败');
    } finally {
      this.scanning = false;
    }
  }

  private async pickQrImage(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      this.statusMessage = '正在本地解析二维码，不会访问其中的链接…';
      const uri = result.photoUris[0];
      const decoded: QrDecodeResponse =
        await GuardianApi.decodeQr(uri, this.fileNameFromUri(uri));
      this.urlText = decoded.primaryText;
      this.sourceText = '二维码图片';
      this.statusMessage = decoded.message;
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '二维码解析失败');
    }
  }

  private fileNameFromUri(uri: string): string {
    const rawName = uri.substring(uri.lastIndexOf('/') + 1);
    return decodeURIComponent(rawName) || 'qrcode.jpg';
  }

  private errorMessage(error: Object, fallback: string): string {
    const typedError = error as Error;
    return typedError.message ? `${fallback}：${typedError.message}` : fallback;
  }

  build() {
    Column() {
      AppHeader({
        title: 'Link Guard',
        subtitle: '点击前静态安全体检'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '01 输入链接与来源',
            copy: '只分析文本，不主动访问目标地址，避免把检测本身变成风险。'
          }) {
            Text('链接')
              .fontSize(12)
              .fontColor('#475569')
              .margin({ bottom: 6 })
            TextArea({
              text: this.urlText,
              placeholder: 'https://example.com/path'
            })
              .height(105)
              .fontSize(13)
              .backgroundColor('#F8FAFC')
              .borderRadius(12)
              .padding(11)
              .onChange((value: string) => {
                this.urlText = value;
              })

            Text('来源场景')
              .fontSize(12)
              .fontColor('#475569')
              .margin({ top: 12, bottom: 6 })
            TextInput({
              text: this.sourceText,
              placeholder: '例如：学校官网、短信、群聊'
            })
              .height(44)
              .fontSize(13)
              .backgroundColor('#F8FAFC')
              .borderRadius(12)
              .onChange((value: string) => {
                this.sourceText = value;
              })

            Button('从相册解析二维码')
              .width('100%')
              .height(42)
              .fontSize(13)
              .fontColor('#0F766E')
              .backgroundColor('#CCFBF1')
              .borderRadius(12)
              .margin({ top: 12 })
              .onClick(() => {
                this.pickQrImage();
              })

            Button(this.scanning ? '检测中…' : '开始链接安全检测')
              .enabled(!this.scanning)
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.scanning ? '#94A3B8' : '#0F9F8F')
              .borderRadius(13)
              .margin({ top: 10 })
              .onClick(() => {
                this.scan();
              })

            Text(this.statusMessage)
              .fontSize(12)
              .fontColor('#64748B')
              .lineHeight(19)
              .margin({ top: 9 })
              .width('100%')
          }

          ResultPanel({
            findings: this.findings,
            score: this.score,
            emptyCopy: '检测 HTTPS、IP 直连、Punycode、短链、敏感参数和来源风险。'
          })
          .margin({ top: 12 })
        }
        .padding({ left: 16, right: 16, bottom: 28 })
        .width('100%')
      }
      .layoutWeight(1)
    }
    .backgroundColor('#F4F7FB')
    .width('100%')
    .height('100%')
  }
}
