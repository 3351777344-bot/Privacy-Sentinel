import type { DetectResult, RiskLevel } from '../types/privacy';

export const riskText: Record<RiskLevel, string> = {
  high: '高风险',
  medium: '中风险',
  low: '低风险'
};

interface RiskSummaryProps {
  result?: DetectResult | null;
}

export default function RiskSummary({ result }: RiskSummaryProps) {
  const counts = {
    high: result?.items.filter((item) => item.riskLevel === 'high').length ?? 0,
    medium: result?.items.filter((item) => item.riskLevel === 'medium').length ?? 0,
    low: result?.items.filter((item) => item.riskLevel === 'low').length ?? 0
  };

  return (
    <section className="card">
      <div className="section-title">
        <span>03</span>
        <div>
          <h3>风险概览</h3>
          <p>检测完成后优先处理高风险信息，再决定是否继续分享。</p>
        </div>
      </div>
      {result ? (
        <>
          <div className={`risk-banner ${result.riskLevel}`}>
            <strong>{riskText[result.riskLevel]}</strong>
            <span>{result.summary}</span>
          </div>
          <div className="stats-grid">
            <div><b>{result.items.length}</b><span>检测项</span></div>
            <div className="stat-high"><b>{counts.high}</b><span>高风险</span></div>
            <div className="stat-medium"><b>{counts.medium}</b><span>中风险</span></div>
            <div className="stat-low"><b>{counts.low}</b><span>低风险</span></div>
          </div>
        </>
      ) : (
        <p className="muted">上传图片后，这里会展示整体风险等级、检测项数量和风险分布。</p>
      )}
    </section>
  );
}
