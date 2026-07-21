import { useRef, useState } from 'react';
import type { ProcessingMode } from '../types/privacy';
import { FileSummary, ProcessingModeSelector } from './PageComponents';

const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB
const ALLOWED_TYPES = ['image/png', 'image/jpeg', 'image/webp'];

interface UploadPanelProps {
  loading: boolean;
  onDetect: (file: File) => Promise<void>;
  processingMode?: ProcessingMode;
  onProcessingModeChange?: (mode: ProcessingMode) => void;
}

export default function UploadPanel({
  loading,
  onDetect,
  processingMode = 'local',
  onProcessingModeChange = () => undefined
}: UploadPanelProps) {
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
      <ProcessingModeSelector value={processingMode} onChange={onProcessingModeChange} />
      <p className="mode-note">
        {processingMode === 'local'
          ? '本地模式：OCR、二维码与规则检测均在本机完成，图片不会发送到模型服务。'
          : '联网模式：图片将发送到已配置的 Qwen VL 服务增强识别；服务不可用时自动回退本地检测。'}
      </p>
      <div className={`upload-box ${file ? 'has-file' : ''} ${loading ? 'scanning' : ''} ${fileError ? 'upload-error' : ''}`} onClick={() => !loading && inputRef.current?.click()} role="button" tabIndex={0} onKeyDown={handleKeyDown}>
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
        {file ? (
          <>
            <FileSummary file={file} label="待检测图片" />
            <span>点击可重新选择图片</span>
          </>
        ) : (
          <>
            <span className="upload-icon">+</span>
            <strong>点击选择图片</strong>
            <span>支持 PNG / JPG / WEBP，单张不超过 10 MB。</span>
          </>
        )}
      </div>
      {fileError && <p className="upload-error-msg">{fileError}</p>}
      <button className="primary-button" disabled={!file || loading || !!fileError} onClick={handleSubmit}>
        {loading ? '检测中...' : `开始${processingMode === 'local' ? '本地' : '联网增强'}检测`}
      </button>
    </section>
  );
}
