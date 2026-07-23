import { common } from '@kit.AbilityKit';
import { AppHeader } from '../components/AppHeader';
import { ModuleCard } from '../components/ModuleCard';
import { MODULES } from '../data/ModuleData';
import { LocalHistoryRecord, ModuleDefinition, RiskLevel } from '../models/SecurityModels';
import { HistoryStore } from '../services/HistoryStore';

@Entry
@Component
struct Index {
  @State historyRecords: LocalHistoryRecord[] = [];

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.loadHistory();
  }

  onPageShow(): void {
    this.loadHistory();
  }

  private async loadHistory(): Promise<void> {
    this.historyRecords =
      await HistoryStore.list(this.abilityContext());
  }

  private averageScore(): number {
    if (this.historyRecords.length === 0) {
      return 100;
    }
    const total = this.historyRecords.reduce(
      (sum: number, record: LocalHistoryRecord): number => sum + record.score,
      0
    );
    return Math.round(total / this.historyRecords.length);
  }

  private reviewCount(): number {
    return this.historyRecords.filter(
      (record: LocalHistoryRecord): boolean => record.riskLevel !== 'low'
    ).length;
  }

  private riskLabel(level: RiskLevel): string {
    if (level === 'high') {
      return '高风险';
    }
    if (level === 'medium') {
      return '需复核';
    }
    return '低风险';
  }

  private riskColor(level: RiskLevel): string {
    if (level === 'high') {
      return '#DC2626';
    }
    if (level === 'medium') {
      return '#D97706';
    }
    return '#15803D';
  }

  build() {
    Column() {
      AppHeader({
        title: 'GuardianHub',
        subtitle: '高校操作前安全中心',
        showBack: false
      })

      Scroll() {
        Column() {
          Column() {
            Text('风险检查，前置一步')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .width('100%')
            Text('分享、提交、点击、上传之前，用统一报告做一次可解释的安全判断。')
              .fontSize(13)
              .fontColor('#DCE7FF')
              .lineHeight(21)
              .margin({ top: 9 })
              .width('100%')

            Row() {
              Text('本地优先')
                .fontSize(11)
                .fontColor('#FFFFFF')
              Text('联网可选')
                .fontSize(11)
                .fontColor('#FFFFFF')
              Text('四模块统一')
                .fontSize(11)
                .fontColor('#FFFFFF')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 18 })
          }
          .alignItems(HorizontalAlign.Start)
          .padding(20)
          .backgroundColor('#1D4ED8')
          .borderRadius(22)
          .width('100%')

          Row() {
            Text('四个安全入口')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172033')
            Blank()
            Text('选择场景开始')
              .fontSize(12)
              .fontColor('#64748B')
          }
          .width('100%')
          .margin({ top: 22, bottom: 12 })

          Grid() {
            ForEach(MODULES, (item: ModuleDefinition) => {
              GridItem() {
                ModuleCard({ item: item })
              }
            }, (item: ModuleDefinition) => item.id)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          Column() {
            Row() {
              Text('今日安全概览')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172033')
              Blank()
              Text('本机数据')
                .fontSize(11)
                .fontColor('#15803D')
            }
            .width('100%')

            Row() {
              Column() {
                Text(`${this.historyRecords.length}`)
                  .fontSize(26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#2563EB')
                Text('本机检测')
                  .fontSize(11)
                  .fontColor('#64748B')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Column() {
                Text(`${this.averageScore()}`)
                  .fontSize(26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#0F9F8F')
                Text('平均安全分')
                  .fontSize(11)
                  .fontColor('#64748B')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Column() {
                Text(`${this.reviewCount()}`)
                  .fontSize(26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#7C3AED')
                Text('待人工复核')
                  .fontSize(11)
                  .fontColor('#64748B')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 18 })
          }
          .alignItems(HorizontalAlign.Start)
          .padding(17)
          .backgroundColor('#FFFFFF')
          .borderRadius(18)
          .border({ width: 1, color: '#E2E8F0' })
          .margin({ top: 14, bottom: 30 })
          .width('100%')

          if (this.historyRecords.length > 0) {
            Column() {
              Row() {
                Text('最近检测')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#172033')
                Blank()
                Text('ArkData 本地保存')
                  .fontSize(11)
                  .fontColor('#15803D')
              }
              .width('100%')
              .margin({ bottom: 10 })

              ForEach(this.historyRecords.slice(0, 3), (record: LocalHistoryRecord) => {
                Column() {
                  Row() {
                    Text(record.moduleLabel)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#172033')
                    Blank()
                    Text(`${this.riskLabel(record.riskLevel)} · ${record.score} 分`)
                      .fontSize(11)
                      .fontColor(this.riskColor(record.riskLevel))
                  }
                  .width('100%')

                  Text(record.summary)
                    .fontSize(11)
                    .fontColor('#64748B')
                    .lineHeight(18)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 6 })
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .padding(12)
                .backgroundColor('#F8FAFC')
                .borderRadius(12)
                .margin({ bottom: 8 })
                .width('100%')
              }, (record: LocalHistoryRecord) => record.id)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(17)
            .backgroundColor('#FFFFFF')
            .borderRadius(18)
            .border({ width: 1, color: '#E2E8F0' })
            .margin({ bottom: 30 })
            .width('100%')
          }
        }
        .padding({ left: 16, right: 16 })
        .width('100%')
      }
      .layoutWeight(1)
    }
    .backgroundColor('#F4F7FB')
    .width('100%')
    .height('100%')
  }
}
