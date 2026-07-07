import { PrivacyItem } from '../models/PrivacyModels';

@Component
export struct MockPhoto {
  @Prop showMarks: boolean = false;
  @Prop processed: boolean = false;
  @Prop items: PrivacyItem[] = [];

  private markColor(level: string): string {
    if (level === 'high') {
      return '#E5484D';
    }
    if (level === 'medium') {
      return '#F59E0B';
    }
    return '#2563EB';
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('订单详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')

          Blank()

          Text('待分享')
            .fontSize(12)
            .fontColor('#2563EB')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#DBEAFE')
            .borderRadius(10)
        }
        .width('100%')

        Divider().strokeWidth(1).color('#E5E7EB').margin({ top: 16, bottom: 14 })

        this.infoLine('收件人', this.processed ? '李*' : '李明', this.processed, 0)
        this.infoLine('手机号', this.processed ? '已隐藏' : '138 8263 2796', this.processed, 1)
        this.infoLine('地址', this.processed ? '上海市浦东新区 ********' : '上海市浦东新区张江镇科苑路88号', this.processed, 2)

        Column() {
          Text('商品信息')
            .fontSize(13)
            .fontColor('#6B7280')
          Text('HarmonyOS 创新开发套件 x 1')
            .fontSize(15)
            .fontColor('#111827')
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .backgroundColor('#F9FAFB')
        .borderRadius(12)
        .margin({ top: 18 })

        this.infoLine('订单编号', this.processed ? 'OD2026********1188' : 'OD2026070609401188', this.processed, 3)
      }
      .width('100%')
      .height('100%')
      .padding(22)
      .backgroundColor(Color.White)

      if (this.showMarks) {
        ForEach(this.items, (item: PrivacyItem) => {
          Blank()
            .width(item.rect.width)
            .height(item.rect.height)
            .backgroundColor('#00000000')
            .border({ width: 2, color: this.markColor(item.riskLevel) })
            .borderRadius(8)
            .position({ x: item.rect.x, y: item.rect.y })

          Text(item.label)
            .fontSize(11)
            .fontColor(Color.White)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.markColor(item.riskLevel))
            .borderRadius(8)
            .position({ x: item.rect.x, y: item.rect.y - 22 })
        }, (item: PrivacyItem) => item.id)
      }

      if (this.processed) {
        Blank()
          .width(210)
          .height(34)
          .backgroundColor('#111827')
          .borderRadius(7)
          .position({ x: 40, y: 138 })
        Blank()
          .width(250)
          .height(58)
          .backgroundColor('#111827')
          .borderRadius(7)
          .position({ x: 40, y: 186 })
        Blank()
          .width(236)
          .height(32)
          .backgroundColor('#111827')
          .borderRadius(7)
          .position({ x: 40, y: 300 })
      }
    }
    .width('100%')
    .height(380)
    .clip(true)
    .borderRadius(18)
    .backgroundColor(Color.White)
    .shadow({
      radius: 18,
      color: '#18223518',
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private infoLine(label: string, value: string, processed: boolean, index: number) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#6B7280')
        .width(70)
      Text(value)
        .fontSize(15)
        .fontColor(processed && (index === 1 || index === 2 || index === 3) ? '#9CA3AF' : '#111827')
        .maxLines(index === 2 ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: index === 0 ? 0 : 14 })
  }
}
