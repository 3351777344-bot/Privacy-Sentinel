import DocReportPanel from '../components/DocReportPanel';
import { PageHero } from '../components/PageComponents';
import type { DocCheckResponse } from '../types/privacy';

interface DocPageProps {
  requirement: string;
  files: File[];
  result: DocCheckResponse | null;
  loading: boolean;
  onBack: () => void;
  onRequirementChange: (value: string) => void;
  onFilesChange: (files: File[]) => void;
  onCheck: () => Promise<void>;
}

export default function DocPage(props: DocPageProps) {
  return (
    <>
      <PageHero eyebrow="Doc Shield" title="Doc Shield 提交护盾" copy="按“输入提交要求 + 上传材料 + 生成提交检查报告”的流程，检查材料完整性、格式规范、隐私风险、提交建议和安全评分。" onBack={props.onBack} />
      <div className="tool-grid doc-tool-grid">
        <section className="card form-card doc-form-card">
          <div className="section-title"><span>01</span><div><h3>提交要求与材料上传</h3><p>支持 txt、md、pdf、docx 内容解析；图片和压缩包会先检查文件名、后缀和上传状态。</p></div></div>
          <textarea value={props.requirement} onChange={(event) => props.onRequirementChange(event.target.value)} placeholder="粘贴课程论文、比赛材料、报名附件等提交要求" />
          <label className="upload-box doc-upload-box">
            <input multiple type="file" accept=".txt,.md,.pdf,.docx,.png,.jpg,.jpeg,.zip,.rar,.ppt,.pptx" onChange={(event) => props.onFilesChange(Array.from(event.target.files ?? []))} />
            <span className="upload-icon">+</span>
            <strong>{props.files.length ? `已选择 ${props.files.length} 个文件` : '选择或拖入多个材料文件'}</strong>
            <span>PDF / DOCX / TXT / MD / PNG / JPG / ZIP / RAR / PPT / PPTX</span>
          </label>
          {props.files.length > 0 && <div className="file-chip-list">{props.files.map((file) => <span key={`${file.name}-${file.size}`}>{file.name}</span>)}</div>}
          <div className="capability-list"><span>要求解析</span><span>完整性检查</span><span>格式规范</span><span>隐私风险</span></div>
          <button className="primary-button" disabled={props.loading || !props.requirement.trim() || props.files.length === 0} onClick={props.onCheck}>
            {props.loading ? '检查中...' : '生成提交检查报告'}
          </button>
        </section>
        <DocReportPanel result={props.result} />
      </div>
    </>
  );
}
