import { ProcessingMode } from '../services/ScanPolicy';
export { ProcessingMode } from '../services/ScanPolicy';

@Component
export struct ProcessingModeSelector {
  @Prop mode: ProcessingMode = 'hybrid';
  @Prop onlineHint: string = '本地完成后逐次授权增强';
  @Prop disabled: boolean = false;
  onModeChange: (mode: ProcessingMode) => void = (_mode: ProcessingMode) => {};

  private label(mode: ProcessingMode): string {
    if (mode === 'local_only') { return '仅本地'; }
    return mode === 'hybrid' ? '本地优先' : '联网分析';
  }

  build() {
    Column() {
      Row() {
        ForEach(['local_only', 'hybrid', 'online'], (mode: ProcessingMode) => {
          Button(this.label(mode))
            .layoutWeight(1)
            .height(42)
            .fontSize(12)
            .fontColor(this.mode === mode ? '#FFFFFF' : '#334155')
            .backgroundColor(this.mode === mode ? '#2563EB' : '#F1F5F9')
            .enabled(!this.disabled)
            .onClick(() => { this.onModeChange(mode); })
        })
      }.width('100%')
      Text(this.mode === 'local_only' ? '禁止网络分析；仅使用端侧能力。' :
        (this.mode === 'hybrid' ? '先完成本地检测，主动点击增强后才请求本次授权。' :
          '先执行本地检查，再请求本次上传授权；拒绝后保留本地结果。'))
        .fontSize(12).fontColor('#64748B').margin({ top: 8 }).width('100%')
    }.width('100%')
  }
}
