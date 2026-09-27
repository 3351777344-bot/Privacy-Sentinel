import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { AppHeader } from '../components/AppHeader';
import { ProcessingMode, ProcessingModeSelector } from '../components/ProcessingModeSelector';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import { DetectResponse, Finding, PrivacyItem, PrivacyProcessResponse } from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { ProcessedImageService } from '../services/ProcessedImageService';
import { QrContentService } from '../services/QrContentService';
import { QrImageReport, QrRules } from '../services/QrRules';
import { ScanPolicy, TransferSession } from '../services/ScanPolicy';

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
  @State historyRecordId: string = '';
  @State statusMessage: string = '尚未选择图片';
  @State scanning: boolean = false;
  @State processingMode: ProcessingMode = 'online';
  private imageTransfer: TransferSession = new TransferSession('online');

  private qrReport: QrImageReport = QrRules.analyze([]);
  @State localComplete: boolean = false;
  @State resultMeta: string = '尚未检测';

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async pickFromFiles(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['图片|.png,.jpg,.jpeg,.webp,.bmp,.gif'];
      options.maxSelectNumber = 1;
      const result = await new picker.DocumentViewPicker().select(options);
      if (result.length === 0) {
        return;
      }
      await this.detectSelectedImage(result[0], this.fileNameFromUri(result[0]));
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '未能打开文件选择器');
    }
  }

  private async pickFromAlbum(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const selection = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (selection.photoUris.length === 0) {
        return;
      }
      await this.detectSelectedImage(
        selection.photoUris[0],
        this.fileNameFromUri(selection.photoUris[0])
      );
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '未能打开系统相册');
    }
  }

  private async detectSelectedImage(imageUri: string, imageName: string): Promise<void> {
    if (this.scanning) { return; }
    const mode = this.processingMode;
    const transfer = new TransferSession(mode);
    this.imageTransfer = transfer;
    this.imageUri = imageUri;
    this.imageName = imageName;
    this.hasImage = true;
    this.processed = false;
    this.processedImageUri = '';
    this.imageId = '';
    this.scanning = true;
    this.localComplete = false;
    try {
      this.qrReport = await QrContentService.decodeAll(imageUri);
      this.findings = this.qrReport.findings;
      this.score = ScanPolicy.score(this.findings);
      this.localComplete = this.qrReport.status !== 'failed';
      this.resultMeta = '来源：端侧二维码与链接规则 · ' + transfer.describe();
      this.statusMessage = this.qrReport.note + ' 未识别图片中的文字，请人工检查文字隐私。';
      this.historyRecordId = await HistoryStore.add(this.abilityContext(), {
        module: 'privacy', moduleLabel: '隐私哨兵', riskLevel: ScanPolicy.risk(this.findings),
        score: this.score, summary: this.statusMessage + ' ' + this.resultMeta,
        sourceLabel: '本地图片', findings: this.findings, suggestions: ['遮挡二维码后仍需检查文字与人物。']
      });
      if (mode === 'online') {
        if (this.qrReport.uploadBlocked) {
          this.statusMessage += ' 图片中的二维码无法确认安全，原图未上传。';
          await this.showNotice('联网分析已阻止',
            '检测到敏感二维码或无法可靠解析二维码。为保护图片内容，未上传原图；可移除二维码后重新选择图片。');
        } else {
          try {
            const report = await GuardianApi.detectPrivacy(imageUri, imageName, mode, transfer);
            await this.applyReport(report);
          } catch (error) {
            const reason = this.errorMessage(error, '增强未完成');
            this.statusMessage += ' ' + reason;
            await this.showNotice('增强分析未完成', reason + '\n已保留端侧检测结果。');
          }
        }
      }
    } finally {
      this.resultMeta = (transfer.state === 'sent' ? '来源：端侧与远程 · ' : '来源：端侧 · ') + transfer.describe();
      this.scanning = false;
    }
  }

  private async applyReport(report: DetectResponse): Promise<void> {
    this.imageId = report.imageId;
    this.score = report.score;
    this.findings = this.qrReport.findings.concat(report.items.map((item: PrivacyItem): Finding => {
      return {
        title: item.label,
        evidence: item.text.length > 0 ? item.text : report.summary,
        suggestion: item.suggestion,
        riskLevel: item.riskLevel
      };
    }));
    this.score = ScanPolicy.score(this.findings);
    this.statusMessage = report.summary;
    if (report.detectorMessage && report.detectorMessage.length > 0) {
      this.statusMessage = `${this.statusMessage}\n${report.detectorMessage}`;
    }
    this.historyRecordId = await HistoryStore.add(this.abilityContext(), {
      module: 'privacy',
      moduleLabel: '隐私哨兵',
      riskLevel: report.riskLevel,
      score: report.score,
      summary: report.summary,
      sourceLabel: this.imageName,
      findings: this.findings,
      suggestions: this.findings.map((item: Finding): string => item.suggestion)
    });
  }

  private async processImage(): Promise<void> {
    if (this.scanning) { return; }
    this.scanning = true;
    try {
      if (this.qrReport.status === 'decoded') {
        this.processedImageUri = await ProcessedImageService.maskLocal(this.abilityContext(), this.imageUri, this.qrReport);
        this.statusMessage = '已在端侧用不透明黑块遮挡全部二维码，未上传。文字和人物未遮挡，请放大复核。';
      } else if (this.imageId.length > 0 && this.processingMode !== 'local_only') {
        const transfer = this.imageTransfer;
        try {
          const masked = await GuardianApi.processAndDownloadImage(
            this.imageId, this.maskMode, this.processingMode, transfer);
          this.processedImageUri = await ProcessedImageService.cache(this.abilityContext(), masked.image);
          this.statusMessage = '远程处理完成，请复核遮挡范围。';
        } finally { this.resultMeta = '远程遮挡 · ' + transfer.describe(); }
      } else {
        throw new Error(this.processingMode === 'local_only'
          ? '仅本地模式只能遮挡二维码；切换到联网分析并重新选择图片后，可检测并遮挡文字与人物。'
          : '请重新选择图片并完成联网授权，再生成安全预览。');
      }
      this.processed = true;
      await HistoryStore.updateProcessed(this.abilityContext(), this.historyRecordId, this.statusMessage);
    } catch (error) {
      // A silent one-line hint was invisible in practice, so the reason a mask
      // could not be produced is surfaced as a dialog the user has to dismiss.
      const reason = this.errorMessage(error, '无法生成处理图');
      this.statusMessage = reason;
      await this.showNotice('无法生成安全预览', reason);
    } finally { this.scanning = false; }
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
      if (this.historyRecordId.length > 0) {
        await HistoryStore.updateAction(
          this.abilityContext(), this.historyRecordId, '安全图片已保存到系统相册', '已保存');
      }
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
      if (this.historyRecordId.length > 0) {
        await HistoryStore.updateAction(
          this.abilityContext(), this.historyRecordId, '已打开安全图片分享面板', '已分享');
      }
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

  /**
   * Modal notice for outcomes the user must acknowledge. A one-line hint under
   * the button was too easy to miss, so blocking failures (and blocked uploads)
   * are reported here instead.
   */
  private async showNotice(title: string, message: string): Promise<void> {
    try {
      await promptAction.showDialog({
        title: title,
        message: message,
        buttons: [{ text: '知道了', color: '#2563EB' }]
      });
    } catch (_) {
      // A dismissed or unavailable dialog must not break the flow; the same
      // text stays in the inline status line.
    }
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
        title: '隐私哨兵',
        subtitle: 'Privacy Sentinel · 图片分享前隐私检查'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '01 选择图片',
            copy: '选择要分享的图片，先在设备上完成检查。'
          }) {
            ProcessingModeSelector({
              mode: this.processingMode,
              disabled: this.scanning,
              onlineHint: '联网分析会识别图片中的文字；检测到敏感或无法确认安全的二维码时，原图不会上传。',
              onModeChange: (mode: ProcessingMode) => {
                this.processingMode = mode;
              }
            })

            Button(this.scanning ? '处理中…' : (this.hasImage ? '重新从文件选择' : '从手机文件选择图片'))
              .enabled(!this.scanning)
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.scanning ? '#94A3B8' : '#2563EB')
              .borderRadius(13)
              .margin({ top: 12 })
              .onClick(() => {
                this.pickFromFiles();
              })

            Button(this.scanning ? '处理中…' : '从系统相册选择')
              .enabled(!this.scanning)
              .width('100%')
              .height(42)
              .fontSize(13)
              .fontColor('#334155')
              .backgroundColor('#F1F5F9')
              .borderRadius(12)
              .margin({ top: 10 })
              .onClick(() => {
                this.pickFromAlbum();
              })


            if (this.hasImage) {
              Row() {
                Text(this.imageName)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#172033')
                Blank()
                Text(this.localComplete ? '本地检测完成' : '未完成')
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
            contextCopy: this.resultMeta,
            verdict: ScanPolicy.verdict(this.findings, this.localComplete, this.qrReport.uploadBlocked),
            emptyCopy: '将检查图片中的文字与二维码，并标出可处理的隐私区域。'
          })
          .margin({ top: 12 })

          if (this.hasImage) {
            Column() {
              SectionCard({
                title: '02 选择处理方式',
                copy: '二维码使用端侧不透明黑块遮挡全部码区；文字与人物不在此范围。无可靠坐标时明确提示，不能生成假安全图。'
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

                // Always render the outcome, not only on success: a failed mask
                // used to leave `processed` false, so the message was hidden
                // inside the success block and the button looked dead.
                if (this.statusMessage.length > 0) {
                  Text(this.statusMessage)
                    .fontSize(12)
                    .fontColor(this.processed ? '#166534' : '#B91C1C')
                    .lineHeight(19)
                    .padding(12)
                    .backgroundColor(this.processed ? '#F0FDF4' : '#FEF2F2')
                    .borderRadius(12)
                    .margin({ top: 10 })
                    .width('100%')
                }

                if (this.processed) {
                  Image(this.processedImageUri)
                    .width('100%')
                    .height(240)
                    .objectFit(ImageFit.Contain)
                    .backgroundColor('#E2E8F0')
                    .borderRadius(12)
                    .margin({ top: 12 })

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
