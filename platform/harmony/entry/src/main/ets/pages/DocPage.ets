import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppHeader } from '../components/AppHeader';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import { DocCheckItem, DocCheckResponse, Finding } from '../models/SecurityModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';

@Entry
@Component
struct DocPage {
  @State requirementText: string =
    '提交课程论文 PDF、封面和签字承诺书；文件名使用学号_姓名_课程名称。';
  @State selectedUris: string[] = [];
  @State selectedNames: string[] = [];
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State statusMessage: string = '尚未选择材料';
  @State scanning: boolean = false;

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async pickDocuments(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = [
        '参赛与课程材料|.pdf,.docx,.txt,.md,.png,.jpg,.jpeg,.zip,.ppt,.pptx'
      ];
      options.maxSelectNumber = 8;
      const result = await new picker.DocumentViewPicker().select(options);
      if (result.length === 0) {
        return;
      }
      this.selectedUris = result;
      this.selectedNames = result.map((uri: string): string => this.fileNameFromUri(uri));
      this.statusMessage = `已选择 ${result.length} 个文件，等待检查`;
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '未能打开系统文件选择器');
    }
  }

  private async scan(): Promise<void> {
    if (this.requirementText.trim().length === 0) {
      this.statusMessage = '请先填写提交要求';
      return;
    }
    if (this.selectedUris.length === 0) {
      this.statusMessage = '请至少选择一个材料文件';
      return;
    }
    this.scanning = true;
    this.statusMessage = '正在检查材料完整性、格式与隐私风险…';
    try {
      const report: DocCheckResponse = await GuardianApi.checkDocuments(
        this.requirementText,
        this.selectedUris,
        this.selectedNames
      );
      const suggestion = report.suggestions.length > 0 ?
        report.suggestions[0] : '提交前打开每个文件进行最终复核。';
      this.findings = report.checks.map((item: DocCheckItem): Finding => {
        return {
          title: item.label,
          evidence: item.evidence,
          suggestion: suggestion,
          riskLevel: item.riskLevel
        };
      });
      this.score = report.score;
      this.statusMessage = report.summary;
      await HistoryStore.add(this.abilityContext(), {
        module: 'doc',
        moduleLabel: '提交护盾',
        riskLevel: report.riskLevel,
        score: report.score,
        summary: report.summary
      });
    } catch (error) {
      this.statusMessage = this.errorMessage(error, '材料检查失败');
    } finally {
      this.scanning = false;
    }
  }

  private fileNameFromUri(uri: string): string {
    const rawName = uri.substring(uri.lastIndexOf('/') + 1);
    return decodeURIComponent(rawName) || '未命名材料';
  }

  private errorMessage(error: Object, fallback: string): string {
    const typedError = error as Error;
    return typedError.message ? `${fallback}：${typedError.message}` : fallback;
  }

  build() {
    Column() {
      AppHeader({
        title: 'Doc Shield',
        subtitle: '材料上传前完整性检查'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '01 提交要求',
            copy: '输入要求和准备提交的文件名，先做格式、清单和隐私自查。'
          }) {
            TextArea({
              text: this.requirementText,
              placeholder: '粘贴完整提交要求'
            })
              .height(130)
              .fontSize(13)
              .backgroundColor('#F8FAFC')
              .borderRadius(12)
              .padding(11)
              .onChange((value: string) => {
                this.requirementText = value;
              })

            Text('待提交材料')
              .fontSize(12)
              .fontColor('#475569')
              .margin({ top: 12, bottom: 6 })

            Button(this.selectedNames.length > 0 ? '重新选择材料' : '从系统选择材料')
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontColor('#C2410C')
              .backgroundColor('#FFEDD5')
              .borderRadius(12)
              .onClick(() => {
                this.pickDocuments();
              })

            if (this.selectedNames.length > 0) {
              Column() {
                ForEach(this.selectedNames, (fileName: string) => {
                  Text(`• ${fileName}`)
                    .fontSize(12)
                    .fontColor('#475569')
                    .lineHeight(19)
                    .width('100%')
                }, (fileName: string) => fileName)
              }
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .backgroundColor('#FFF7ED')
              .borderRadius(11)
              .margin({ top: 9 })
              .width('100%')
            }

            Button(this.scanning ? '检查中…' : '开始提交前检查')
              .enabled(!this.scanning)
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.scanning ? '#94A3B8' : '#EA7C24')
              .borderRadius(13)
              .margin({ top: 12 })
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
            emptyCopy: '检查材料缺失、格式、命名和文件名隐私风险。'
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
