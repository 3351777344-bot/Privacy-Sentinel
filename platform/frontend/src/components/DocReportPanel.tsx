import type { DocCheckResponse } from '../types/privacy';
import { EvidenceList, RiskBadge, RiskReport, SuggestionList } from './RiskComponents';

const FILE_STATUS_LABELS: Record<string, string> = {
  parsed: '已解析内容',
  metadata_only: '仅读取文件信息',
  parse_failed: '解析失败',
};

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
  const parsed = result.parsedRequirements;
  const online = parsed.source === 'online';
  const contentRequirements = parsed.contentRequirements ?? [];
  // `source` missing entirely means the backend predates the online pass: it
  // ignored `processing_mode` without erroring, so a user who picked 联网增强
  // would otherwise see a local report with nothing to explain it. Deployment is
  // manual in this project, so that skew is a normal state, not an edge case.
  const backendOutdated = parsed.source === undefined;

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
        <h4>
          解析出的提交要求
          <span className={`requirement-source ${online ? 'online' : 'local'}`}>
            {online ? '在线 AI 识别' : '本地规则解析'}
          </span>
        </h4>
        {backendOutdated && (
          <p className="requirement-warning">
            当前后端版本不包含联网解析：它忽略了处理模式，本报告完全由本地规则生成。
            部署后端后重新检查即可使用「联网增强」。
          </p>
        )}
        {parsed.modelWarning && <p className="requirement-warning">{parsed.modelWarning}</p>}
        <RequirementItem label="文件格式" value={parsed.formats.join('、') || '未明确'} />
        <RequirementItem label="命名规则" value={parsed.namingRule || '未明确'} />
        <RequirementItem label="必需材料" value={parsed.requiredMaterials.join('、') || '未明确'} />
        <RequirementItem label="字数/页数" value={parsed.lengthRequirement || '未明确'} />
        <RequirementItem label="截止时间" value={parsed.deadline || '未明确'} />
        {contentRequirements.length > 0 && (
          <RequirementItem label="内容要求" value={contentRequirements.join('；')} />
        )}
        {parsed.notes && <RequirementItem label="需人工确认" value={parsed.notes} />}
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
              .{file.extension || '无后缀'} / {FILE_STATUS_LABELS[file.status] ?? '已读取'} / {file.wordCount} 字
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
