import type { MaskType, PrivacyItem } from '../types/privacy';

interface MaskControlProps {
  disabled: boolean;
  loading: boolean;
  maskType: MaskType;
  items: PrivacyItem[];
  onMaskTypeChange: (type: MaskType) => void;
  onProcess: (scope: 'high' | 'all') => Promise<void>;
}

const maskOptions: Array<{ type: MaskType; label: string; desc: string }> = [
  { type: 'black', label: '黑条遮盖', desc: '适合手机号、地址等明确文本' },
  { type: 'blur', label: '模糊处理', desc: '适合头像、昵称等局部区域' },
  { type: 'mosaic', label: '马赛克', desc: '适合二维码、证件局部区域' }
];

export default function MaskControl({
  disabled,
  loading,
  maskType,
  items,
  onMaskTypeChange,
  onProcess
}: MaskControlProps) {
  const highCount = items.filter((item) => item.riskLevel === 'high').length;

  return (
    <section className="card">
      <div className="section-title">
        <span>05</span>
        <div>
          <h3>打码控制</h3>
          <p>选择处理方式，一键生成可以再次确认的安全预览图。</p>
        </div>
      </div>
      <div className="mask-options">
        {maskOptions.map((option) => (
          <button
            className={maskType === option.type ? 'selected' : ''}
            key={option.type}
            onClick={() => onMaskTypeChange(option.type)}
          >
            <strong>{option.label}</strong>
            <span>{option.desc}</span>
          </button>
        ))}
      </div>
      <div className="action-row">
        <button disabled={disabled || loading || highCount === 0} onClick={() => onProcess('high')}>
          {loading ? '处理中...' : `一键处理高风险 (${highCount})`}
        </button>
        <button disabled={disabled || loading || items.length === 0} onClick={() => onProcess('all')}>
          处理全部检测项
        </button>
      </div>
    </section>
  );
}
