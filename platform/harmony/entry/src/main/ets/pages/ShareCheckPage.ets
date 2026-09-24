import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppHeader } from '../components/AppHeader';
import { ProcessingModeSelector } from '../components/ProcessingModeSelector';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import {
  CodeAnalyzeResponse,
  CodeVulnerability,
  DetectResponse,
  Finding,
  PrivacyItem,
  RiskLevel,
  ScanReport
} from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { ArchivePreview, ArchiveReview } from '../services/ArchiveReview';
import { HistoryStore } from '../services/HistoryStore';
import { LocalRuleEngine } from '../services/LocalRuleEngine';
import { ProcessedImageService } from '../services/ProcessedImageService';
import { QrContentService } from '../services/QrContentService';
import { QrImageReport, QrRules } from '../services/QrRules';
import { ShareOutService } from '../services/ShareOutService';
import { SignatureDB } from '../services/SignatureDB';
import { ThreatScanner } from '../services/ThreatScanner';
import { ProcessingMode, ScanPolicy } from '../services/ScanPolicy';
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
  @State historyRecordId: string = '';
  /**
   * Set when the backend was unreachable and the channel degraded to the
   * on-device rule engine, so the report can stop claiming a full check.
   */
  @State fallbackReason: string = '';
  @State mode: ProcessingMode = 'hybrid';
  private gateGeneration: number = 0;
  private qrReport: QrImageReport = QrRules.analyze([]);

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    emitter.on(SHARE_INTENT_CHANGE_EVENT_ID, () => {
      this.runGate();
    });
    this.runGate();
  }

  private async runGate(): Promise<void> {
    const generation: number = ++this.gateGeneration;
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
      const total: number = Math.min(intent.uris.length, 20);
      const combined: Finding[] = [];
      let combinedScore: number = 100;
      let failed: number = 0;
      for (let index = 0; index < total; index++) {
        const uri: string = intent.uris[index];
        const fileRoute: GateRoute = this.routeForUri(intent, uri);
        try {
          if (fileRoute === 'image') { await this.runImageRoute(uri); }
          else { await this.runDocRoute(uri); }
          this.findings.forEach((item: Finding) => combined.push({
            title: `文件 ${index + 1} · ${item.title}`, evidence: item.evidence,
            suggestion: item.suggestion, riskLevel: item.riskLevel
          }));
          combinedScore = Math.min(combinedScore, this.score);
        } catch (_) { failed++; }
        if (generation !== this.gateGeneration) { return; }
      }
      this.route = 'unknown';
      this.findings = combined;
      this.score = failed > 0 ? Math.min(combinedScore, 50) : combinedScore;
      this.riskLevel = this.localOverallRisk(combined);
      this.phase = 'report';
      this.sourceLabel = `批量分享（${total} 个文件）`;
      const overflow: number = intent.uris.length - total;
      this.multiImageHint = `已逐个扫描 ${total} 个文件，失败 ${failed} 个` +
        (overflow > 0 ? `；另有 ${overflow} 个超过单批 20 个上限，未扫描。` : '。');
      this.summary = this.multiImageHint + ' 批量报告不提供一键继续分享，请返回系统分享面板处理。';
      return;
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
        this.summary = '暂不支持该分享内容。请选择文件、图片、链接或代码片段。';
    }
  }

  private routeForUri(intent: ShareIntent, uri: string): GateRoute {
    if (intent.utd.includes('image') || this.hasFileExtension(uri, 'png|jpe?g|webp|bmp|gif')) {
      return 'image';
    }
    return 'doc';
  }

  private resetState(): void {
    this.phase = 'analyzing';
    this.findings = [];
    this.score = 100;
    this.riskLevel = 'low';
    this.summary = '正在进行安全检测…';
    this.suggestions = [];
    this.sourceLabel = '';
    this.sourceUri = '';
    this.imageId = '';
    this.processedImageUri = '';
    this.processed = false;
    this.multiImageHint = '';
    this.historyRecordId = '';
    this.sourceText = '';
    this.fallbackReason = '';
    this.qrReport = QrRules.analyze([]);
  }

  /**
   * Prefix for reports produced by the on-device engine after the backend was
   * unreachable. Kept explicit so a degraded scan is never mistaken for a
   * complete one.
   */
  private localCheckNotice(): string {
    return `检测服务不可达，已改用端侧离线检测（${this.fallbackReason}）：结果覆盖范围小于联网检测，建议人工复核。`;
  }

  private resolveRoute(intent: ShareIntent): GateRoute {
    if (intent.uris.length > 0) {
      if (intent.utd.includes('image')) {
        return 'image';
      }
      if (intent.utd.includes('pdf') || intent.utd.includes('word') ||
        intent.utd.includes('archive')) {
        return 'doc';
      }
      if (this.hasFileExtension(intent.uris[0], 'pdf|docx?|txt|md|zip')) {
        return 'doc';
      }
      if (this.hasFileExtension(intent.uris[0], 'png|jpe?g|webp|bmp|gif')) {
        return 'image';
      }
      // Any shared file without a dedicated module still receives the generic
      // binary/signature scan instead of being rejected by its extension.
      return 'doc';
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

  private async runImageRoute(imageUri: string, enhance: boolean = false): Promise<void> {
    this.sourceUri = imageUri;
    this.sourceLabel = '分享图片';
    const qr: QrImageReport = await QrContentService.decodeAll(imageUri);
    this.qrReport = qr;
    this.findings = qr.findings;
    this.score = qr.status === 'failed' ? 0 : this.localScore(this.findings);
    this.riskLevel = qr.status === 'failed' ? 'medium' : this.localOverallRisk(this.findings);
    this.summary = `${qr.note} 未执行 OCR，文字隐私无法判断。`;
    this.phase = 'report';
    if (enhance && this.mode === 'local_only') {
      this.summary += ' 当前为仅本地模式，未发送原图。';
    } else if (enhance && !qr.uploadBlocked) {
      try {
        const report = await GuardianApi.detectPrivacy(imageUri, 'shared-image.jpg', this.mode);
        this.imageId = report.imageId;
        this.findings = this.findings.concat(report.items.map((item: PrivacyItem): Finding => {
          return { title: item.label, evidence: item.text, suggestion: item.suggestion, riskLevel: item.riskLevel };
        }));
        this.score = Math.min(report.score, this.localScore(this.findings));
        this.riskLevel = this.highestRisk(this.findings, report.riskLevel);
        this.summary = '来源：端侧二维码与远程 OCR · 已授权上传原图。' + report.summary;
      } catch (_) {
        this.summary += ' 增强分析未完成，保留本地结果；如已同意发送，数据可能已到达服务器。不自动重试。';
      }
    } else if (enhance) {
      this.summary += ' 敏感二维码禁止上传原图。';
    }
    await this.recordHistory('privacy', '隐私哨兵', this.riskLevel, this.score, this.summary);
  }

  /** A code finding is reported once, by the on-device decoder. */
  private isQrFinding(title: string): boolean {
    return title.indexOf('码') >= 0 && title.indexOf('二维码') >= 0;
  }

  private highestRisk(findings: Finding[], fallback: RiskLevel): RiskLevel {
    const local: RiskLevel = this.localOverallRisk(findings);
    const order: number[] = [local, fallback].map((level: RiskLevel): number => {
      if (level === 'high') {
        return 2;
      }
      return level === 'medium' ? 1 : 0;
    });
    return order[0] >= order[1] ? local : fallback;
  }

  /** Same deduction scheme as the on-device rule engine. */
  private localScore(findings: Finding[]): number {
    let deduction = 0;
    findings.forEach((item: Finding) => {
      deduction += item.riskLevel === 'high' ? 28 : (item.riskLevel === 'medium' ? 16 : 7);
    });
    return Math.max(0, 100 - deduction);
  }

  private async processImage(): Promise<void> {
    this.phase = 'processing';
    this.summary = '正在生成脱敏图片…';
    try {
      if (this.qrReport.status === 'decoded') {
        this.processedImageUri = await ProcessedImageService.maskLocal(
          this.abilityContext(), this.sourceUri, this.qrReport);
        this.processed = true;
        this.phase = 'report';
        this.summary = '已在端侧用不透明黑块遮挡全部二维码，未上传原图。';
        if (this.historyRecordId.length > 0) {
          await HistoryStore.updateProcessed(this.abilityContext(), this.historyRecordId, '已端侧遮挡全部二维码');
        }
        return;
      }
      if (this.imageId.length === 0) {
        throw new Error('当前仅完成二维码检测；未获得可处理的远程 OCR 结果。');
      }
      const result =
        await GuardianApi.processPrivacy(this.imageId, this.maskMode);
      const imageData = await GuardianApi.downloadProcessedImage(result.processedImageUrl);
      this.processedImageUri =
        await ProcessedImageService.cache(this.abilityContext(), imageData);
      this.processed = true;
      this.phase = 'report';
      this.summary = result.message;
      if (this.historyRecordId.length > 0) {
        await HistoryStore.updateProcessed(
          this.abilityContext(), this.historyRecordId, `已使用${this.maskMode}方式脱敏`);
      }
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
      await this.recordShareAction('已打开脱敏图片分享面板');
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
      await this.recordShareAction('已知晓风险并打开原图分享面板');
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
      await this.recordShareAction('已打开文件分享面板');
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
      await ShareOutService.shareLink(this.abilityContext(), this.sourceText);
      await this.recordShareAction('已打开链接分享面板');
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
      await this.recordShareAction('已打开代码分享面板');
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
    this.summary = '正在执行端侧通用文件扫描（文件头/PE/PDF/压缩包/宏/哈希黑名单）…';
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
      let archiveNote: string = '';
      if (/\.zip$/i.test(this.sourceLabel)) {
        const preview: ArchivePreview = ArchiveReview.inspect(new Uint8Array(buffer), report);
        preview.sensitiveFiles.forEach((name: string) => this.findings.push({
          title: '压缩包含敏感文件名', evidence: name,
          suggestion: '移除密钥、环境配置或凭据文件后再分享。', riskLevel: 'high'
        }));
        archiveNote = ArchiveReview.describe(preview);
      }
      this.score = ScanPolicy.score(this.findings);
      this.riskLevel = ScanPolicy.risk(this.findings);
      this.summary = archiveNote.length > 0 ? archiveNote : `端侧引擎完成扫描：${this.sourceLabel}`;
      this.suggestions = ['确认文件来源可信后再保存或打开。'];
      this.phase = 'report';
      await this.recordHistory('doc', '提交护盾', this.riskLevel, this.score, this.summary);
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
    this.sourceText = url;
    this.sourceLabel = '分享链接';
    const local = LocalRuleEngine.scanLink(url, '分享面板');
    this.findings = local.findings;
    this.score = local.score;
    this.riskLevel = this.localOverallRisk(local.findings);
    this.summary = '本地静态检测完成 · 未上传。未查询域名信誉和跳转链路。';
    this.suggestions = ['请人工核对来源；未命中不代表安全。'];
    this.phase = 'report';
    await this.recordHistory('link', '链接卫士', this.riskLevel, this.score, this.summary);
  }

  private async runCodeRoute(code: string): Promise<void> {
    this.sourceText = code;
    this.sourceLabel = '分享代码';
    const local = LocalRuleEngine.scanCode(code);
    this.findings = local.findings;
    this.score = local.score;
    this.riskLevel = this.localOverallRisk(local.findings);
    this.summary = '本地代码检测完成 · 未上传。覆盖常见静态规则，不保证发现所有漏洞。';
    this.suggestions = ['不要执行未知代码，敏感凭据应移除并轮换。'];
    this.phase = 'report';
    await this.recordHistory('code', '代码卫士', this.riskLevel, this.score, this.summary);
  }

  /** Highest risk level across a finding list. */
  private localOverallRisk(findings: Finding[]): RiskLevel {
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

  private toRiskLevel(verdict: string): RiskLevel {
    if (verdict === 'malicious' || verdict === 'high') {
      return 'high';
    }
    if (verdict === 'suspicious' || verdict === 'medium') {
      return 'medium';
    }
    return 'low';
  }

  private async recordHistory(module: string, label: string,
    riskLevel: RiskLevel, score: number, summary: string): Promise<void> {
    try {
      this.historyRecordId = await HistoryStore.add(this.abilityContext(), {
        module: module as 'privacy' | 'code' | 'link' | 'doc',
        moduleLabel: label,
        riskLevel: riskLevel,
        score: score,
        summary: `[分享拦截] ${summary}`,
        sourceLabel: this.sourceLabel,
        // A degraded on-device scan must stay distinguishable in history.
        status: this.fallbackReason.length > 0 ? '端侧离线检测' : '待决策',
        findings: this.findings,
        suggestions: this.suggestions
      });
    } catch (_) {
    }
  }

  private async recordShareAction(action: string): Promise<void> {
    if (this.historyRecordId.length === 0) {
      return;
    }
    await HistoryStore.updateAction(
      this.abilityContext(), this.historyRecordId, action, '已发起分享');
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
      return '文件安全安检';
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

          ProcessingModeSelector({ mode: this.mode,
            disabled: this.phase === 'analyzing' || this.phase === 'processing',
            onModeChange: (value: ProcessingMode) => { this.mode = value; } })

          if (this.route === 'image' && this.sourceUri.length > 0 && this.phase === 'report') {
            Button('增强分析 原图将上传')
              .enabled(this.mode !== 'local_only')
              .onClick(() => { this.runImageRoute(this.sourceUri, true); })
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
            verdict: ScanPolicy.verdict(this.findings, this.phase === 'report', this.phase === 'offline'),
            contextCopy: '来源：端侧分享拦截；联网增强每次单独授权。',
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
              copy: '该内容类型依赖联网检测服务。请确认后端服务已启动，或稍后重试；文件（含 ZIP）、链接与代码片段支持端侧离线检测。'
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
