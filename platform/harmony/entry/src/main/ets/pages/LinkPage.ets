import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppHeader } from '../components/AppHeader';
import { ProcessingModeSelector } from '../components/ProcessingModeSelector';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import { Finding, LinkCheckItem, LinkCheckResponse } from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { LocalRuleEngine } from '../services/LocalRuleEngine';
import { QrContentService } from '../services/QrContentService';
import { QrImageReport } from '../services/QrRules';
import { ProcessingMode, ScanPolicy, TransferSession } from '../services/ScanPolicy';

@Entry
@Component
struct LinkPage {
  @State urlText: string = 'http://xn--campus-login.example/login?redirect=payment&token=demo';
  @State sourceText: string = '陌生短信';
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State statusMessage: string = '等待检测';
  @State resultMeta: string = '尚未检测';
  @State scanning: boolean = false;
  @State complete: boolean = false;
  @State mode: ProcessingMode = 'hybrid';
  private rawQrUrls: string[] = [];
  private qrFindings: Finding[] = [];
  private qrBlocked: boolean = false;

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async saveHistory(summary: string): Promise<void> {
    await HistoryStore.add(this.abilityContext(), {
      module: 'link', moduleLabel: '链接卫士', riskLevel: ScanPolicy.risk(this.findings),
      score: this.score, summary: summary, sourceLabel: '端侧链接检查', findings: this.findings,
      suggestions: this.findings.map((item: Finding): string => item.suggestion)
    });
  }

  private async scan(enhance: boolean = false): Promise<void> {
    const targets: string[] = this.qrFindings.length > 0 ? this.rawQrUrls.slice() : [this.urlText.trim()];
    if (this.qrFindings.length === 0 && (targets.length === 0 || targets[0].length === 0)) {
      this.statusMessage = '请先输入链接或解析二维码'; return;
    }
    const mode: ProcessingMode = this.mode;
    const transfer = new TransferSession(mode);
    this.scanning = true;
    this.complete = true;
    const localFindings: Finding[] = this.qrFindings.slice();
    targets.forEach((target: string) => {
      LocalRuleEngine.scanLink(target, this.sourceText).findings.forEach((item: Finding) => localFindings.push(item));
    });
    this.findings = localFindings;
    this.score = ScanPolicy.score(this.findings);
    this.statusMessage = targets.length > 0 ?
      `端侧已检查 ${targets.length} 个完整链接；未访问目标地址、未查询跳转链。` :
      '二维码载荷已在端侧分类；其中没有可执行链接检查的 URL。';
    await this.saveHistory(this.statusMessage);
    try {
      if (ScanPolicy.shouldEnhance(mode, enhance) && !this.qrBlocked && targets.length > 0) {
        const remote: Finding[] = [];
        for (let index = 0; index < targets.length; index++) {
          const session = index === 0 ? transfer : new TransferSession(mode);
          const report: LinkCheckResponse = await GuardianApi.checkLink(targets[index], this.sourceText, session);
          report.checks.forEach((item: LinkCheckItem) => remote.push({
            title: item.label, evidence: item.message,
            suggestion: report.suggestions.length > 0 ? report.suggestions[0] : '打开前再次核对域名。',
            riskLevel: item.riskLevel
          }));
        }
        this.findings = localFindings.concat(remote);
        this.score = ScanPolicy.score(this.findings);
        this.statusMessage += ' 联网增强完成。';
        await this.saveHistory(this.statusMessage);
      } else if (this.qrBlocked && enhance) {
        this.statusMessage += ' 二维码含敏感载荷或解析失败，已阻止上传。';
      }
    } catch (error) {
      this.statusMessage += ` 增强分析未完成：${this.errorMessage(error, '请求失败')}`;
    } finally {
      this.resultMeta = `来源：端侧静态规则；${transfer.describe()}`;
      this.scanning = false;
    }
  }

  private async pickQrImage(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const selected = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (selected.photoUris.length === 0) { return; }
      this.scanning = true;
      const report: QrImageReport = await QrContentService.decodeAll(selected.photoUris[0]);
      this.rawQrUrls = [];
      report.codes.forEach((item) => { if (item.url.length > 0) { this.rawQrUrls.push(item.url); } });
      this.qrBlocked = report.uploadBlocked;
      this.qrFindings = report.findings.slice();
      this.findings = report.findings;
      this.score = ScanPolicy.score(this.findings);
      this.complete = report.status !== 'failed';
      this.sourceText = '二维码图片';
      this.urlText = report.codes.map((item): string => item.text).join('\n');
      this.statusMessage = report.note;
      this.resultMeta = '来源：端侧二维码解码；未上传；界面仅展示脱敏内容。';
      await this.saveHistory(this.statusMessage);
    } catch (error) {
      this.complete = false; this.qrBlocked = true;
      this.statusMessage = this.errorMessage(error, '二维码解析失败');
    } finally { this.scanning = false; }
  }

  private errorMessage(error: Object, fallback: string): string {
    const typedError = error as Error;
    return typedError.message ? `${fallback}：${typedError.message}` : fallback;
  }

  build() {
    Column() {
      AppHeader({ title: 'Link Guard', subtitle: '点击前静态安全体检' })
      Scroll() {
        Column() {
          SectionCard({ title: '01 输入链接与来源', copy: '二维码完整载荷仅在内存中参与端侧分析；界面与历史只保存脱敏内容。' }) {
            TextArea({ text: this.urlText, placeholder: 'https://example.com/path' })
              .height(105).fontSize(13).backgroundColor('#F8FAFC').borderRadius(12).padding(11).enabled(!this.scanning)
              .onChange((value: string) => {
                this.urlText = value; this.rawQrUrls = []; this.qrFindings = []; this.qrBlocked = false;
              })
            TextInput({ text: this.sourceText, placeholder: '例如：学校官网、短信、群聊' })
              .height(44).fontSize(13).backgroundColor('#F8FAFC').borderRadius(12).margin({ top: 10 }).enabled(!this.scanning)
              .onChange((value: string) => { this.sourceText = value; })
            Button('从相册解析全部二维码').width('100%').height(42).fontSize(13).fontColor('#0F766E')
              .backgroundColor('#CCFBF1').borderRadius(12).margin({ top: 12 }).enabled(!this.scanning)
              .onClick(() => { this.pickQrImage(); })
            ProcessingModeSelector({ mode: this.mode, disabled: this.scanning,
              onModeChange: (value: ProcessingMode) => { this.mode = value; } })
            Button(this.scanning ? '检测中…' : '执行端侧检测').width('100%').height(46).margin({ top: 10 })
              .enabled(!this.scanning).onClick(() => { this.scan(false); })
            if (this.mode !== 'local_only') {
              Button('增强分析 · 本次授权').width('100%').height(42).margin({ top: 8 })
                .enabled(!this.scanning && !this.qrBlocked).onClick(() => { this.scan(true); })
            }
            Text(this.statusMessage).fontSize(12).fontColor('#64748B').lineHeight(19).margin({ top: 9 }).width('100%')
          }
          ResultPanel({ findings: this.findings, score: this.score,
            verdict: ScanPolicy.verdict(this.findings, this.complete, this.qrBlocked), contextCopy: this.resultMeta,
            emptyCopy: '检测 HTTPS、IP 直连、Punycode、短链、敏感参数和来源风险。' }).margin({ top: 12 })
        }.padding({ left: 16, right: 16, bottom: 28 }).width('100%')
      }.layoutWeight(1)
    }.backgroundColor('#F4F7FB').width('100%').height('100%')
  }
}
