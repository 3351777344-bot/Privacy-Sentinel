import { AppHeader } from '../components/AppHeader';
import { SectionCard } from '../components/SectionCard';

/** A numbered step in the quick-start list. */
interface GuideStepItem {
  index: string;
  title: string;
  detail: string;
}

/** A module entry in the reference list. */
interface GuideModuleItem {
  name: string;
  accent: string;
  when: string;
  detail: string;
}

const QUICK_START: GuideStepItem[] = [
  {
    index: '1',
    title: '按动作选入口',
    detail: '要分享图片就进隐私哨兵，要提交代码就进代码卫士。入口和动作对应，选错只是检查重点不同。'
  },
  {
    index: '2',
    title: '选择处理模式',
    detail: '默认仅本地，什么都不外发。需要更细的结论时切到联网分析，发送前会弹窗说明要发什么。'
  },
  {
    index: '3',
    title: '看报告再决定',
    detail: '报告给出评分、风险等级、判断依据和建议。它是决策参考，不是放行许可。'
  }
];

const MODULE_LIST: GuideModuleItem[] = [
  {
    name: '隐私哨兵',
    accent: '#2563EB',
    when: '分享前',
    detail: '识别图片中的文字与二维码。敏感或无法确认安全的二维码会阻止原图上传，可用端侧黑块直接遮挡码区。'
  },
  {
    name: '代码卫士',
    accent: '#7C3AED',
    when: '提交前',
    detail: '检查代码片段或整个项目 ZIP：硬编码凭据、危险调用、路径穿越与可疑文件结构。ZIP 只在内存中只读扫描，不执行其中代码。'
  },
  {
    name: '链接卫士',
    accent: '#0F9F8F',
    when: '点击前',
    detail: '静态判断协议、域名、短链、Punycode 与敏感参数。不访问你输入的目标网址。'
  },
  {
    name: '提交护盾',
    accent: '#EA7C24',
    when: '上传前',
    detail: '把提交要求与材料比对：完整性、命名、格式、文件结构与隐私风险，指出缺了什么、哪里不合规。'
  }
];

@Entry
@Component
struct GuidePage {
  @Builder
  quickStartRow(item: GuideStepItem) {
    Row() {
      Text(item.index)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor('#2563EB')
      Column() {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172033')
          .width('100%')
        Text(item.detail)
          .fontSize(12)
          .fontColor('#64748B')
          .lineHeight(19)
          .width('100%')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 12 })
  }

  @Builder
  moduleRow(item: GuideModuleItem) {
    Column() {
      Row() {
        Text(item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
        Text(item.when)
          .fontSize(11)
          .fontColor(item.accent)
          .backgroundColor('#F1F5F9')
          .borderRadius(7)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .margin({ left: 8 })
      }
      .width('100%')

      Text(item.detail)
        .fontSize(12)
        .fontColor('#64748B')
        .lineHeight(19)
        .width('100%')
        .margin({ top: 5 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: '#F1F5F9' })
  }

  @Builder
  boundaryRow(mark: string, text: string, accent: string) {
    Row() {
      Text(mark)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
        .width(16)
      Text(text)
        .fontSize(12)
        .fontColor('#475569')
        .lineHeight(20)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 9 })
  }

  build() {
    Column() {
      AppHeader({
        title: '使用说明',
        subtitle: '怎么用，数据去哪'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '一分钟上手',
            copy: '三步就能出结论，不需要注册，也不联网也能用。'
          }) {
            ForEach(QUICK_START, (item: GuideStepItem) => {
              this.quickStartRow(item);
            }, (item: GuideStepItem) => item.index)
          }

          Column() {
            SectionCard({
              title: '四个模块',
              copy: '它们共用同一套报告格式，所以换模块不用重新理解结论。'
            }) {
              ForEach(MODULE_LIST, (item: GuideModuleItem) => {
                this.moduleRow(item);
              }, (item: GuideModuleItem) => item.name)
            }
          }
          .width('100%')
          .margin({ top: 12 })

          Column() {
            SectionCard({
              title: '两种处理模式',
              copy: '端侧优先，联网必须逐次授权。'
            }) {
              Text('仅本地')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#172033')
                .width('100%')
              Text('检查全部在设备上完成，不发起任何网络请求。服务层会硬阻断发送，不存在“以为没发其实发了”的情况。')
                .fontSize(12)
                .fontColor('#64748B')
                .lineHeight(19)
                .width('100%')
                .margin({ top: 4 })

              Text('联网分析')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#172033')
                .width('100%')
                .margin({ top: 14 })
              Text('在本地规则的基础上补充远程分析。点击检测后会弹窗说明要发送的内容，同意才发送；不同意则保留本地结论。同一次操作只授权一次。')
                .fontSize(12)
                .fontColor('#64748B')
                .lineHeight(19)
                .width('100%')
                .margin({ top: 4 })
            }
          }
          .width('100%')
          .margin({ top: 12 })

          Column() {
            SectionCard({
              title: '数据边界',
              copy: '默认留在设备上，需要外发时必须由你当场同意。'
            }) {
              this.boundaryRow('✓', '图片、链接、代码与文件默认只做端侧或私有后端的本地检查，不上传原文件。', '#15803D')
              this.boundaryRow('✓', '敏感或无法确认安全的二维码，原图会被阻止上传。', '#15803D')
              this.boundaryRow('✓', '网络失败不会自动重试上传，避免在你看不到的时候重复外发。', '#15803D')
              this.boundaryRow('!', '选择联网分析后，相关内容会发送至服务端；图片视觉分析可能由第三方 AI 服务处理。弹窗里会写明范围。', '#B45309')
              this.boundaryRow('!', '本地结论只覆盖已检查的范围，未命中规则不代表安全。', '#B45309')
            }
          }
          .width('100%')
          .margin({ top: 12 })

          Column() {
            SectionCard({
              title: '结果怎么看',
              copy: '每条结论都能追到依据。'
            }) {
              Text('评分 0–100，分数越高越安全；风险等级分为高、中、低。')
                .fontSize(12)
                .fontColor('#475569')
                .lineHeight(20)
                .width('100%')
              Text('报告里的每一条都带位置与原因，并给出建议动作。报告底部会注明结论来源：端侧规则、是否已授权发送、是否收到远程结果。')
                .fontSize(12)
                .fontColor('#475569')
                .lineHeight(20)
                .width('100%')
                .margin({ top: 9 })
              Text('检查记录只保存在本机，可在首页「本机历史概览」回看。')
                .fontSize(12)
                .fontColor('#475569')
                .lineHeight(20)
                .width('100%')
                .margin({ top: 9 })
            }
          }
          .width('100%')
          .margin({ top: 12 })

          Column() {
            SectionCard({
              title: '能力边界',
              copy: '把它当成一次快速体检，而不是安全保证。'
            }) {
              Text('GuardianHub 是分享目标，不是系统级拦截器：它可以拦住经由系统分享面板发起的内容，不会拦截其他应用内部的传输。端侧能力同样有范围——图片离线只解析二维码，不含完整文字识别；代码检查是规则与静态分析，不是完整 SAST。')
                .fontSize(12)
                .fontColor('#475569')
                .lineHeight(20)
                .width('100%')
            }
          }
          .width('100%')
          .margin({ top: 12, bottom: 28 })
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
