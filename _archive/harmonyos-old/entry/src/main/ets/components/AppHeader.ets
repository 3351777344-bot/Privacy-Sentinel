import router from '@ohos.router';

@Component
export struct AppHeader {
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop showBack: boolean = true;

  build() {
    Row() {
      if (this.showBack) {
        Text('‹')
          .fontSize(32)
          .fontColor('#111827')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })
      }

      Column() {
        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(13)
            .fontColor('#6B7280')
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.showBack ? 8 : 0 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 20, right: 20, top: 14, bottom: 12 })
  }
}

