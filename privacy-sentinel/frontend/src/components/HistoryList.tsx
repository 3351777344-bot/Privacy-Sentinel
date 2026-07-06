import type { HistoryRecord } from '../types/privacy';
import { riskText } from './RiskSummary';

interface HistoryListProps {
  records: HistoryRecord[];
}

export default function HistoryList({ records }: HistoryListProps) {
  return (
    <section className="card history-card">
      <div className="section-title">
        <span>07</span>
        <div>
          <h3>最近检测记录</h3>
          <p>用于展示分享前的安全检查闭环。</p>
        </div>
      </div>
      {records.length === 0 ? (
        <p className="muted">暂无历史记录。</p>
      ) : (
        <div className="history-list">
          {records.map((record) => (
            <article className="history-item" key={record.imageId}>
              <div>
                <strong>{record.imageId}</strong>
                <span>{record.createdAt}</span>
              </div>
              <em className={`risk-pill ${record.riskLevel}`}>{riskText[record.riskLevel]}</em>
              <span className="status">{record.status}</span>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
