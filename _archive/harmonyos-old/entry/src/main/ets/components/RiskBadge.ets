import { RiskLevel } from '../models/PrivacyModels';

@Component
export struct RiskBadge {
  @Prop level: RiskLevel;
  @Prop size: 'small' | 'large' = 'small';

  private getText(): string {
    switch (this.level) {
      case 'high':
        return '高风险';
      case 'medium':
        return '中风险';
      case 'low':
        return '低风险';
      default:
        return '安全';
    }
  }

  private getColor(): string {
    switch (this.level) {
      case 'high':
        return '#E5484D';
      case 'medium':
        return '#F59E0B';
      case 'low':
        return '#2563EB';
      default:
        return '#16A34A';
    }
  }

  build() {
    Text(this.getText())
      .fontSize(this.size === 'large' ? 18 : 12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.getColor())
      .padding({
        left: this.size === 'large' ? 14 : 10,
        right: this.size === 'large' ? 14 : 10,
        top: this.size === 'large' ? 8 : 5,
        bottom: this.size === 'large' ? 8 : 5
      })
      .backgroundColor(`${this.getColor()}18`)
      .borderRadius(16)
  }
}

