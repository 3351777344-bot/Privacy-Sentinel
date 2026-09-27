import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppHeader } from '../components/AppHeader';
import { ProcessingMode, ProcessingModeSelector } from '../components/ProcessingModeSelector';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import {
  CodeAnalyzeResponse,
  CodeVulnerability,
  Finding
} from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { LocalRuleEngine } from '../services/LocalRuleEngine';
import { ThreatScanner } from '../services/ThreatScanner';
import { ArchiveReview } from '../services/ArchiveReview';
import { ScanPolicy, TransferSession } from '../services/ScanPolicy';

@Entry
@Component
struct CodePage {
  @State codeText: string =
    'const api_key = "sk-demo-secret";\n' +
    'db.execute("SELECT * FROM users WHERE id=" + userId);\n' +
    'console.log("token", token);';
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State archiveUri: string = '';
  @State archiveName: string = '';
  @State archiveStatus: string = '尚未选择项目包';
  @State scanningArchive: boolean = false;
  @State scanningSnippet: boolean = false;
  @State snippetStatus: string = '默认端侧扫描，不上传；选择增强分析后仍需授权本次发送。';
  @State processingMode: ProcessingMode = 'hybrid';

  @State resultMeta: string = '尚未检测';
  @State completed: boolean = false;
  @State archivePreview: string = '';

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private mapVulnerabilities(report: CodeAnalyzeResponse): Finding[] {
    return report.vulnerabilities.map((item: CodeVulnerability): Finding => {
      const location = item.filePath ?
        `${item.filePath}${item.line ? `:${item.line}` : ''}` :
        (item.line ? `行 ${item.line}` : '代码片段');
      return {
        title: item.title,
        evidence: `${location} · ${item.reason}`,
        suggestion: item.suggestion,
        riskLevel: item.riskLevel
      };
    });
  }

  private async saveLocal(label: string, summary: string): Promise<void> {
    await HistoryStore.add(this.abilityContext(), {
      module: 'code', moduleLabel: '代码卫士', riskLevel: ScanPolicy.risk(this.findings),
      score: this.score, summary: summary, sourceLabel: label, findings: this.findings,
      suggestions: this.findings.map((item: Finding): string => item.suggestion)
    });
  }

  private async scan(enhance: boolean = false): Promise<void> {
    if (this.scanningSnippet || this.scanningArchive) { return; }
    const code = this.codeText;
    if (!code.trim()) { this.snippetStatus = '请先输入代码'; return; }
    const mode = this.processingMode;
    const transfer = new TransferSession(mode);
    this.scanningSnippet = true;
    try {
      const local = LocalRuleEngine.scanCode(code);
      this.findings = local.findings;
      this.score = ScanPolicy.score(this.findings);
      this.completed = true;
      this.snippetStatus = '端侧规则检测完成；不覆盖完整语义与依赖漏洞。';
      await this.saveLocal('代码片段', this.snippetStatus + ' 未发送。');
      if (ScanPolicy.shouldEnhance(mode, enhance)) {
        try {
          const report = await GuardianApi.analyzeCodeText(code, 'auto', mode, transfer);
          this.findings = local.findings.concat(this.mapVulnerabilities(report));
          this.score = ScanPolicy.score(this.findings);
          this.snippetStatus += ' 远程来源：' + (report.detectorSource || '规则') + '。' + report.summary;
          await this.saveLocal('代码增强', this.snippetStatus + ' ' + transfer.describe());
        } catch (error) {
          this.snippetStatus += ' ' + this.errorMessage(error, '增强未完成');
        }
      }
    } finally {
      this.resultMeta = (transfer.state === 'sent' ? '端侧与远程 · ' : '端侧 · ') + transfer.describe();
      this.snippetStatus += ' ' + transfer.describe();
      this.scanningSnippet = false;
    }
  }

  private async pickArchive(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['ZIP 项目包|.zip'];
      options.maxSelectNumber = 1;
      const result = await new picker.DocumentViewPicker().select(options);
      if (result.length === 0) {
        return;
      }
      this.archiveUri = result[0];
      this.archiveName = this.fileNameFromUri(result[0]);
      this.archiveStatus = '已选择，等待安全扫描';
    } catch (error) {
      this.archiveStatus = this.errorMessage(error, '未能打开系统文件选择器');
    }
  }

  private async scanArchive(enhance: boolean = false): Promise<void> {
    if (this.scanningArchive || this.scanningSnippet) { return; }
    if (!this.archiveUri) { this.archiveStatus = '请先选择ZIP'; return; }
    const uri = this.archiveUri;
    const name = this.archiveName;
    const mode = this.processingMode;
    const transfer = new TransferSession(mode);
    this.scanningArchive = true;
    try {
      const data = new Uint8Array(await GuardianApi.readSelectedFile(uri, 10 * 1024 * 1024));
      const local = ThreatScanner.scanFile(name, data);
      const preview = ArchiveReview.inspect(data, local);
      this.archivePreview = ArchiveReview.describe(preview);
      this.findings = local.findings.map((item): Finding => {
        return { title: item.label, evidence: item.detail, suggestion: '人工复核，不运行未知代码。',
          riskLevel: item.level === 'high' ? 'high' : (item.level === 'medium' ? 'medium' : 'low') };
      });
      this.score = ScanPolicy.score(this.findings);
      this.completed = true;
      this.archiveStatus = 'ZIP端侧扫描完成，原包未发送。';
      await this.saveLocal('ZIP项目包', this.archiveStatus);
      if (ScanPolicy.shouldEnhance(mode, enhance)) {
        if (!preview.canEnhance) { this.archiveStatus += ' 结构无效或条目超限，禁止增强。'; }
        else {
          try {
            const report = await GuardianApi.analyzeCodeText(preview.summary, 'auto', mode, transfer,
              this.archivePreview + '\n只解释静态摘要，不执行源码审计。');
            this.archiveStatus += ' 摘要增强结果：' + report.summary;
            await this.saveLocal('ZIP摘要增强', this.archiveStatus + ' ' + transfer.describe());
          } catch (error) { this.archiveStatus += ' ' + this.errorMessage(error, '增强未完成'); }
        }
      }
    } catch (error) {
      this.completed = false;
      this.archiveStatus = this.errorMessage(error, '项目包未完成检测');
    } finally {
      this.resultMeta = '端侧文件扫描 · ' + transfer.describe();
      this.archiveStatus += ' ' + transfer.describe();
      this.scanningArchive = false;
    }
  }

  private fileNameFromUri(uri: string): string {
    const rawName = uri.substring(uri.lastIndexOf('/') + 1);
    return decodeURIComponent(rawName) || 'project.zip';
  }

  private errorMessage(error: Object, fallback: string): string {
    const typedError = error as Error;
    return typedError.message ? `${fallback}：${typedError.message}` : fallback;
  }

  build() {
    Column() {
      AppHeader({
        title: 'Code Guardian',
        subtitle: '代码提交前安全检查'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '处理模式',
            copy: '默认端侧扫描。ZIP增强仅发送计数、规则编号与结论，不发送原包和源码。'
          }) {
            ProcessingModeSelector({
              mode: this.processingMode,
              disabled: this.scanningSnippet || this.scanningArchive,
              onlineHint: 'DeepSeek 增强',
              onModeChange: (mode: ProcessingMode) => {
                this.processingMode = mode;
              }
            })
          }

          Column() {
            SectionCard({
              title: '01 输入代码片段',
              copy: '联网增强会在本地规则基础上调用 DeepSeek，失败时自动回退本地结果。'
            }) {
              TextArea({
                text: this.codeText,
                placeholder: '粘贴待提交代码'
              })
                .height(210)
                .fontSize(13)
                .fontColor('#172033')
                .backgroundColor('#F8FAFC')
                .borderRadius(12)
                .padding(12)
                .onChange((value: string) => {
                  this.codeText = value;
                })

              Button('增强当前代码 需授权')
                .enabled(this.processingMode !== 'local_only' && !this.scanningSnippet && !this.scanningArchive)
                .onClick(() => { this.scan(true); })
              Text(this.snippetStatus)
                .fontSize(12)
                .fontColor('#64748B')
                .lineHeight(19)
                .margin({ top: 10 })
                .width('100%')

              Button(this.scanningSnippet ? '检测中…' :
                (this.processingMode === 'online' ? '开始 DeepSeek 增强检测' : '开始本地代码检测'))
                .enabled(!this.scanningSnippet)
                .width('100%')
                .height(46)
                .fontSize(14)
                .fontColor('#FFFFFF')
                .backgroundColor(this.scanningSnippet ? '#94A3B8' : '#7C3AED')
                .borderRadius(13)
                .margin({ top: 12 })
                .onClick(() => {
                  this.scan();
                })
            }
          }
          .width('100%')
          .margin({ top: 12 })

          Column() {
            SectionCard({
              title: '02 上传 ZIP 项目包',
              copy: '端侧只读检查ZIP结构与内容；列出包内数量和敏感文件，增强只发送无原文摘要。'
            }) {
              Button(this.archiveName.length > 0 ? '重新选择项目包' : '选择 ZIP 项目包')
                .enabled(!this.scanningArchive && !this.scanningSnippet)
                .width('100%')
                .height(44)
                .fontSize(13)
                .fontColor('#6D28D9')
                .backgroundColor('#EDE9FE')
                .borderRadius(12)
                .onClick(() => {
                  this.pickArchive();
                })

              if (this.archiveName.length > 0) {
                Text(this.archiveName)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#172033')
                  .margin({ top: 10 })
                  .width('100%')
              }

              Text(this.archivePreview).fontSize(12).fontColor('#475569').margin({ top: 10 })
              Button('增强ZIP摘要 不上传原包')
                .enabled(this.processingMode !== 'local_only' && !this.scanningArchive && !this.scanningSnippet)
                .onClick(() => { this.scanArchive(true); })
              Text(this.archiveStatus)
                .fontSize(12)
                .fontColor('#64748B')
                .lineHeight(19)
                .margin({ top: 8 })
                .width('100%')

              Button(this.scanningArchive ? '扫描中…' : '开始项目包安全审查')
                .enabled(!this.scanningArchive)
                .width('100%')
                .height(46)
                .fontSize(14)
                .fontColor('#FFFFFF')
                .backgroundColor(this.scanningArchive ? '#94A3B8' : '#7C3AED')
                .borderRadius(13)
                .margin({ top: 12 })
                .onClick(() => {
                  this.scanArchive();
                })
            }
          }
          .width('100%')
          .margin({ top: 12 })

          ResultPanel({
            findings: this.findings,
            score: this.score,
            contextCopy: this.resultMeta,
            verdict: ScanPolicy.verdict(this.findings, this.completed),
            emptyCopy: '点击检测后，报告将展示风险原因和提交前修改建议。'
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
