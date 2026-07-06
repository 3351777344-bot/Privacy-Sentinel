import router from '@ohos.router';
import { AppHeader } from '../components/AppHeader';
import { MockPhoto } from '../components/MockPhoto';
import { maskModes, mockDetectResult } from '../data/MockData';
import { MaskMode } from '../models/PrivacyModels';

@Entry
@Component
struct EditMask {
  @State selectedMode: string = 'black';

  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '打码编辑', subtitle: '选择处理方式并应用到高风险信息' })

        MockPhoto({ showMarks: true, items: mockDetectResult.privacyItems })
          .margin({ top: 4 })

        Column() {
          Text('打码方式')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .margin({ bottom: 12 })

          ForEach(maskModes, (mode: MaskMode) => {
            Row() {
              Column() {
                Text(mode.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111827')
                Text(mode.description)
                  .fontSize(13)
                  .fontColor('#6B7280')
                  .lineHeight(19)
                  .margin({ top: 5 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Radio({ value: mode.id, group: 'maskMode' })
                .checked(this.selectedMode === mode.id)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedMode = mode.id;
                  }
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.selectedMode === mode.id ? '#EFF6FF' : '#F9FAFB')
            .border({
              width: 1,
              color: this.selectedMode === mode.id ? '#2563EB' : '#EEF2F7'
            })
            .borderRadius(16)
            .margin({ top: 10 })
            .onClick(() => {
              this.selectedMode = mode.id;
            })
          }, (mode: MaskMode) => mode.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(20)
        .margin({ top: 16 })

        Button('一键处理高风险信息')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .width('100%')
          .height(52)
          .backgroundColor('#2563EB')
          .borderRadius(16)
          .margin({ top: 18 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/SafePreview' });
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 32 })
    }
    .backgroundColor('#F6F8FB')
  }
}

