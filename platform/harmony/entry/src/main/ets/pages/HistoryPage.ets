import { common } from '@kit.AbilityKit';
import { AppHeader } from '../components/AppHeader';
import { Finding, LocalHistoryRecord, RiskLevel } from '../models/SecurityModels';
import { HistoryStore } from '../services/HistoryStore';

@Entry
@Component
struct HistoryPage {
  @State records: LocalHistoryRecord[] = [];
  @State moduleFilter: string = 'all';
  @State expandedId: string = '';
  @State pendingDeleteId: string = '';
  @State confirmClear: boolean = false;
  @State statusMessage: string = '';

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
    this.records = await HistoryStore.list(this.abilityContext());
  }

  private filteredRecords(): LocalHistoryRecord[] {
    if (this.moduleFilter === 'all') {
      return this.records;
    }
    return this.records.filter((record: LocalHistoryRecord): boolean => {
      return record.module === this.moduleFilter;
    });
  }

  private processedCount(): number {
    return this.records.filter((record: LocalHistoryRecord): boolean => record.processed).length;
  }

  private pendingCount(): number {
    return this.records.filter((record: LocalHistoryRecord): boolean => {
      return record.status === '待复核' || record.status === '待决策';
    }).length;
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

  private effectiveScore(record: LocalHistoryRecord): number {
    return record.processedScore === undefined ? record.score : record.processedScore;
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${this.pad(date.getMonth() + 1)}-${this.pad(date.getDate())} ` +
      `${this.pad(date.getHours())}:${this.pad(date.getMinutes())}`;
  }

  private async removeRecord(id: string): Promise<void> {
    if (this.pendingDeleteId !== id) {
      this.pendingDeleteId = id;
      this.statusMessage = '再次点击删除按钮以确认。';
      return;
    }
    const removed = await HistoryStore.remove(this.abilityContext(), id);
    this.pendingDeleteId = '';
    this.expandedId = '';
    this.statusMessage = removed ? '历史记录已删除。' : '未找到该记录。';
    await this.loadHistory();
  }

  private async clearHistory(): Promise<void> {
    if (!this.confirmClear) {
      this.confirmClear = true;
      this.statusMessage = '再次点击“确认清空”将删除全部本机历史。';
      return;
    }
    const cleared = await HistoryStore.clear(this.abilityContext());
    this.confirmClear = false;
    this.expandedId = '';
    this.statusMessage = cleared ? '本机历史已清空。' : '清空失败，请稍后重试。';
    await this.loadHistory();
  }

  @Builder
  private filterButton(label: string, value: string) {
    Button(label)
      .fontSize(12)
      .fontColor(this.moduleFilter === value ? '#FFFFFF' : '#475569')
      .backgroundColor(this.moduleFilter === value ? '#2563EB' : '#F1F5F9')
      .borderRadius(12)
      .height(36)
      .padding({ left: 12, right: 12 })
      .margin({ right: 8 })
      .onClick(() => {
        this.moduleFilter = value;
        this.pendingDeleteId = '';
      })
  }

  build() {
    Column() {
      AppHeader({
        title: '检测历史',
        subtitle: '本机报告与处置记录'
      })

      Scroll() {
        Column() {
          Row() {
            Column() {
              Text(`${this.records.length}`)
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor('#2563EB')
              Text('已存记录')
                .fontSize(11)
                .fontColor('#64748B')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Text(`${this.processedCount()}`)
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor('#15803D')
              Text('已处理')
                .fontSize(11)
                .fontColor('#64748B')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Text(`${this.pendingCount()}`)
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor('#D97706')
              Text('待处理')
                .fontSize(11)
                .fontColor('#64748B')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(18)
          .border({ width: 1, color: '#E2E8F0' })
          .width('100%')

          Scroll() {
            Row() {
              this.filterButton('全部', 'all')
              this.filterButton('隐私', 'privacy')
              this.filterButton('代码', 'code')
              this.filterButton('链接', 'link')
              this.filterButton('材料', 'doc')
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ top: 14, bottom: 12 })

          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .fontSize(12)
              .fontColor('#475569')
              .padding(10)
              .backgroundColor('#EFF6FF')
              .borderRadius(10)
              .width('100%')
              .margin({ bottom: 10 })
          }

          if (this.filteredRecords().length === 0) {
            Column() {
              Text('暂无历史检测记录')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172033')
              Text('完成任一安全检测后，完整报告会保存在这里。')
                .fontSize(12)
                .fontColor('#64748B')
                .margin({ top: 8 })
            }
            .padding(28)
            .backgroundColor('#FFFFFF')
            .borderRadius(18)
            .width('100%')
          } else {
            ForEach(this.filteredRecords(), (record: LocalHistoryRecord) => {
              Column() {
                Row() {
                  Column() {
                    Text(record.moduleLabel)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#172033')
                    Text(this.formatTime(record.createdAt))
                      .fontSize(10)
                      .fontColor('#94A3B8')
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(`${this.riskLabel(record.riskLevel)} · ${this.effectiveScore(record)} 分`)
                    .fontSize(11)
                    .fontColor(this.riskColor(record.riskLevel))
                    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                    .backgroundColor('#F8FAFC')
                    .borderRadius(10)
                }
                .width('100%')

                Text(record.summary)
                  .fontSize(12)
                  .fontColor('#475569')
                  .lineHeight(19)
                  .maxLines(this.expandedId === record.id ? 8 : 2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 10 })
                  .width('100%')

                Row() {
                  Text(record.status)
                    .fontSize(11)
                    .fontColor(record.processed ? '#15803D' : '#D97706')
                  Blank()
                  Button(this.expandedId === record.id ? '收起详情' : '查看详情')
                    .fontSize(11)
                    .fontColor('#2563EB')
                    .backgroundColor('#EFF6FF')
                    .height(32)
                    .borderRadius(10)
                    .onClick(() => {
                      this.expandedId = this.expandedId === record.id ? '' : record.id;
                      this.pendingDeleteId = '';
                    })
                }
                .width('100%')
                .margin({ top: 10 })

                if (this.expandedId === record.id) {
                  Column() {
                    if (record.sourceLabel.length > 0) {
                      Text(`检测对象：${record.sourceLabel}`)
                        .fontSize(11)
                        .fontColor('#64748B')
                        .width('100%')
                    }
                    if (record.processedScore !== undefined) {
                      Text(`评分变化：${record.score} → ${record.processedScore}`)
                        .fontSize(11)
                        .fontColor('#15803D')
                        .margin({ top: 6 })
                        .width('100%')
                    }
                    if (record.action.length > 0) {
                      Text(`最近处置：${record.action}`)
                        .fontSize(11)
                        .fontColor('#475569')
                        .margin({ top: 6 })
                        .width('100%')
                    }

                    if (record.findings.length > 0) {
                      Text('风险证据')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#172033')
                        .margin({ top: 12, bottom: 6 })
                        .width('100%')
                      ForEach(record.findings, (finding: Finding) => {
                        Column() {
                          Text(finding.title)
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(this.riskColor(finding.riskLevel))
                            .width('100%')
                          Text(finding.evidence)
                            .fontSize(11)
                            .fontColor('#64748B')
                            .lineHeight(17)
                            .margin({ top: 3 })
                            .width('100%')
                          Text(`建议：${finding.suggestion}`)
                            .fontSize(11)
                            .fontColor('#334155')
                            .lineHeight(17)
                            .margin({ top: 3 })
                            .width('100%')
                        }
                        .alignItems(HorizontalAlign.Start)
                        .padding(10)
                        .backgroundColor('#F8FAFC')
                        .borderRadius(10)
                        .margin({ bottom: 7 })
                        .width('100%')
                      }, (finding: Finding) => `${record.id}-${finding.title}-${finding.evidence}`)
                    }

                    if (record.suggestions.length > 0) {
                      Text('处置建议')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#172033')
                        .margin({ top: 10, bottom: 5 })
                        .width('100%')
                      ForEach(record.suggestions, (suggestion: string) => {
                        Text(`· ${suggestion}`)
                          .fontSize(11)
                          .fontColor('#475569')
                          .lineHeight(17)
                          .margin({ bottom: 4 })
                          .width('100%')
                      }, (suggestion: string) => `${record.id}-${suggestion}`)
                    }

                    Button(this.pendingDeleteId === record.id ? '确认删除此记录' : '删除此记录')
                      .fontSize(12)
                      .fontColor('#DC2626')
                      .backgroundColor('#FEF2F2')
                      .height(38)
                      .borderRadius(10)
                      .width('100%')
                      .margin({ top: 8 })
                      .onClick(() => {
                        this.removeRecord(record.id);
                      })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .padding({ top: 12 })
                  .border({ width: 1, color: '#E2E8F0' })
                  .margin({ top: 10 })
                  .width('100%')
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding(15)
              .backgroundColor('#FFFFFF')
              .borderRadius(16)
              .border({ width: 1, color: '#E2E8F0' })
              .margin({ bottom: 10 })
              .width('100%')
            }, (record: LocalHistoryRecord) => record.id)
          }

          if (this.records.length > 0) {
            Button(this.confirmClear ? '确认清空全部历史' : '清空全部历史')
              .fontSize(12)
              .fontColor('#DC2626')
              .backgroundColor('#FEF2F2')
              .borderRadius(12)
              .height(42)
              .width('100%')
              .margin({ top: 8, bottom: 28 })
              .onClick(() => {
                this.clearHistory();
              })
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
