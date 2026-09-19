import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppHeader } from '../components/AppHeader';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import { DetectResponse, Finding, PrivacyItem, RiskLevel, ScanReport } from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { LocalRuleEngine } from '../services/LocalRuleEngine';
import { ProcessedImageService } from '../services/ProcessedImageService';
import { ShareOutService } from '../services/ShareOutService';
import { SignatureDB } from '../services/SignatureDB';
import { ThreatScanner } from '../services/ThreatScanner';
import { SHARE_INTENT_KEY, ShareIntent } from '../shareability/ShareCheckAbility';

type GateRoute = 'image' | 'doc' | 'link' | 'code' | 'unknown';
type GatePhase = 'analyzing' | 'report' | 'processing' | 'offline';

const SHARE_INTENT_CHANGE_EVENT_ID = 'guardianhub.shareIntentChange';
const MAX_DOC_SCAN_BYTES = 12 * 1024 * 1024;

interface GateResult {
  route: GateRoute;
  findings: Finding[];
  score: number;
  riskLevel: RiskLevel;
  summary: string;
  suggestions: string[];
}

@Entry
@Component
struct ShareCheckPage {
  @State phase: GatePhase = 'analyzing';
  @State route: GateRoute = 'unknown';
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State riskLevel: RiskLevel = 'low';
  @State summary: string = '正在分析分享内容…';
  @State suggestions: string[] = [];
  @State sourceLabel: string = '';
  @State sourceUri: string = '';
  /** Raw inspected text, kept so the code channel can continue sharing it. */
  @State sourceText: string = '';
  @State imageId: string = '';
  @State processedImageUri: string = '';
  @State processed: boolean = false;
  @State maskMode: string = 'black';
  @State multiImageHint: string = '';

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    emitter.on(SHARE_INTENT_CHANGE_EVENT_ID, () => {
      this.runGate();
    });
    this.runGate();
  }

  private runGate(): void {
    const intent: ShareIntent | undefined =
      AppStorage.get<ShareIntent>(SHARE_INTENT_KEY);
    if (!intent || (intent.uris.length === 0 && intent.text.length === 0)) {
      this.phase = 'report';
      this.route = 'unknown';
      this.findings = [];
      this.score = 100;
      this.summary = '未收到可检测的内容。请从系统分享面板选择 GuardianHub 隐私安检。';
      return;
    }
    this.resetState();
    if (intent.uris.length > 1) {
      this.multiImageHint = `收到 ${intent.uris.length} 个文件，本次仅检测第一个。`;
    }
    this.route = this.resolveRoute(intent);
    switch (this.route) {
      case 'image':
        this.runImageRoute(intent.uris[0]);
        break;
      case 'doc':
        this.runDocRoute(intent.uris[0]);
        break;
      case 'link':
        this.runLinkRoute(this.extractUrl(intent));
        break;
      case 'code':
        this.runCodeRoute(intent.text);
        break;
      default:
        this.phase = 'report';
        this.summary = '暂不支持该类型的内容。当前支持图片、PDF/Word 文档、链接和代码片段。';
    }
  }

  private resetState(): void {
    this.phase = 'analyzing';
    this.findings = [];
    this.score = 100;
    this.riskLevel = 'low';
    this.summary = '正在进行安全检测…';
    this.suggestions = [];
    this.imageId = '';
    this.processedImageUri = '';
    this.processed = false;
    this.multiImageHint = '';
    this.sourceText = '';
  }

  private resolveRoute(intent: ShareIntent): GateRoute {
    if (intent.uris.length > 0) {
      if (intent.utd.includes('image')) {
        return 'image';
      }
      if (intent.utd.includes('pdf') || intent.utd.includes('word')) {
        return 'doc';
      }
      if (this.hasFileExtension(intent.uris[0], 'pdf|docx?|txt|md')) {
        return 'doc';
      }
      if (this.hasFileExtension(intent.uris[0], 'png|jpe?g|webp|bmp|gif')) {
        return 'image';
      }
      return 'unknown';
    }
    const text = intent.text.trim();
    if (text.length === 0) {
      return 'unknown';
    }
    if (/^https?:\/\//i.test(text)) {
      return 'link';
    }
    if (this.looksLikeCode(text)) {
      return 'code';
    }
    if (/(https?:\/\/)/i.test(text)) {
      return 'link';
    }
    return 'unknown';
  }

  private hasFileExtension(uri: string, pattern: string): boolean {
    const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
    return new RegExp(`\\.(${pattern})$`, 'i').test(name);
  }

  private extractUrl(intent: ShareIntent): string {
    const text = intent.text.trim();
    const match = text.match(/https?:\/\/[^\s"'<>]+/i);
    return match !== null ? match[0] : text;
  }

  private looksLikeCode(text: string): boolean {
    let hits = 0;
    if (/(function|def |class |import |require\(|const |let |var )/i.test(text)) {
      hits++;
    }
    // Trailing block/semicolon, or the common interpreter shebang. Single-line
    // snippets from a share panel carry no newlines, so `$` is used without the
    // `m` flag on purpose.
    const trimmed = text.replace(/\s+$/, '');
    const tail = trimmed.charAt(trimmed.length - 1);
    if (tail === '}' || tail === ';' || trimmed.indexOf('#!') === 0) {
      hits++;
    }
    // Assignment with a non-space right-hand side. Requiring a quoted value
    // missed ordinary cases such as `api_key = abcdef123456`.
    if (/[A-Za-z_]\w*\s*=\s*[^\s]/.test(text)) {
      hits++;
    }
    // A genuine line break or a trailing line comment means this is very
    // unlikely to be plain prose. The comment check avoids a bare `//` so that
    // ordinary URLs are not mistaken for code.
    if (text.indexOf('\n') >= 0 || /(^|\s)\/\/\s*\S/.test(text)) {
      hits++;
    }
    return hits >= 2;
  }

  private async runImageRoute(imageUri: string): Promise<void> {
    this.sourceUri = imageUri;
    this.sourceLabel = this.fileNameFromUri(imageUri);
    this.summary = '正在进行 OCR、二维码和隐私规则检测…';
    try {
      const report: DetectResponse =
        await GuardianApi.detectPrivacy(imageUri, this.sourceLabel, 'local');
      this.imageId = report.imageId;
      this.findings = report.items.map((item: PrivacyItem): Finding => {
        return {
          title: item.label,
          evidence: item.text.length > 0 ? item.text : report.summary,
          suggestion: item.suggestion,
          riskLevel: item.riskLevel
        };
      });
      this.score = report.score;
      this.riskLevel = report.riskLevel;
      this.summary = report.summary;
      this.phase = 'report';
      await this.recordHistory('privacy', '隐私哨兵', report.riskLevel, report.score, report.summary);
    } catch (error) {
      this.phase = 'offline';
      this.summary = this.errorMessage(error, '图片检测失败');
    }
  }

  private async processImage(): Promise<void> {
    if (this.imageId.length === 0) {
      return;
    }
    this.phase = 'processing';
    this.summary = '正在生成脱敏图片…';
    try {
      const result =
        await GuardianApi.processPrivacy(this.imageId, this.maskMode);
      const imageData = await GuardianApi.downloadProcessedImage(result.processedImageUrl);
      this.processedImageUri =
        await ProcessedImageService.cache(this.abilityContext(), imageData);
      this.processed = true;
      this.phase = 'report';
      this.summary = result.message;
    } catch (error) {
      this.phase = 'report';
      this.summary = this.errorMessage(error, '脱敏图片生成失败');
    }
  }

  private async shareProcessedImage(): Promise<void> {
    if (this.processedImageUri.length === 0) {
      return;
    }
    try {
      await ProcessedImageService.share(this.abilityContext(), this.processedImageUri);
    } catch (error) {
      this.summary = this.errorMessage(error, '打开系统分享失败');
    }
  }

  private async shareOriginalImage(): Promise<void> {
    if (this.sourceUri.length === 0) {
      return;
    }
    try {
      await ProcessedImageService.share(this.abilityContext(), this.sourceUri);
    } catch (error) {
      this.summary = this.errorMessage(error, '打开系统分享失败');
    }
  }

  /**
   * Continue sharing the inspected document.
   *
   * The received URI is often not re-shareable, so ShareOutService falls back to
   * a sandbox copy of the bytes we already scanned.
   */
  private async shareCheckedFile(): Promise<void> {
    if (this.sourceUri.length === 0) {
      return;
    }
    try {
      await ShareOutService.shareFile(
        this.abilityContext(), this.sourceUri, this.sourceLabel);
    } catch (error) {
      this.summary = this.errorMessage(error, '继续分享失败');
    }
  }

  /** Continue sharing the inspected link. */
  private async shareCheckedLink(): Promise<void> {
    if (this.sourceLabel.length === 0) {
      return;
    }
    try {
      await ShareOutService.shareLink(this.abilityContext(), this.sourceLabel);
    } catch (error) {
      this.summary = this.errorMessage(error, '继续分享失败');
    }
  }

  /** Continue sharing the inspected code snippet. */
  private async shareCheckedCode(code: string): Promise<void> {
    if (code.length === 0) {
      return;
    }
    try {
      await ShareOutService.shareCode(this.abilityContext(), code);
    } catch (error) {
      this.summary = this.errorMessage(error, '继续分享失败');
    }
  }

  /**
   * Gate verdict copy for the non-image channels: the scan is done, the only
   * remaining decision is whether the user wants to keep sharing.
   */
  private continueCopy(): string {
    if (this.riskLevel === 'high') {
      return '该内容存在高风险项，建议返回发送方修改后再分享；如确需继续，请自行承担风险。';
    }
    if (this.riskLevel === 'medium') {
      return '该内容存在需要复核的项，确认无误后可继续分享。';
    }
    return '未发现明显风险，可继续分享。';
  }

  /** Risk-aware label so a risky item is never shared with one careless tap. */
  private continueLabel(): string {
    if (this.riskLevel === 'low') {
      return '继续分享';
    }
    return '已知晓风险，仍继续分享';
  }

  private async runDocRoute(fileUri: string): Promise<void> {
    this.sourceUri = fileUri;
    this.sourceLabel = this.fileNameFromUri(fileUri);
    this.summary = '正在执行端侧静态扫描（PE/PDF/ZIP/宏/哈希黑名单）…';
    try {
      await SignatureDB.ensureLoaded(this.abilityContext());
      const buffer: ArrayBuffer =
        await GuardianApi.readSelectedFile(fileUri, MAX_DOC_SCAN_BYTES);
      const report = ThreatScanner.scanFile(
        this.sourceLabel,
        new Uint8Array(buffer),
        { blacklist: SignatureDB.current() }
      );
      this.findings = report.findings.map((item): Finding => {
        return {
          title: item.label,
          evidence: item.evidence && item.evidence.length > 0 ?
            `${item.detail}（${item.evidence}）` : item.detail,
          suggestion: '确认文件来源可信后再保存或打开。',
          riskLevel: this.toRiskLevel(item.level)
        };
      });
      this.score = report.score;
      this.riskLevel = this.toRiskLevel(report.verdict);
      this.summary = `端侧引擎完成扫描：${this.sourceLabel}`;
      this.suggestions = ['确认文件来源可信后再保存或打开。'];
      this.phase = 'report';
      await this.recordHistory('doc', '提交护盾', this.riskLevel, report.score, this.summary);
    } catch (error) {
      this.phase = 'report';
      this.score = 0;
      this.riskLevel = 'medium';
      this.findings = [{
        title: '文件无法读取',
        evidence: this.errorMessage(error, '读取失败'),
        suggestion: '请确认文件大小未超出 12 MB 限制后重试。',
        riskLevel: 'medium'
      }];
      this.summary = '未完成扫描，建议人工确认文件内容。';
    }
  }

  private async runLinkRoute(url: string): Promise<void> {
    this.sourceLabel = url;
    this.summary = '正在对链接执行静态安全检查…';
    try {
      const report = await GuardianApi.checkLink(url, '分享面板');
      this.findings = report.checks.map((item): Finding => {
        return {
          title: item.label,
          evidence: item.message,
          suggestion: report.suggestions.length > 0 ? report.suggestions[0] : '请确认链接来源后访问。',
          riskLevel: item.riskLevel
        };
      });
      this.score = report.score;
      this.riskLevel = report.riskLevel;
      this.summary = report.summary;
      this.suggestions = report.suggestions;
      this.phase = 'report';
      await this.recordHistory('link', '链接卫士', report.riskLevel, report.score, report.summary);
    } catch (error) {
      this.phase = 'offline';
      this.summary = this.errorMessage(error, '链接检测失败');
    }
  }

  private async runCodeRoute(code: string): Promise<void> {
    this.sourceLabel = '分享的代码片段';
    this.sourceText = code;
    this.summary = '正在执行端侧代码规则扫描…';
    const report: ScanReport = LocalRuleEngine.scanCode(code);
    this.findings = report.findings;
    this.score = report.score;
    this.riskLevel = this.overallRisk(report.findings);
    this.summary = report.findings.length > 0 ?
      `端侧规则引擎发现 ${report.findings.length} 项风险。` :
      '端侧规则引擎未发现明显风险，仍建议人工复核。';
    this.suggestions = ['修复后再提交或分享该代码。'];
    this.phase = 'report';
    await this.recordHistory('code', '代码卫士', this.riskLevel, report.score, this.summary);
  }

  private toRiskLevel(verdict: string): RiskLevel {
    if (verdict === 'malicious' || verdict === 'high') {
      return 'high';
    }
    if (verdict === 'suspicious' || verdict === 'medium') {
      return 'medium';
    }
    return 'low';
  }

  private overallRisk(findings: Finding[]): RiskLevel {
    let risk: RiskLevel = 'low';
    findings.forEach((item: Finding) => {
      if (item.riskLevel === 'high') {
        risk = 'high';
      } else if (item.riskLevel === 'medium' && risk !== 'high') {
        risk = 'medium';
      }
    });
    return risk;
  }

  private async recordHistory(module: string, label: string,
    riskLevel: RiskLevel, score: number, summary: string): Promise<void> {
    try {
      await HistoryStore.add(this.abilityContext(), {
        module: module as 'privacy' | 'code' | 'link' | 'doc',
        moduleLabel: label,
        riskLevel: riskLevel,
        score: score,
        summary: `[分享拦截] ${summary}`
      });
    } catch (_) {
    }
  }

  private fileNameFromUri(uri: string): string {
    const rawName = uri.substring(uri.lastIndexOf('/') + 1);
    return decodeURIComponent(rawName) || 'shared-file';
  }

  private errorMessage(error: Object, fallback: string): string {
    const typedError = error as Error;
    return typedError.message ? `${fallback}：${typedError.message}` : fallback;
  }

  private routeTitle(): string {
    if (this.route === 'image') {
      return '图片隐私安检';
    }
    if (this.route === 'doc') {
      return '文档安全安检';
    }
    if (this.route === 'link') {
      return '链接安全安检';
    }
    if (this.route === 'code') {
      return '代码安全安检';
    }
    return '隐私安检';
  }

  private routeIcon(): string {
    if (this.route === 'image') {
      return '🖼';
    }
    if (this.route === 'doc') {
      return '📄';
    }
    if (this.route === 'link') {
      return '🔗';
    }
    if (this.route === 'code') {
      return '⌨';
    }
    return '🛡';
  }

  private bannerColor(): string {
    if (this.phase === 'analyzing' || this.phase === 'processing') {
      return '#EFF6FF';
    }
    if (this.riskLevel === 'high') {
      return '#FEF2F2';
    }
    if (this.riskLevel === 'medium') {
      return '#FFFBEB';
    }
    return '#F0FDF4';
  }

  private bannerTextColor(): string {
    if (this.phase === 'analyzing' || this.phase === 'processing') {
      return '#1D4ED8';
    }
    if (this.riskLevel === 'high') {
      return '#B91C1C';
    }
    if (this.riskLevel === 'medium') {
      return '#B45309';
    }
    return '#15803D';
  }

  private bannerText(): string {
    if (this.phase === 'analyzing') {
      return '安检进行中，请稍候…';
    }
    if (this.phase === 'processing') {
      return '正在生成脱敏图片…';
    }
    if (this.phase === 'offline') {
      return '检测服务不可达，已暂停安检';
    }
    if (this.riskLevel === 'high') {
      return '检测到高风险内容，建议处理后继续';
    }
    if (this.riskLevel === 'medium') {
      return '检测到需复核内容，请谨慎操作';
    }
    return '未发现明显风险，可继续操作';
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
        title: 'GuardianHub 隐私安检',
        subtitle: this.routeTitle()
      })

      Scroll() {
        Column() {
          Column() {
            Text(`${this.routeIcon()} ${this.bannerText()}`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.bannerTextColor())
              .lineHeight(20)
              .width('100%')
            if (this.sourceLabel.length > 0) {
              Text(this.sourceLabel)
                .fontSize(11)
                .fontColor('#64748B')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 6 })
                .width('100%')
            }
            if (this.multiImageHint.length > 0) {
              Text(this.multiImageHint)
                .fontSize(11)
                .fontColor('#D97706')
                .margin({ top: 4 })
                .width('100%')
            }
          }
          .padding(14)
          .backgroundColor(this.bannerColor())
          .borderRadius(14)
          .width('100%')

          if (this.route === 'image' && this.sourceUri.length > 0 && this.phase === 'report') {
            Image(this.sourceUri)
              .width('100%')
              .height(200)
              .objectFit(ImageFit.Contain)
              .backgroundColor('#E2E8F0')
              .borderRadius(12)
              .margin({ top: 12 })
          }

          ResultPanel({
            findings: this.findings,
            score: this.score,
            emptyCopy: this.summary
          })
          .margin({ top: 12 })

          if (this.phase === 'report' && this.route !== 'unknown') {
            Column() {
              SectionCard({
                title: this.route === 'image' ? '处置建议' : '是否继续分享',
                copy: this.route === 'image' ? this.summary : this.continueCopy()
              }) {
                ForEach(this.suggestions, (tip: string) => {
                  Text(`· ${tip}`)
                    .fontSize(12)
                    .fontColor('#475569')
                    .lineHeight(19)
                    .width('100%')
                }, (tip: string) => tip)

                if (this.route === 'link') {
                  Button(this.continueLabel())
                    .width('100%')
                    .height(44)
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .backgroundColor(this.riskLevel === 'high' ? '#DC2626' : '#15803D')
                    .borderRadius(12)
                    .margin({ top: 12 })
                    .onClick(() => {
                      this.shareCheckedLink();
                    })
                }

                if (this.route === 'code') {
                  Button(this.continueLabel())
                    .width('100%')
                    .height(44)
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .backgroundColor(this.riskLevel === 'high' ? '#DC2626' : '#15803D')
                    .borderRadius(12)
                    .margin({ top: 12 })
                    .onClick(() => {
                      this.shareCheckedCode(this.sourceText);
                    })
                }

                if (this.route === 'doc') {
                  Button(this.continueLabel())
                    .width('100%')
                    .height(44)
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .backgroundColor(this.riskLevel === 'high' ? '#DC2626' : '#15803D')
                    .borderRadius(12)
                    .margin({ top: 12 })
                    .onClick(() => {
                      this.shareCheckedFile();
                    })
                }

                if (this.route === 'image' && this.riskLevel !== 'low') {
                  Row() {
                    ForEach(['black', 'blur', 'mosaic'], (mode: string) => {
                      Button(this.modeLabel(mode))
                        .layoutWeight(1)
                        .height(38)
                        .fontSize(12)
                        .fontColor(this.maskMode === mode ? '#FFFFFF' : '#334155')
                        .backgroundColor(this.maskMode === mode ? '#2563EB' : '#F1F5F9')
                        .borderRadius(10)
                        .margin({ right: mode === 'mosaic' ? 0 : 8 })
                        .onClick(() => {
                          this.maskMode = mode;
                          this.processed = false;
                          this.processedImageUri = '';
                        })
                    }, (mode: string) => mode)
                  }
                  .width('100%')
                  .margin({ top: 12 })

                  if (!this.processed) {
                    Button('一键脱敏并生成安全图片')
                      .width('100%')
                      .height(44)
                      .fontSize(14)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#2563EB')
                      .borderRadius(12)
                      .margin({ top: 12 })
                      .onClick(() => {
                        this.processImage();
                      })
                  } else {
                    Image(this.processedImageUri)
                      .width('100%')
                      .height(220)
                      .objectFit(ImageFit.Contain)
                      .backgroundColor('#E2E8F0')
                      .borderRadius(12)
                      .margin({ top: 12 })

                    Row() {
                      Button('分享安全图片')
                        .layoutWeight(1)
                        .height(42)
                        .fontSize(12)
                        .fontColor('#FFFFFF')
                        .backgroundColor('#15803D')
                        .borderRadius(11)
                        .margin({ right: 8 })
                        .onClick(() => {
                          this.shareProcessedImage();
                        })

                      Button('重新脱敏')
                        .layoutWeight(1)
                        .height(42)
                        .fontSize(12)
                        .fontColor('#334155')
                        .backgroundColor('#F1F5F9')
                        .borderRadius(11)
                        .onClick(() => {
                          this.processed = false;
                          this.processedImageUri = '';
                        })
                    }
                    .width('100%')
                    .margin({ top: 10 })
                  }

                  Button('我已知晓风险，仍分享原图')
                    .width('100%')
                    .height(40)
                    .fontSize(12)
                    .fontColor('#DC2626')
                    .backgroundColor('#FEF2F2')
                    .borderRadius(11)
                    .margin({ top: 10 })
                    .onClick(() => {
                      this.shareOriginalImage();
                    })
                }

                if (this.route === 'image' && this.riskLevel === 'low') {
                  Button('直接分享原图')
                    .width('100%')
                    .height(44)
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#15803D')
                    .borderRadius(12)
                    .margin({ top: 12 })
                    .onClick(() => {
                      this.shareOriginalImage();
                    })
                }
              }
            }
            .width('100%')
            .margin({ top: 12 })
          }

          if (this.phase === 'offline') {
            SectionCard({
              title: '检测服务不可达',
              copy: '该内容类型依赖联网检测服务。请确认后端服务已启动，或稍后重试；文档与代码片段支持端侧离线检测。'
            }) {
              Button('重试检测')
                .width('100%')
                .height(42)
                .fontSize(13)
                .fontColor('#1D4ED8')
                .backgroundColor('#DBEAFE')
                .borderRadius(11)
                .margin({ top: 10 })
                .onClick(() => {
                  this.runGate();
                })
            }
          }
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 28 })
        .width('100%')
      }
      .layoutWeight(1)
    }
    .backgroundColor('#F4F7FB')
    .width('100%')
    .height('100%')
  }
}
