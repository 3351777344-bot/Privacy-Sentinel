import type { PrivacyItem } from '../types/privacy';
import { riskText } from './RiskSummary';

interface PrivacyItemListProps {
  items: PrivacyItem[];
}

export default function PrivacyItemList({ items }: PrivacyItemListProps) {
  return (
    <section className="card">
      <div className="section-title">
        <span>04</span>
        <div>
          <h3>隐私检测项</h3>
          <p>列表中的建议后续可接入 OCR、二维码识别和人脸检测。</p>
        </div>
      </div>
      {items.length === 0 ? (
        <p className="muted">暂无检测项。</p>
      ) : (
        <div className="privacy-list">
          {items.map((item) => (
            <article className="privacy-item" key={item.id}>
              <div>
                <strong>{item.label}</strong>
                <span>{item.text}</span>
              </div>
              <em className={`risk-pill ${item.riskLevel}`}>{riskText[item.riskLevel]}</em>
              <p>{item.suggestion}</p>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
