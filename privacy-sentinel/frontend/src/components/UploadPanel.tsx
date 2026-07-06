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
          <p>选择截图、快递单、订单页或聊天记录，先让 AI 扫描潜在隐私风险。</p>
        </div>
      </div>
      <div className="upload-box" onClick={() => inputRef.current?.click()}>
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
        <span className="upload-icon">+</span>
        <strong>{file ? file.name : '点击选择本地图片'}</strong>
        <span>支持常见图片格式，检测完成后会在原图上标注隐私框。</span>
      </div>
      <button className="primary-button" disabled={!file || loading} onClick={handleSubmit}>
        {loading ? 'AI 检测中...' : '开始隐私检测'}
      </button>
    </section>
  );
}
