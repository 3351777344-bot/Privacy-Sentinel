@Component
export struct SectionCard {
  @Prop title: string;
  @Prop copy: string = '';
  @BuilderParam content: () => void;

  build() {
    Column() {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172033')
        .width('100%')
      if (this.copy.length > 0) {
        Text(this.copy)
          .fontSize(12)
          .fontColor('#64748B')
          .lineHeight(19)
          .margin({ top: 4, bottom: 13 })
          .width('100%')
      }
      this.content()
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .border({ width: 1, color: '#E2E8F0' })
    .width('100%')
  }
}
