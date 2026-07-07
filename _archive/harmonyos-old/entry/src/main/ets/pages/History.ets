import { AppHeader } from '../components/AppHeader';
import { RiskBadge } from '../components/RiskBadge';
import { historyRecords } from '../data/MockData';
import { HistoryRecord } from '../models/PrivacyModels';

@Entry
@Component
struct History {
  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '历史记录', subtitle: '最近检测过的分享图片' })

        ForEach(historyRecords, (record: HistoryRecord) => {
          Row() {
            Column() {
              Text(record.title)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111827')
              Text(`${record.scene} · ${record.itemCount} 个敏感项`)
                .fontSize(13)
                .fontColor('#6B7280')
                .margin({ top: 6 })
              Text(record.createdAt)
                .fontSize(12)
                .fontColor('#9CA3AF')
                .margin({ top: 8 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            RiskBadge({ level: record.riskLevel })
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.White)
          .borderRadius(18)
          .margin({ top: 12 })
        }, (record: HistoryRecord) => record.id)
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 32 })
    }
    .backgroundColor('#F6F8FB')
  }
}

