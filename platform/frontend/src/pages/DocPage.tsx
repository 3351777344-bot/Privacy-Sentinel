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
          <div className="local-mode-banner"><strong>本地材料检查</strong><span>文件内容仅在本机解析，不会上传到第三方模型服务</span></div>
          <textarea value={props.requirement} onChange={(event) => props.onRequirementChange(event.target.value)} placeholder="粘贴课程论文、比赛材料、报名附件等提交要求" />
          <label className={`upload-box doc-upload-box ${props.files.length ? 'has-file' : ''}`}>
            <input multiple type="file" accept=".txt,.md,.pdf,.docx,.png,.jpg,.jpeg,.zip,.rar,.ppt,.pptx" onChange={(event) => props.onFilesChange(Array.from(event.target.files ?? []))} />
            <span className="upload-icon">+</span>
            <strong>{props.files.length ? `已选择 ${props.files.length} 个文件` : '选择或拖入多个材料文件'}</strong>
            <span>PDF / DOCX / TXT / MD / PNG / JPG / ZIP / RAR / PPT / PPTX</span>
          </label>
          {props.files.length > 0 && (
            <div className="selected-file-list" aria-label="已选择材料">
              {props.files.map((file, index) => (
                <div className="selected-file" key={`${file.name}-${file.size}-${index}`}>
                  <span className="selected-file-icon">▤</span>
                  <div>
                    <small>材料 {index + 1}</small>
                    <strong title={file.name}>{file.name}</strong>
                  </div>
                  <span className="selected-file-size">
                    {file.size >= 1024 * 1024
                      ? `${(file.size / (1024 * 1024)).toFixed(1)} MB`
                      : `${Math.max(1, Math.round(file.size / 1024))} KB`}
                  </span>
                  <button
                    aria-label={`移除 ${file.name}`}
                    className="remove-file"
                    onClick={() => props.onFilesChange(props.files.filter((_, itemIndex) => itemIndex !== index))}
                    type="button"
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          )}
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
