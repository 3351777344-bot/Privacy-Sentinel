import type { PrivacyItem } from '../types/privacy';
import { RiskBadge } from './RiskComponents';

interface PrivacyItemListProps {
  items: PrivacyItem[];
}

const SOURCE_LABELS: Record<string, string> = {
  ocr: '文字识别',
  qr: '二维码',
  face: '人脸识别',
  rule: '规则检测',
  vision_api: '深度分析',
};

export default function PrivacyItemList({ items }: PrivacyItemListProps) {
  return (
    <section className="card">
      <div className="section-title">
        <span>04</span>
        <div>
          <h3>风险证据列表</h3>
          <p>逐项展示隐私类型、识别内容、风险等级和处理建议。</p>
        </div>
      </div>
      {items.length === 0 ? (
        <p className="muted">暂无检测项。完成图片检测后会自动生成列表。</p>
      ) : (
        <div className="privacy-list">
          {items.map((item) => (
            <article className={`privacy-item ${item.riskLevel}`} key={item.id}>
              <div>
                <strong>{item.label}</strong>
                <span className="source-tag">{SOURCE_LABELS[item.source ?? 'rule'] ?? '自动识别'}</span>
                <span>{item.text}</span>
              </div>
              <RiskBadge level={item.riskLevel} compact />
              <p>{item.suggestion}</p>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
