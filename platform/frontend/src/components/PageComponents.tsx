import { RiskBadge } from './RiskComponents';
import type { ProcessingMode } from '../types/privacy';

export function PageHero({
  eyebrow,
  title,
  copy,
  onBack
}: {
  eyebrow: string;
  title: string;
  copy: string;
  onBack: () => void;
}) {
  return (
    <header className="page-hero">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p>{copy}</p>
      </div>
      <button onClick={onBack}>返回安全中心</button>
    </header>
  );
}

export function ImageCompareCard({ title, imageUrl }: { title: string; imageUrl: string }) {
  return (
    <div className="compare-card">
      <strong>{title}</strong>
      <img src={imageUrl} alt={title} />
    </div>
  );
}

export function ProcessingModeSelector({
  value,
  onChange,
  onlineAvailable = true
}: {
  value: ProcessingMode;
  onChange: (mode: ProcessingMode) => void;
  onlineAvailable?: boolean;
}) {
  return (
    <div className="processing-mode" role="group" aria-label="处理模式">
      <button className={value === 'local' ? 'selected' : ''} onClick={() => onChange('local')} type="button">
        <strong>本地处理</strong>
        <span>材料仅在本机分析</span>
      </button>
      <button
        className={value === 'online' ? 'selected' : ''}
        disabled={!onlineAvailable}
        onClick={() => onChange('online')}
        type="button"
      >
        <strong>联网增强</strong>
        <span>{onlineAvailable ? '调用已配置的模型服务' : '当前模块仅支持本地'}</span>
      </button>
    </div>
  );
}

export function FileSummary({ file, label = '已选择文件' }: { file: File; label?: string }) {
  const size = file.size >= 1024 * 1024
    ? `${(file.size / (1024 * 1024)).toFixed(1)} MB`
    : `${Math.max(1, Math.round(file.size / 1024))} KB`;
  return (
    <div className="selected-file">
      <span className="selected-file-icon">▤</span>
      <div>
        <small>{label}</small>
        <strong title={file.name}>{file.name}</strong>
      </div>
      <span className="selected-file-size">{size}</span>
    </div>
  );
}

export function DecisionCard({
  title,
  ok,
  positive,
  negative
}: {
  title: string;
  ok: boolean;
  positive: string;
  negative: string;
}) {
  return (
    <section className={`card decision-card ${ok ? 'low' : 'high'}`}>
      <strong>{title}</strong>
      <RiskBadge level={ok ? 'low' : 'high'} compact />
      <p>{ok ? positive : negative}</p>
    </section>
  );
}
