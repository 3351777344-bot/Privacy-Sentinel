import type { HistoryRecord, RiskLevel, TextFinding } from '../types/privacy';

export const riskText: Record<RiskLevel, string> = {
  high: '高风险',
  medium: '中风险',
  low: '低风险'
};

export const riskToneText: Record<RiskLevel, string> = {
  high: '建议立即处理',
  medium: '建议复核后处理',
  low: '当前较安全'
};

interface RiskBadgeProps {
  level: RiskLevel;
  compact?: boolean;
}

export function RiskBadge({ level, compact = false }: RiskBadgeProps) {
  return (
    <em className={`risk-pill ${level} ${compact ? 'compact' : ''}`}>
      {compact ? level : `${riskText[level]} / ${level}`}
    </em>
  );
}

interface ScoreCardProps {
  score: number;
  title?: string;
  subtitle?: string;
}

export function ScoreCard({ score, title = '安全评分', subtitle }: ScoreCardProps) {
  const level: RiskLevel = score >= 85 ? 'low' : score >= 65 ? 'medium' : 'high';

  return (
    <section className={`score-card unified-score ${level}`}>
      <span>{title}</span>
      <strong>{score}</strong>
      <p>{subtitle ?? riskToneText[level]}</p>
    </section>
  );
}

interface SuggestionListProps {
  suggestions: string[];
  emptyText?: string;
}

export function SuggestionList({ suggestions, emptyText = '暂无需要处理的建议。' }: SuggestionListProps) {
  return (
    <div className="suggestion-box">
      <strong>建议操作</strong>
      {suggestions.length > 0 ? suggestions.map((suggestion) => <p key={suggestion}>{suggestion}</p>) : <p>{emptyText}</p>}
    </div>
  );
}

interface RiskReportProps {
  title: string;
  riskLevel?: RiskLevel;
  score?: number;
  summary?: string;
  evidence?: TextFinding[];
  suggestions?: string[];
  emptyText?: string;
  badgeLabel?: string;
}

export function RiskReport({
  title,
  riskLevel,
  score,
  summary,
  evidence = [],
  suggestions = [],
  emptyText = '完成检测后，这里会展示风险等级、检测摘要、风险证据和建议操作。',
  badgeLabel = 'R'
}: RiskReportProps) {
  return (
    <section className="card result-card">
      <div className="section-title">
        <span>{badgeLabel}</span>
        <div>
          <h3>{title}</h3>
          <p>统一使用 high / medium / low 风险等级和 0-100 安全评分。</p>
        </div>
      </div>
      {riskLevel ? (
        <>
          <div className={`risk-banner ${riskLevel}`}>
            <RiskBadge level={riskLevel} />
            <span>{summary}</span>
            {typeof score === 'number' && <b>{score} / 100</b>}
          </div>
          <EvidenceList evidence={evidence} />
          <SuggestionList suggestions={suggestions} />
        </>
      ) : (
        <p className="muted">{emptyText}</p>
      )}
    </section>
  );
}

export function EvidenceList({ evidence }: { evidence: TextFinding[] }) {
  if (evidence.length === 0) {
    return <p className="muted">暂无风险证据。</p>;
  }

  return (
    <div className="finding-list">
      {evidence.map((item, index) => (
        <article className={`finding-item ${item.riskLevel}`} key={`${item.label}-${index}`}>
          <div>
            <strong>{item.label}</strong>
            <span>{item.evidence}</span>
          </div>
          <RiskBadge level={item.riskLevel} compact />
        </article>
      ))}
    </div>
  );
}

interface HistoryTimelineProps {
  records: HistoryRecord[];
  title?: string;
  description?: string;
}

export function HistoryTimeline({
  records,
  title = '最近安全检测历史',
  description = '记录最近的检测结果，方便复盘处理状态和风险变化。'
}: HistoryTimelineProps) {
  const moduleLabels = {
    privacy: '隐私哨兵',
    code: '代码卫士',
    link: '链接卫士',
    doc: '提交护盾'
  };
  return (
    <section className="card history-card">
      <div className="section-title">
        <span>H</span>
        <div>
          <h3>{title}</h3>
          <p>{description}</p>
        </div>
      </div>
      {records.length === 0 ? (
        <p className="muted">暂无历史检测记录。</p>
      ) : (
        <div className="history-list timeline-list">
          {records.slice(0, 8).map((record) => (
            <article className="history-item timeline-item" key={record.recordId || `${record.imageId}-${record.createdAt}`}>
              <div>
                <strong>{record.summary}</strong>
                <span>
                  {moduleLabels[record.module ?? 'privacy']} · {record.score ?? '--'} 分 ·{' '}
                  {new Date(record.createdAt).toLocaleString('zh-CN', { hour12: false })}
                </span>
              </div>
              <RiskBadge level={record.riskLevel} compact />
              <span className="status">{record.status}</span>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
