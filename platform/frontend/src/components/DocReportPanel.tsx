import type { DocCheckResponse } from '../types/privacy';
import { EvidenceList, RiskBadge, RiskReport, SuggestionList } from './RiskComponents';

export default function DocReportPanel({ result }: { result: DocCheckResponse | null }) {
  if (!result) {
    return (
      <RiskReport
        title="提交检查报告"
        emptyText="上传材料并开始检查后，这里会展示要求解析、材料完整性、格式规范、隐私风险、提交建议和安全评分。"
      />
    );
  }

  const groups = {
    completeness: result.checks.filter((item) => item.category === 'completeness'),
    format: result.checks.filter((item) => item.category === 'format'),
    privacy: result.checks.filter((item) => item.category === 'privacy')
  };

  return (
    <section className="card result-card doc-report">
      <div className="section-title">
        <span>R</span>
        <div>
          <h3>提交检查报告</h3>
          <p>{result.summary}</p>
        </div>
      </div>
      <div className={`risk-banner ${result.riskLevel}`}>
        <RiskBadge level={result.riskLevel} />
        <span>提交安全评分</span>
        <b>{result.score} / 100</b>
      </div>

      <div className="parsed-requirements">
        <h4>解析出的提交要求</h4>
        <RequirementItem label="文件格式" value={result.parsedRequirements.formats.join('、') || '未明确'} />
        <RequirementItem label="命名规则" value={result.parsedRequirements.namingRule || '未明确'} />
        <RequirementItem label="必需材料" value={result.parsedRequirements.requiredMaterials.join('、') || '未明确'} />
        <RequirementItem label="字数/页数" value={result.parsedRequirements.lengthRequirement || '未明确'} />
        <RequirementItem label="截止时间" value={result.parsedRequirements.deadline || '未明确'} />
      </div>

      <DocCheckGroup title="材料完整性" items={groups.completeness} />
      <DocCheckGroup title="格式规范" items={groups.format} />
      <DocCheckGroup title="隐私风险" items={groups.privacy} />

      <div className="uploaded-files">
        <h4>已上传材料</h4>
        {result.files.map((file) => (
          <div key={file.fileName}>
            <strong>{file.fileName}</strong>
            <span>
              .{file.extension || '无后缀'} / {file.status} / {file.wordCount} 字
            </span>
          </div>
        ))}
      </div>

      <SuggestionList suggestions={result.suggestions} />
    </section>
  );
}

function RequirementItem({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function DocCheckGroup({ title, items }: { title: string; items: DocCheckResponse['checks'] }) {
  return (
    <div className="doc-check-group">
      <h4>{title}</h4>
      <EvidenceList evidence={items} />
    </div>
  );
}
