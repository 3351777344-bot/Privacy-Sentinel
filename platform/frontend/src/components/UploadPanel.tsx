import { useRef, useState } from 'react';

const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB
const ALLOWED_TYPES = ['image/png', 'image/jpeg', 'image/webp'];

interface UploadPanelProps {
  loading: boolean;
  onDetect: (file: File) => Promise<void>;
}

export default function UploadPanel({ loading, onDetect }: UploadPanelProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [fileError, setFileError] = useState('');

  function validateFile(f: File): boolean {
    setFileError('');
    if (!ALLOWED_TYPES.includes(f.type)) {
      setFileError('不支持的文件格式，请上传 PNG / JPG / WEBP 图片。');
      return false;
    }
    if (f.size > MAX_IMAGE_BYTES) {
      const mb = (f.size / (1024 * 1024)).toFixed(1);
      setFileError(`图片文件过大（${mb} MB），最大允许 10 MB。`);
      return false;
    }
    return true;
  }

  async function handleSubmit() {
    if (!file) return;
    if (!validateFile(file)) return;
    await onDetect(file);
  }

  function handleKeyDown(event: React.KeyboardEvent) {
    if (!loading && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      inputRef.current?.click();
    }
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
      <div className={`upload-box ${loading ? 'scanning' : ''} ${fileError ? 'upload-error' : ''}`} onClick={() => !loading && inputRef.current?.click()} role="button" tabIndex={0} onKeyDown={handleKeyDown}>
        <input
          ref={inputRef}
          type="file"
          accept=".png,.jpg,.jpeg,.webp"
          aria-label="选择图片文件"
          onChange={(event) => {
            const f = event.target.files?.[0] ?? null;
            setFile(f);
            if (f) validateFile(f);
          }}
        />
        <span className="upload-icon">+</span>
        <strong>{file ? file.name : '点击选择本地图片'}</strong>
        <span>支持 PNG / JPG / WEBP，单张不超过 10 MB。</span>
      </div>
      {fileError && <p className="upload-error-msg">{fileError}</p>}
      <button className="primary-button" disabled={!file || loading || !!fileError} onClick={handleSubmit}>
        {loading ? '本地 OCR 检测中...' : '开始隐私检测'}
      </button>
    </section>
  );
}
