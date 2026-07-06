import router from '@ohos.router';
import { AppHeader } from '../components/AppHeader';
import { MockPhoto } from '../components/MockPhoto';
import { RiskBadge } from '../components/RiskBadge';

@Entry
@Component
struct SafePreview {
  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '安全预览', subtitle: '确认处理效果后再分享' })

        MockPhoto({ processed: true })
          .margin({ top: 4 })

        Column() {
          Row() {
            Column() {
              Text('安全等级')
                .fontSize(13)
                .fontColor('#6B7280')
              Text('可安全分享')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            RiskBadge({ level: 'safe', size: 'large' })
          }
          .width('100%')

          Text('高风险字段已完成遮挡。建议分享前再次确认图片边缘、二维码、头像、昵称等上下文信息。')
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

        Row() {
          Button('返回首页')
            .fontSize(16)
            .fontColor('#111827')
            .layoutWeight(1)
            .height(50)
            .backgroundColor('#F3F4F6')
            .borderRadius(16)
            .onClick(() => {
              router.clear();
              router.pushUrl({ url: 'pages/Index' });
            })

          Blank().width(12)

          Button('模拟分享')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(50)
            .backgroundColor('#16A34A')
            .borderRadius(16)
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 32 })
    }
    .backgroundColor('#F6F8FB')
  }
}

