import router from '@ohos.router';
import { AppHeader } from '../components/AppHeader';
import { MockPhoto } from '../components/MockPhoto';
import { RiskBadge } from '../components/RiskBadge';
import { mockDetectResult } from '../data/MockData';
import { PrivacyItem } from '../models/PrivacyModels';

@Entry
@Component
struct DetectResultPage {
  private result = mockDetectResult;

  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '检测结果', subtitle: this.result.scene })

        MockPhoto({ showMarks: true, items: this.result.privacyItems })
          .margin({ top: 4 })

        Column() {
          Row() {
            Column() {
              Text('综合风险')
                .fontSize(13)
                .fontColor('#6B7280')
              Text(`${this.result.score} 分`)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            RiskBadge({ level: this.result.riskLevel, size: 'large' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.result.summary)
            .fontSize(14)
            .fontColor('#4B5563')
            .lineHeight(22)
            .margin({ top: 14 })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(20)
        .margin({ top: 16 })

        Column() {
          Text('检测项')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .margin({ bottom: 12 })

          ForEach(this.result.privacyItems, (item: PrivacyItem) => {
            Row() {
              Column() {
                Text(item.label)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111827')
                Text(item.valuePreview)
                  .fontSize(13)
                  .fontColor('#6B7280')
                  .margin({ top: 4 })
                Text(item.suggestion)
                  .fontSize(12)
                  .fontColor('#9CA3AF')
                  .margin({ top: 6 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              RiskBadge({ level: item.riskLevel })
            }
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .border({ width: { bottom: 1 }, color: '#EEF2F7' })
          }, (item: PrivacyItem) => item.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(20)
        .margin({ top: 16 })

        Button('去打码处理')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .width('100%')
          .height(52)
          .backgroundColor('#2563EB')
          .borderRadius(16)
          .margin({ top: 18 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/EditMask' });
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 32 })
    }
    .backgroundColor('#F6F8FB')
  }
}

