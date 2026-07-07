import type { DetectResult } from '../types/privacy';
import { EvidenceList, RiskReport, riskText } from './RiskComponents';

interface RiskSummaryProps {
  result?: DetectResult | null;
}

function privacyScore(result?: DetectResult | null) {
  if (!result) return 100;
  const penalty = result.items.reduce((total, item) => {
    if (item.riskLevel === 'high') return total + 18;
    if (item.riskLevel === 'medium') return total + 9;
    return total + 2;
  }, 0);
  return Math.max(0, 100 - penalty);
}

export default function RiskSummary({ result }: RiskSummaryProps) {
  const counts = {
    high: result?.items.filter((item) => item.riskLevel === 'high').length ?? 0,
    medium: result?.items.filter((item) => item.riskLevel === 'medium').length ?? 0,
    low: result?.items.filter((item) => item.riskLevel === 'low').length ?? 0
  };

  if (!result) {
    return (
      <RiskReport
        title="隐私检测报告"
        badgeLabel="03"
        emptyText="上传图片后，这里会展示风险等级、检测摘要、风险证据和处理建议。"
      />
    );
  }

  return (
    <section className="card result-card">
      <div className="section-title">
        <span>03</span>
        <div>
          <h3>隐私检测报告</h3>
          <p>检测图片中的高、中、低风险隐私信息，并给出分享前处理建议。</p>
        </div>
      </div>
      <div className={`risk-banner ${result.riskLevel}`}>
        <strong>{riskText[result.riskLevel]}</strong>
        <span>{result.summary}</span>
        <b>{privacyScore(result)} / 100</b>
      </div>
      <div className="stats-grid">
        <div>
          <b>{result.items.length}</b>
          <span>检测项</span>
        </div>
        <div className="stat-high">
          <b>{counts.high}</b>
          <span>高风险</span>
        </div>
        <div className="stat-medium">
          <b>{counts.medium}</b>
          <span>中风险</span>
        </div>
        <div className="stat-low">
          <b>{counts.low}</b>
          <span>低风险</span>
        </div>
      </div>
      <EvidenceList
        evidence={result.items.map((item) => ({
          label: item.label,
          evidence: `${item.text}：${item.suggestion}`,
          riskLevel: item.riskLevel
        }))}
      />
    </section>
  );
}

export { riskText };
