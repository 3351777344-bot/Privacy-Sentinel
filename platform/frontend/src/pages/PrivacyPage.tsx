import { toAssetUrl } from '../api/privacyApi';
import ImagePreview from '../components/ImagePreview';
import MaskControl from '../components/MaskControl';
import { ImageCompareCard, PageHero } from '../components/PageComponents';
import PrivacyItemList from '../components/PrivacyItemList';
import { RiskReport } from '../components/RiskComponents';
import RiskSummary from '../components/RiskSummary';
import UploadPanel from '../components/UploadPanel';
import type { DetectResult, MaskType, TextFinding } from '../types/privacy';

interface PrivacyPageProps {
  result: DetectResult | null;
  processedUrl: string;
  loadingDetect: boolean;
  loadingMask: boolean;
  maskType: MaskType;
  onBack: () => void;
  onDetect: (file: File) => Promise<void>;
  onMaskTypeChange: (type: MaskType) => void;
  onProcess: (scope: 'high' | 'all' | 'custom', selectedIds?: string[]) => Promise<void>;
}

function evidenceFromResult(result: DetectResult | null): TextFinding[] {
  return (
    result?.items.map((item) => ({
      label: item.label,
      evidence: `${item.text}：${item.suggestion}`,
      riskLevel: item.riskLevel
    })) ?? []
  );
}

export default function PrivacyPage(props: PrivacyPageProps) {
  const { result, processedUrl, loadingDetect, loadingMask, maskType } = props;
  return (
    <>
      <PageHero
        eyebrow="Privacy Sentinel"
        title="Privacy Sentinel 隐私哨兵"
        copy="图片分享前先识别敏感区域并打码，保留原有上传、检测、标注、处理和历史记录能力。"
        onBack={props.onBack}
      />
      <div className="workflow-grid">
        <div className="left-column">
          <UploadPanel loading={loadingDetect} onDetect={props.onDetect} />
          <ImagePreview
            imageUrl={toAssetUrl(result?.originalImageUrl)}
            items={result?.items}
            title="原图与隐私检测框"
            emptyText="上传图片后，这里会展示原图和标注出的隐私检测框。"
          />
        </div>
        <div className="right-column">
          <RiskSummary result={result} />
          <PrivacyItemList items={result?.items ?? []} />
          <MaskControl
            disabled={!result}
            loading={loadingMask}
            maskType={maskType}
            items={result?.items ?? []}
            onMaskTypeChange={props.onMaskTypeChange}
            onProcess={props.onProcess}
          />
        </div>
      </div>

      <div className="bottom-grid">
        <section className="card safe-preview">
          <div className="section-title">
            <span>06</span>
            <div>
              <h3>原图 / 处理后对比</h3>
              <p>打码完成后对照检查，确认无误再对外分享。</p>
            </div>
          </div>
          {processedUrl && result ? (
            <div className="comparison-grid">
              <ImageCompareCard title="原图" imageUrl={toAssetUrl(result.originalImageUrl)} />
              <ImageCompareCard title="处理后" imageUrl={processedUrl} />
            </div>
          ) : (
            <div className="safe-empty">
              <strong>等待打码处理</strong>
              <p className="muted">完成检测并选择处理策略后，这里会展示原图与安全版本对比。</p>
            </div>
          )}
        </section>
        <RiskReport
          title="分享前风险报告"
          riskLevel={result?.riskLevel}
          score={result?.score}
          summary={result?.summary}
          evidence={evidenceFromResult(result)}
          suggestions={[
            '优先处理高风险区域，再复核中风险区域是否与分享目的有关。',
            '如果图片包含二维码、证件、住址或联系方式，建议处理后再分享。',
            '正式发布前查看处理后预览，避免误遮挡重要内容或遗漏隐私。'
          ]}
        />
      </div>
    </>
  );
}
