import { DecisionCard, PageHero } from '../components/PageComponents';
import { EvidenceList, RiskReport } from '../components/RiskComponents';
import type { LinkCheckResponse, TextFinding } from '../types/privacy';

const sourceOptions = ['短信', '群聊', '邮件', '二维码', '二手交易', '客服', '学校通知', '陌生人私信', '其他'];

interface LinkPageProps {
  url: string;
  source: string;
  qrFile: File | null;
  qrMessage: string;
  result: LinkCheckResponse | null;
  loading: boolean;
  loadingQr: boolean;
  onBack: () => void;
  onUrlChange: (value: string) => void;
  onSourceChange: (value: string) => void;
  onQrUpload: (file: File | null) => Promise<void>;
  onCheck: () => Promise<void>;
}

function evidenceFromResult(result: LinkCheckResponse | null): TextFinding[] {
  return result?.checks.map((item) => ({ label: `${item.label} / ${item.status}`, evidence: item.message, riskLevel: item.riskLevel })) ?? [];
}

export default function LinkPage(props: LinkPageProps) {
  return (
    <>
      <PageHero eyebrow="Link Guard" title="Link Guard 链接卫士" copy="打开链接之前，先做一次安全体检。" onBack={props.onBack} />
      <div className="tool-grid">
        <section className="card form-card">
          <div className="section-title"><span>01</span><div><h3>链接安全体检</h3><p>输入 URL、短链接、二维码解析出的内容或链接来源说明。</p></div></div>
          <input value={props.url} onChange={(event) => props.onUrlChange(event.target.value)} placeholder="https://example.com" aria-label="待检查链接" />
          <label className="field-label">链接来源
            <select value={props.source} onChange={(event) => props.onSourceChange(event.target.value)}>
              {sourceOptions.map((source) => <option key={source} value={source}>{source}</option>)}
            </select>
          </label>
          <label className="upload-box doc-upload-box">
            <input aria-label="二维码图片" type="file" accept="image/png,image/jpeg,image/webp" onChange={(event) => void props.onQrUpload(event.target.files?.[0] ?? null)} />
            <span className="upload-icon">+</span>
            <strong>{props.loadingQr ? '二维码解析中...' : props.qrFile?.name ?? '选择二维码图片'}</strong>
            <span>图片仅在本地解析，不会主动访问二维码中的链接。</span>
          </label>
          {props.qrMessage && <p className="muted">{props.qrMessage}</p>}
          <button className="primary-button" disabled={props.loading || props.loadingQr || !props.url.trim()} onClick={props.onCheck}>
            {props.loading ? '体检中...' : '开始链接安全体检'}
          </button>
        </section>
        <div className="report-stack">
          <RiskReport title="链接安全体检报告" riskLevel={props.result?.riskLevel} score={props.result?.score} summary={props.result?.summary} evidence={evidenceFromResult(props.result)} suggestions={props.result?.suggestions} />
          {props.result && <>
            <section className="card detail-card">
              <div className="section-title"><span>P</span><div><h3>可疑参数与来源风险</h3><p>{props.result.normalizedUrl}</p></div></div>
              <EvidenceList evidence={[
                ...props.result.suspiciousParams.map((item) => ({ label: item.name, evidence: item.reason, riskLevel: item.riskLevel })),
                { label: `来源场景：${props.result.sourceRisk.source}`, evidence: props.result.sourceRisk.reason, riskLevel: props.result.sourceRisk.riskLevel }
              ]} />
            </section>
            <DecisionCard title="是否建议打开链接" ok={props.result.shouldOpen} positive="可以谨慎打开" negative="不建议直接打开" />
          </>}
        </div>
      </div>
    </>
  );
}
