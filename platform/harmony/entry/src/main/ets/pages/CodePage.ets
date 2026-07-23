import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppHeader } from '../components/AppHeader';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import {
  CodeAnalyzeResponse,
  CodeVulnerability,
  Finding,
  RiskLevel,
  ScanReport
} from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { LocalRuleEngine } from '../services/LocalRuleEngine';

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

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async scan(): Promise<void> {
    const report: ScanReport = LocalRuleEngine.scanCode(this.codeText);
    this.findings = report.findings;
    this.score = report.score;
    let riskLevel: RiskLevel = 'low';
    report.findings.forEach((item: Finding) => {
      if (item.riskLevel === 'high') {
        riskLevel = 'high';
      } else if (item.riskLevel === 'medium' && riskLevel !== 'high') {
        riskLevel = 'medium';
      }
    });
    const summary = report.findings.length > 0 ?
      `本地规则检测发现 ${report.findings.length} 项风险，请修复后再提交。` :
      '本地规则检测未发现明显风险，仍建议在提交前进行人工复核。';
    await HistoryStore.add(this.abilityContext(), {
      module: 'code',
      moduleLabel: '代码卫士',
      riskLevel: riskLevel,
      score: report.score,
      summary: summary
    });
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
        await GuardianApi.analyzeCodeArchive(this.archiveUri, this.archiveName);
      this.score = report.score;
      this.findings = report.vulnerabilities.map((item: CodeVulnerability): Finding => {
        const location = item.filePath ?
          `${item.filePath}${item.line ? `:${item.line}` : ''}` : '项目级风险';
        return {
          title: item.title,
          evidence: `${location} · ${item.reason}`,
          suggestion: item.suggestion,
          riskLevel: item.riskLevel
        };
      });
      this.archiveStatus =
        `已扫描 ${report.scannedFiles} 个文件，跳过 ${report.skippedFiles} 个；` +
        `${report.shouldSubmit ? '可以进入人工复核' : '暂不建议直接提交'}`;
      await HistoryStore.add(this.abilityContext(), {
        module: 'code',
        moduleLabel: '代码卫士',
        riskLevel: report.riskLevel,
        score: report.score,
        summary: report.summary
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
            title: '01 输入代码片段',
            copy: '本地规则检查硬编码凭据、SQL 拼接、命令执行、敏感日志和明文地址。'
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

            Button('开始本地代码检测')
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#7C3AED')
              .borderRadius(13)
              .margin({ top: 12 })
              .onClick(() => {
                this.scan();
              })
          }

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
