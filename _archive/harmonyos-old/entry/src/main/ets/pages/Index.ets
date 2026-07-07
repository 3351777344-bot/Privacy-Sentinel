import router from '@ohos.router';
import { AppHeader } from '../components/AppHeader';

@Entry
@Component
struct Index {
  build() {
    Scroll() {
      Column() {
        AppHeader({
          title: 'Privacy Sentinel',
          subtitle: '隐私哨兵：AI 安全分享助手',
          showBack: false
        })

        Column() {
          Text('分享之前，先让 AI 帮你检查一遍')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .lineHeight(40)

          Text('面向截图、照片、聊天记录、快递单、订单页面等分享场景，自动发现敏感信息并生成安全分享预览。')
            .fontSize(15)
            .fontColor('#6B7280')
            .lineHeight(23)
            .margin({ top: 14 })

          Button('开始检测')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(52)
            .backgroundColor('#2563EB')
            .borderRadius(16)
            .margin({ top: 28 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/ImageSelect' });
            })

          Button('查看历史记录')
            .fontSize(16)
            .fontColor('#111827')
            .width('100%')
            .height(50)
            .backgroundColor('#F3F4F6')
            .borderRadius(16)
            .margin({ top: 12 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/History' });
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(24)
        .backgroundColor(Color.White)
        .borderRadius(24)
        .shadow({ radius: 20, color: '#18223514', offsetX: 0, offsetY: 10 })
        .margin({ top: 18 })

        Row() {
          this.featureCard('风险分级', '高 / 中 / 低风险清晰提示')
          Blank().width(12)
          this.featureCard('一键打码', '快速处理敏感区域')
        }
        .width('100%')
        .margin({ top: 16 })

        Row() {
          this.featureCard('安全预览', '分享前确认最终效果')
          Blank().width(12)
          this.featureCard('历史追踪', '保留最近检测记录')
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 32 })
    }
    .backgroundColor('#F6F8FB')
  }

  @Builder
  private featureCard(title: string, desc: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
      Text(desc)
        .fontSize(12)
        .fontColor('#6B7280')
        .lineHeight(18)
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height(104)
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(18)
  }
}

