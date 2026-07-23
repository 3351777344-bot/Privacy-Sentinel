import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppHeader } from '../components/AppHeader';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import { DetectResponse, Finding, PrivacyItem, PrivacyProcessResponse } from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { ProcessedImageService } from '../services/ProcessedImageService';

@Entry
@Component
struct PrivacyPage {
  @State hasImage: boolean = false;
  @State maskMode: string = 'black';
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State processed: boolean = false;
  @State imageUri: string = '';
  @State imageName: string = '';
  @State imageId: string = '';
  @State processedImageUri: string = '';
  @State statusMessage: string = '尚未选择图片';
  @State scanning: boolean = false;

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async pickAndDetect(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const selection = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (selection.photoUris.length === 0) {
        return;
      }
      this.imageUri = selection.photoUris[0];
      this.imageName = this.fileNameFromUri(this.imageUri);
      this.hasImage = true;
      this.processed = false;
      this.processedImageUri = '';
      this.scanning = true;
      this.statusMessage = '正在进行 OCR、二维码和隐私规则检测…';
      const report: DetectResponse =
        await GuardianApi.detectPrivacy(this.imageUri, this.imageName);
      await this.applyReport(report);
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '图片检测失败');
    } finally {
      this.scanning = false;
    }
  }

  private async detectDemo(): Promise<void> {
    this.imageUri = '';
    this.imageName = 'privacy_sentinel_demo_qr.png';
    this.hasImage = true;
    this.processed = false;
    this.processedImageUri = '';
    this.scanning = true;
    this.statusMessage = '正在载入演示图片并执行真实隐私检测…';
    try {
      const report = await GuardianApi.detectPrivacyDemo();
      await this.applyReport(report);
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '演示图片检测失败');
    } finally {
      this.scanning = false;
    }
  }

  private async applyReport(report: DetectResponse): Promise<void> {
    this.imageId = report.imageId;
    this.score = report.score;
    this.findings = report.items.map((item: PrivacyItem): Finding => {
      return {
        title: item.label,
        evidence: item.text.length > 0 ? item.text : report.summary,
        suggestion: item.suggestion,
        riskLevel: item.riskLevel
      };
    });
    this.statusMessage = report.summary;
    await HistoryStore.add(this.abilityContext(), {
      module: 'privacy',
      moduleLabel: '隐私哨兵',
      riskLevel: report.riskLevel,
      score: report.score,
      summary: report.summary
    });
  }

  private async processImage(): Promise<void> {
    if (this.imageId.length === 0) {
      this.statusMessage = '请先完成图片检测';
      return;
    }
    this.scanning = true;
    this.statusMessage = '正在生成安全预览…';
    try {
      const result: PrivacyProcessResponse =
        await GuardianApi.processPrivacy(this.imageId, this.maskMode);
      const imageData = await GuardianApi.downloadProcessedImage(result.processedImageUrl);
      this.processedImageUri = await ProcessedImageService.cache(
        this.abilityContext(),
        imageData
      );
      this.processed = true;
      this.statusMessage = result.message;
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '安全预览生成失败');
    } finally {
      this.scanning = false;
    }
  }

  private async saveProcessedImage(): Promise<void> {
    if (this.processedImageUri.length === 0) {
      this.statusMessage = '请先生成安全预览';
      return;
    }
    try {
      await ProcessedImageService.saveToGallery(
        this.abilityContext(),
        this.processedImageUri
      );
      this.statusMessage = '安全图片已保存到系统相册。';
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '保存图片失败');
    }
  }

  private async shareProcessedImage(): Promise<void> {
    if (this.processedImageUri.length === 0) {
      this.statusMessage = '请先生成安全预览';
      return;
    }
    try {
      await ProcessedImageService.share(
        this.abilityContext(),
        this.processedImageUri
      );
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '打开系统分享失败');
    }
  }

  private fileNameFromUri(uri: string): string {
    const rawName = uri.substring(uri.lastIndexOf('/') + 1);
    return decodeURIComponent(rawName) || 'privacy-image.jpg';
  }

  private errorMessage(error: Object, fallback: string): string {
    const typedError = error as Error;
    return typedError.message ? `${fallback}：${typedError.message}` : fallback;
  }

  private modeLabel(mode: string): string {
    if (mode === 'blur') {
      return '模糊';
    }
    if (mode === 'mosaic') {
      return '马赛克';
    }
    return '黑条';
  }

  build() {
    Column() {
      AppHeader({
        title: 'Privacy Sentinel',
        subtitle: '图片分享前隐私检查'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '01 选择图片',
            copy: '通过系统相册选择图片，再调用私有服务完成 OCR、二维码定位和隐私风险识别。'
          }) {
            Button(this.scanning ? '处理中…' : (this.hasImage ? '重新选择图片' : '从系统相册选择图片'))
              .enabled(!this.scanning)
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.scanning ? '#94A3B8' : '#2563EB')
              .borderRadius(13)
              .onClick(() => {
                this.pickAndDetect();
              })

            Button(this.scanning ? '处理中…' : '加载内置演示图')
              .enabled(!this.scanning)
              .width('100%')
              .height(42)
              .fontSize(13)
              .fontColor('#1D4ED8')
              .backgroundColor('#DBEAFE')
              .borderRadius(12)
              .margin({ top: 10 })
              .onClick(() => {
                this.detectDemo();
              })

            if (this.hasImage) {
              Row() {
                Text(this.imageName)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#172033')
                Blank()
                Text(this.imageId.length > 0 ? '已完成检测' : '等待结果')
                  .fontSize(11)
                  .fontColor('#15803D')
              }
              .padding(12)
              .backgroundColor('#F0FDF4')
              .borderRadius(12)
              .margin({ top: 12 })
              .width('100%')
            }

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
            emptyCopy: '载入演示图片后展示手机号、地址和二维码风险。'
          })
          .margin({ top: 12 })

          if (this.hasImage) {
            Column() {
              SectionCard({
                title: '02 选择处理方式',
                copy: '处理动作只针对命中的区域，导出前仍需人工复核。'
              }) {
                Row() {
                  ForEach(['black', 'blur', 'mosaic'], (mode: string) => {
                    Button(this.modeLabel(mode))
                      .layoutWeight(1)
                      .height(40)
                      .fontSize(12)
                      .fontColor(this.maskMode === mode ? '#FFFFFF' : '#334155')
                      .backgroundColor(this.maskMode === mode ? '#2563EB' : '#F1F5F9')
                      .borderRadius(11)
                      .margin({ right: mode === 'mosaic' ? 0 : 8 })
                      .onClick(() => {
                        this.maskMode = mode;
                        this.processed = false;
                        this.processedImageUri = '';
                      })
                  }, (mode: string) => mode)
                }
                .width('100%')

                Button(this.scanning ? '处理中…' :
                  (this.processed ? '重新生成安全预览' : '生成安全预览'))
                  .enabled(!this.scanning)
                  .width('100%')
                  .height(46)
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .backgroundColor(this.scanning ? '#94A3B8' :
                    (this.processed ? '#15803D' : '#172033'))
                  .borderRadius(13)
                  .margin({ top: 12 })
                  .onClick(() => {
                    this.processImage();
                  })

                if (this.processed) {
                  Image(this.processedImageUri)
                    .width('100%')
                    .height(240)
                    .objectFit(ImageFit.Contain)
                    .backgroundColor('#E2E8F0')
                    .borderRadius(12)
                    .margin({ top: 12 })

                  Text(`已使用${this.modeLabel(this.maskMode)}处理 ${this.findings.length} 个风险区域，建议导出前放大复核边界。`)
                    .fontSize(12)
                    .fontColor('#166534')
                    .lineHeight(19)
                    .padding(12)
                    .backgroundColor('#F0FDF4')
                    .borderRadius(12)
                    .margin({ top: 10 })
                    .width('100%')

                  Row() {
                    Button('保存到相册')
                      .layoutWeight(1)
                      .height(42)
                      .fontSize(12)
                      .fontColor('#1D4ED8')
                      .backgroundColor('#DBEAFE')
                      .borderRadius(11)
                      .margin({ right: 8 })
                      .onClick(() => {
                        this.saveProcessedImage();
                      })

                    Button('系统分享')
                      .layoutWeight(1)
                      .height(42)
                      .fontSize(12)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#2563EB')
                      .borderRadius(11)
                      .onClick(() => {
                        this.shareProcessedImage();
                      })
                  }
                  .width('100%')
                  .margin({ top: 10 })
                }
              }
            }
            .width('100%')
            .margin({ top: 12 })
          }
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
