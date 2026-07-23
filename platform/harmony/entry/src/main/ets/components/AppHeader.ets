@Component
export struct AppHeader {
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop showBack: boolean = true;

  build() {
    Row() {
      if (this.showBack) {
        Button('‹')
          .width(38)
          .height(38)
          .fontSize(28)
          .fontColor('#172033')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
      }

      Column() {
        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor('#64748B')
            .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.showBack ? 10 : 0 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 18, right: 18, top: 16, bottom: 12 })
  }
}
