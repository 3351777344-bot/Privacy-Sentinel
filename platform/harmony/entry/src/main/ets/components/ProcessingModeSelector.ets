export type ProcessingMode = 'local' | 'online';

@Component
export struct ProcessingModeSelector {
  @Prop mode: ProcessingMode = 'local';
  @Prop onlineHint: string = '调用已配置的模型服务';
  onModeChange: (mode: ProcessingMode) => void = (_mode: ProcessingMode) => {
  };

  build() {
    Column() {
      Text('处理模式')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#475569')
        .width('100%')

      Row() {
        Button() {
          Column() {
            Text('本地优先')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.mode === 'local' ? '#FFFFFF' : '#334155')
            Text('本机规则 / OCR')
              .fontSize(10)
              .fontColor(this.mode === 'local' ? '#DBEAFE' : '#94A3B8')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .layoutWeight(1)
        .height(54)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.mode === 'local' ? '#2563EB' : '#F1F5F9')
        .borderRadius(12)
        .margin({ right: 8 })
        .onClick(() => {
          this.onModeChange('local');
        })

        Button() {
          Column() {
            Text('联网增强')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.mode === 'online' ? '#FFFFFF' : '#334155')
            Text(this.onlineHint)
              .fontSize(10)
              .fontColor(this.mode === 'online' ? '#DBEAFE' : '#94A3B8')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .layoutWeight(1)
        .height(54)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.mode === 'online' ? '#0F766E' : '#F1F5F9')
        .borderRadius(12)
        .onClick(() => {
          this.onModeChange('online');
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
