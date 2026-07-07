import { useMemo, useState } from 'react';
import type { MaskType, PrivacyItem } from '../types/privacy';
import { RiskBadge } from './RiskComponents';

interface MaskControlProps {
  disabled: boolean;
  loading: boolean;
  maskType: MaskType;
  items: PrivacyItem[];
  onMaskTypeChange: (type: MaskType) => void;
  onProcess: (scope: 'high' | 'all' | 'custom', selectedIds?: string[]) => Promise<void>;
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
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const highCount = items.filter((item) => item.riskLevel === 'high').length;
  const selectedCount = selectedIds.length;

  const selectableItems = useMemo(
    () =>
      items.map((item) => ({
        ...item,
        checked: selectedIds.includes(item.id)
      })),
    [items, selectedIds]
  );

  function toggleItem(id: string) {
    setSelectedIds((current) => (current.includes(id) ? current.filter((itemId) => itemId !== id) : [...current, id]));
  }

  return (
    <section className="card">
      <div className="section-title">
        <span>05</span>
        <div>
          <h3>处理策略</h3>
          <p>选择打码方式和处理范围，生成可复核的安全分享版本。</p>
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

      <div className="strategy-grid">
        <button disabled={disabled || loading || highCount === 0} onClick={() => onProcess('high')}>
          <strong>只处理高风险</strong>
          <span>{highCount} 项</span>
        </button>
        <button disabled={disabled || loading || items.length === 0} onClick={() => onProcess('all')}>
          <strong>处理全部</strong>
          <span>{items.length} 项</span>
        </button>
        <button disabled={disabled || loading || selectedCount === 0} onClick={() => onProcess('custom', selectedIds)}>
          <strong>自定义选择</strong>
          <span>{selectedCount} 项</span>
        </button>
      </div>

      {items.length > 0 && (
        <div className="custom-mask-list">
          {selectableItems.map((item) => (
            <label className="custom-mask-item" key={item.id}>
              <input checked={item.checked} type="checkbox" onChange={() => toggleItem(item.id)} />
              <span>
                <strong>{item.label}</strong>
                <small>{item.text}</small>
              </span>
              <RiskBadge level={item.riskLevel} compact />
            </label>
          ))}
        </div>
      )}
    </section>
  );
}
