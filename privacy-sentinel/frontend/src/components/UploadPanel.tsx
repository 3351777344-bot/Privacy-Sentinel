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
          <p>选择截图、快递单、订单页或聊天记录，先用 mock 检测跑通演示流程。</p>
        </div>
      </div>
      <div className="upload-box" onClick={() => inputRef.current?.click()}>
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
        <strong>{file ? file.name : '点击选择本地图片'}</strong>
        <span>当前 Demo 不接付费大模型，检测项由后端 mock 生成。</span>
      </div>
      <button className="primary-button" disabled={!file || loading} onClick={handleSubmit}>
        {loading ? 'AI 检测中...' : '开始隐私检测'}
      </button>
    </section>
  );
}
