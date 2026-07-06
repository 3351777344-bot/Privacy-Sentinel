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
  { type: 'black', label: '黑条', desc: '适合手机号、地址等明确文本' },
  { type: 'blur', label: '模糊', desc: '适合头像、昵称等局部区域' },
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
          <h3>一键打码</h3>
          <p>打码由后端真实生成，当前检测数据仍为 mock。</p>
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
          {loading ? '处理中...' : `一键处理高风险信息 (${highCount})`}
        </button>
        <button disabled={disabled || loading || items.length === 0} onClick={() => onProcess('all')}>
          处理全部检测信息
        </button>
      </div>
    </section>
  );
}
