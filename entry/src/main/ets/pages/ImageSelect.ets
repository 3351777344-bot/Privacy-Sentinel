import router from '@ohos.router';
import { AppHeader } from '../components/AppHeader';
import { MockPhoto } from '../components/MockPhoto';

@Entry
@Component
struct ImageSelect {
  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '选择图片', subtitle: '当前为示例图片，后续可接入相册选择' })

        Column() {
          MockPhoto()

          Text('示例图片：订单页面截图')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .margin({ top: 20 })

          Text('模拟用户在分享前选择一张包含订单、地址、手机号等信息的截图。')
            .fontSize(14)
            .fontColor('#6B7280')
            .lineHeight(21)
            .margin({ top: 8 })

          Button('开始检测')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(52)
            .backgroundColor('#2563EB')
            .borderRadius(16)
            .margin({ top: 24 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/DetectResult' });
            })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(22)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 32 })
    }
    .backgroundColor('#F6F8FB')
  }
}

