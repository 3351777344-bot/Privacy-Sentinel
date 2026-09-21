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
  @State snippetStatus: string = '默认联网增强会调用 DeepSeek；ZIP 项目包为保护源码仍只做本地全量扫描。';
  @State processingMode: ProcessingMode = 'online';

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

  private async scan(): Promise<void> {
    if (this.codeText.trim().length === 0) {
      this.snippetStatus = '请先输入待检测代码';
      return;
    }
    this.scanningSnippet = true;
    this.snippetStatus = this.processingMode === 'online' ?
      '正在调用 DeepSeek 联网增强分析…' :
      '正在执行本地规则检测…';
    try {
      const report: CodeAnalyzeResponse =
        await GuardianApi.analyzeCodeText(this.codeText, 'auto', this.processingMode);
      this.score = report.score;
      this.findings = this.mapVulnerabilities(report);
      const source = report.detectorSource ?? 'rule';
      this.snippetStatus =
        `${report.summary} · 来源 ${source}` +
        (report.deepseekWarning ? `\n${report.deepseekWarning}` : '');
      await HistoryStore.add(this.abilityContext(), {
        module: 'code',
        moduleLabel: '代码卫士',
        riskLevel: report.riskLevel,
        score: report.score,
        summary: report.summary,
        sourceLabel: '代码片段',
        findings: this.findings,
        suggestions: report.suggestions
      });
    } catch (error) {
      this.snippetStatus = this.errorMessage(error, '代码检测失败');
    } finally {
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

  private async scanArchive(): Promise<void> {
    if (this.archiveUri.length === 0) {
      this.archiveStatus = '请先选择 ZIP 项目包';
      return;
    }
    this.scanningArchive = true;
    this.archiveStatus = '正在上传到私有服务并执行只读扫描…';
    try {
      const report: CodeAnalyzeResponse =
        await GuardianApi.analyzeCodeArchive(
          this.archiveUri,
          this.archiveName,
          this.processingMode
        );
      this.score = report.score;
      this.findings = this.mapVulnerabilities(report);
      const scanned = report.scannedFiles ?? 0;
      const skipped = report.skippedFiles ?? 0;
      this.archiveStatus =
        `已扫描 ${scanned} 个文件，跳过 ${skipped} 个；` +
        `${report.shouldSubmit ? '可以进入人工复核' : '暂不建议直接提交'}` +
        (report.deepseekWarning ? `\n${report.deepseekWarning}` : '');
      await HistoryStore.add(this.abilityContext(), {
        module: 'code',
        moduleLabel: '代码卫士',
        riskLevel: report.riskLevel,
        score: report.score,
        summary: report.summary,
        sourceLabel: this.archiveName,
        findings: this.findings,
        suggestions: report.suggestions
      });
    } catch (error) {
      this.archiveStatus = this.errorMessage(error, '项目包扫描失败');
    } finally {
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
            copy: '代码片段联网时调用 DeepSeek；ZIP 即使选联网也只做本地全量扫描，不会整包外发。'
          }) {
            ProcessingModeSelector({
              mode: this.processingMode,
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
              copy: '系统文件选择器只接收 ZIP；后端在内存中只读扫描，不执行、编译或导入代码。'
            }) {
              Button(this.archiveName.length > 0 ? '重新选择项目包' : '选择 ZIP 项目包')
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
