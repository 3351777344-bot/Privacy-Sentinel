import { common } from '@kit.AbilityKit';
import { GuideStore } from '../services/GuideStore';

/** One screen of the first-run guide. */
interface GuideStep {
  tag: string;
  title: string;
  body: string;
  bullets: string[];
}

const STEP_COUNT: number = 3;

const STEPS: GuideStep[] = [
  {
    tag: '第 1 步 · 这是什么',
    title: '分享之前，先看一眼',
    body: 'GuardianHub 出现在系统分享菜单里。收到图片、链接、代码或文件后，它先在设备上做一次检查，再由你决定要不要继续分享。',
    bullets: [
      '它是分享目标，不是系统级拦截器',
      '未命中规则不代表安全，结论只覆盖已检查的范围',
      '每次检查都会留下一条本机历史记录'
    ]
  },
  {
    tag: '第 2 步 · 怎么选',
    title: '四个入口，各管一件事',
    body: '按你正要做的动作选入口，选错也不会出错，只是检查的重点不同。',
    bullets: [
      '隐私哨兵 —— 分享前，看图片里的敏感内容',
      '代码卫士 —— 提交前，查凭证、危险调用与项目结构',
      '链接卫士 —— 点击前，判断协议、域名与参数风险',
      '提交护盾 —— 上传前，核对材料完整性与隐私'
    ]
  },
  {
    tag: '第 3 步 · 数据去哪',
    title: '默认不出设备',
    body: '端侧能做完的都留在设备上。确实需要联网时，会在发送前弹窗说明要发什么，由你当场决定。',
    bullets: [
      '默认端侧处理，不上传原文件',
      '联网增强逐次授权，不同意就只出本地结论',
      '敏感或无法确认安全的二维码会阻止原图上传',
      '网络失败不会自动重试上传'
    ]
  }
];

@Entry
@Component
struct OnboardingPage {
  @State step: number = 0;

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    // Marked on show, not on finish: a back gesture must not make the guide
    // reappear on every launch.
    GuideStore.markOnboardingSeen(this.abilityContext());
  }

  private current(): GuideStep {
    return STEPS[this.step];
  }

  private isLast(): boolean {
    return this.step >= STEP_COUNT - 1;
  }

  private finish(): void {
    this.getUIContext().getRouter().back();
  }

  private advance(): void {
    if (this.isLast()) {
      this.finish();
      return;
    }
    this.step = this.step + 1;
  }

  @Builder
  bulletRow(text: string) {
    Row() {
      Text('•')
        .fontSize(13)
        .fontColor('#2563EB')
        .margin({ right: 7 })
      Text(text)
        .fontSize(13)
        .fontColor('#475569')
        .lineHeight(21)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 9 })
  }

  build() {
    Column() {
      Row() {
        Blank()
        Button('跳过')
          .fontSize(13)
          .fontColor('#64748B')
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.finish();
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6 })

      Column() {
        Text(this.current().tag)
          .fontSize(12)
          .fontColor('#2563EB')
          .fontWeight(FontWeight.Medium)
          .width('100%')

        Text(this.current().title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
          .width('100%')
          .margin({ top: 10 })

        Text(this.current().body)
          .fontSize(13)
          .fontColor('#64748B')
          .lineHeight(21)
          .width('100%')
          .margin({ top: 10 })

        Column() {
          ForEach(this.current().bullets, (item: string) => {
            this.bulletRow(item);
          }, (item: string) => item)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .border({ width: 1, color: '#E2E8F0' })
      .width('100%')
      .margin({ top: 8 })

      Blank()

      Row() {
        ForEach([0, 1, 2], (index: number) => {
          Row()
            .width(this.step === index ? 20 : 7)
            .height(7)
            .borderRadius(4)
            .backgroundColor(this.step === index ? '#2563EB' : '#CBD5E1')
            .margin({ right: index === 2 ? 0 : 6 })
        }, (index: number) => `${index}`)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .margin({ bottom: 16 })

      Button(this.isLast() ? '开始使用' : '下一步')
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#2563EB')
        .borderRadius(14)
        .onClick(() => {
          this.advance();
        })

      Text('随时可以从首页「使用说明」再看一遍')
        .fontSize(11)
        .fontColor('#94A3B8')
        .margin({ top: 12, bottom: 6 })
    }
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F4F7FB')
    .width('100%')
    .height('100%')
  }
}
