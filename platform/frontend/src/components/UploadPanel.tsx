import { useRef, useState } from 'react';

interface UploadPanelProps {
  loading: boolean;
  onDetect: (file: File) => Promise<void>;
}

export default function UploadPanel({ loading, onDetect }: UploadPanelProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);

  async function handleSubmit() {
    if (!file) return;
    await onDetect(file);
  }

  return (
    <section className="card upload-panel">
      <div className="section-title">
        <span>01</span>
        <div>
          <h3>图片上传</h3>
          <p>选择截图、快递单、订单页或聊天记录，先扫描潜在隐私风险。</p>
        </div>
      </div>
      <div className={`upload-box ${loading ? 'scanning' : ''}`} onClick={() => !loading && inputRef.current?.click()} role="button" tabIndex={0}>
        <input
          ref={inputRef}
          type="file"
          accept=".png,.jpg,.jpeg,.webp"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
        <span className="upload-icon">+</span>
        <strong>{file ? file.name : '点击选择本地图片'}</strong>
        <span>支持 PNG / JPG / WEBP，单张不超过 10 MB。</span>
      </div>
      <button className="primary-button" disabled={!file || loading} onClick={handleSubmit}>
        {loading ? '本地 OCR 检测中...' : '开始隐私检测'}
      </button>
    </section>
  );
}
