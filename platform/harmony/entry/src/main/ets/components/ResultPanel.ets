import { Finding, RiskLevel } from '../models/SecurityModels';

@Component
struct RiskBadge {
  @Prop level: RiskLevel;

  private label(): string {
    if (this.level === 'high') {
      return '高风险';
    }
    if (this.level === 'medium') {
      return '中风险';
    }
    return '低风险';
  }

  private color(): string {
    if (this.level === 'high') {
      return '#DC2626';
    }
    if (this.level === 'medium') {
      return '#D97706';
    }
    return '#15803D';
  }

  build() {
    Text(this.label())
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.color())
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor('#F8FAFC')
      .borderRadius(12)
  }
}

@Component
export struct ResultPanel {
  @Prop findings: Finding[] = [];
  @Prop score: number = 100;
  @Prop emptyCopy: string = '完成检测后，这里会展示风险证据和处理建议。';

  private overallRisk(): RiskLevel {
    let risk: RiskLevel = 'low';
    this.findings.forEach((item: Finding) => {
      if (item.riskLevel === 'high') {
        risk = 'high';
      } else if (item.riskLevel === 'medium' && risk !== 'high') {
        risk = 'medium';
      }
    });
    return risk;
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('安全体检报告')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172033')
          Text(this.findings.length > 0 ? `${this.findings.length} 项需要关注` : '等待检测')
            .fontSize(12)
            .fontColor('#64748B')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(`${this.score}`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.score < 60 ? '#DC2626' : '#2563EB')
        Text('/100')
          .fontSize(11)
          .fontColor('#94A3B8')
          .alignSelf(ItemAlign.End)
          .margin({ bottom: 5, left: 2 })
      }
      .width('100%')

      if (this.findings.length === 0) {
        Text(this.emptyCopy)
          .fontSize(13)
          .fontColor('#64748B')
          .lineHeight(21)
          .padding(14)
          .backgroundColor('#F8FAFC')
          .borderRadius(12)
          .margin({ top: 14 })
          .width('100%')
      } else {
        Row() {
          RiskBadge({ level: this.overallRisk() })
          Text(this.score < 60 ? '不建议继续当前操作' : '建议处理后继续')
            .fontSize(12)
            .fontColor('#475569')
            .margin({ left: 9 })
        }
        .width('100%')
        .margin({ top: 14 })

        ForEach(this.findings, (item: Finding) => {
          Column() {
            Row() {
              Text(item.title)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172033')
                .layoutWeight(1)
              RiskBadge({ level: item.riskLevel })
            }
            .width('100%')

            Text(item.evidence)
              .fontSize(12)
              .fontColor('#64748B')
              .lineHeight(19)
              .margin({ top: 8 })
              .width('100%')
            Text(`建议：${item.suggestion}`)
              .fontSize(12)
              .fontColor('#1E40AF')
              .lineHeight(19)
              .margin({ top: 7 })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(13)
          .backgroundColor('#F8FAFC')
          .borderRadius(12)
          .margin({ top: 10 })
          .width('100%')
        }, (item: Finding) => `${item.title}-${item.evidence}`)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .border({ width: 1, color: '#E2E8F0' })
    .width('100%')
  }
}

