import { ProcessingMode } from '../services/ScanPolicy';
export { ProcessingMode } from '../services/ScanPolicy';

@Component
export struct ProcessingModeSelector {
  @Prop mode: ProcessingMode = 'local_only';
  @Prop onlineHint: string = '联网分析会将所选内容发送至配置的服务。';
  /**
   * Module identity colour for the selected pill. Defaults to the privacy blue;
   * the code and document pages pass their own accent so a control never fights
   * the module's primary action button.
   */
  @Prop accentColor: string = '#2563EB';
  @Prop disabled: boolean = false;
  onModeChange: (mode: ProcessingMode) => void = (_mode: ProcessingMode) => {};

  private label(mode: ProcessingMode): string {
    if (mode === 'local_only') { return '仅本地'; }
    return '联网分析';
  }

  build() {
    Column() {
      Row() {
        ForEach(['local_only', 'online'], (mode: ProcessingMode) => {
          Button(this.label(mode))
            .layoutWeight(1)
            .height(42)
            .fontSize(12)
            .fontColor(this.mode === mode ? '#FFFFFF' : '#334155')
            .backgroundColor(this.mode === mode ? this.accentColor : '#F1F5F9')
            .enabled(!this.disabled)
            .onClick(() => { this.onModeChange(mode); })
        })
      }.width('100%')
      Text(this.mode === 'local_only' ? '仅使用端侧能力。' : this.onlineHint)
        .fontSize(12).fontColor('#64748B').margin({ top: 8 }).width('100%')
    }.width('100%')
  }
}
