import { ModuleDefinition } from '../models/SecurityModels';

@Component
export struct ModuleCard {
  @Prop item: ModuleDefinition;

  build() {
    Column() {
      Row() {
        Text(this.item.icon)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.item.accent)
          .width(42)
          .height(42)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.item.tint)
          .borderRadius(13)

        Blank()

        Text(this.item.moment)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.item.accent)
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(this.item.tint)
          .borderRadius(12)
      }
      .width('100%')

      Text(this.item.eyebrow)
        .fontSize(11)
        .fontColor('#64748B')
        .margin({ top: 16 })
        .width('100%')

      Text(this.item.title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172033')
        .margin({ top: 3 })
        .width('100%')

      Text(this.item.description)
        .fontSize(12)
        .fontColor('#64748B')
        .lineHeight(19)
        .maxLines(3)
        .margin({ top: 8 })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .height(190)
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .border({ width: 1, color: '#E2E8F0' })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: this.item.route });
    })
  }
}
