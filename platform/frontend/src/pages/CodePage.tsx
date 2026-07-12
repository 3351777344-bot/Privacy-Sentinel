import { DecisionCard, PageHero } from '../components/PageComponents';
import { RiskReport } from '../components/RiskComponents';
import type { CodeAnalyzeResponse, TextFinding } from '../types/privacy';

const languageOptions = [
  { value: 'auto', label: '自动识别' },
  { value: 'python', label: 'Python' },
  { value: 'java', label: 'Java' },
  { value: 'javascript', label: 'JavaScript' },
  { value: 'typescript', label: 'TypeScript' },
  { value: 'sql', label: 'SQL' },
  { value: 'other', label: 'Other' }
];

interface CodePageProps {
  text: string;
  language: string;
  file: File | null;
  result: CodeAnalyzeResponse | null;
  loading: boolean;
  onBack: () => void;
  onTextChange: (value: string) => void;
  onLanguageChange: (value: string) => void;
  onFileChange: (file: File | null) => void;
  onAnalyze: () => Promise<void>;
}

function evidenceFromResult(result: CodeAnalyzeResponse | null): TextFinding[] {
  return (
    result?.vulnerabilities.map((item) => ({
      label: item.line ? `${item.title} / 第 ${item.line} 行` : item.title,
      evidence: `${item.snippet || '未截取到代码片段'}。${item.reason}`,
      riskLevel: item.riskLevel
    })) ?? []
  );
}

export default function CodePage(props: CodePageProps) {
  return (
    <>
      <PageHero eyebrow="Code Guardian" title="Code Guardian 代码卫士" copy="提交代码之前，先检查潜在安全风险。" onBack={props.onBack} />
      <div className="tool-grid">
        <section className="card form-card">
          <div className="section-title">
            <span>01</span>
            <div>
              <h3>代码输入区</h3>
              <p>粘贴代码或上传单个代码文件，当前不强制支持 zip 项目扫描。</p>
            </div>
          </div>
          <label className="field-label">
            代码语言
            <select value={props.language} onChange={(event) => props.onLanguageChange(event.target.value)}>
              {languageOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </label>
          {props.result && (
            <p className="muted">
              识别语言：{props.result.language}（来源：{props.result.languageSource}，置信度：{Math.round(props.result.languageConfidence * 100)}%）
            </p>
          )}
          <textarea value={props.text} onChange={(event) => props.onTextChange(event.target.value)} />
          <label className="upload-box doc-upload-box">
            <input type="file" accept=".py,.java,.js,.ts,.sql,.txt,.zip" onChange={(event) => props.onFileChange(event.target.files?.[0] ?? null)} />
            <span className="upload-icon">+</span>
            <strong>{props.file ? props.file.name : '选择单个代码文件'}</strong>
            <span>.py / .java / .js / .ts / .sql / .txt；zip 为后续扩展功能</span>
          </label>
          {props.file?.name.toLowerCase().endsWith('.zip') && <p className="muted">当前版本暂不解析 zip 项目包，请上传单个代码文件或直接粘贴核心代码片段。</p>}
          <button className="primary-button" disabled={props.loading || (!props.text.trim() && !props.file)} onClick={props.onAnalyze}>
            {props.loading ? '检测中...' : '开始代码安全检测'}
          </button>
        </section>
        <div className="report-stack">
          <RiskReport title="代码安全体检报告" riskLevel={props.result?.riskLevel} score={props.result?.score} summary={props.result?.summary} evidence={evidenceFromResult(props.result)} suggestions={props.result?.suggestions} />
          {props.result && <DecisionCard title="是否建议直接提交代码" ok={props.result.shouldSubmit} positive="可以提交" negative={props.result.riskLevel === 'high' ? '不建议提交' : '建议修复后提交'} />}
        </div>
      </div>
    </>
  );
}
