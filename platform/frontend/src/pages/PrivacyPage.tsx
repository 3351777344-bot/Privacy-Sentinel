import { toAssetUrl } from '../api/privacyApi';
import ImagePreview from '../components/ImagePreview';
import MaskControl from '../components/MaskControl';
import { ImageCompareCard, PageHero } from '../components/PageComponents';
import PrivacyItemList from '../components/PrivacyItemList';
import RiskSummary from '../components/RiskSummary';
import UploadPanel from '../components/UploadPanel';
import type { DetectResult, MaskType, ProcessingMode } from '../types/privacy';

interface PrivacyPageProps {
  result: DetectResult | null;
  processedUrl: string;
  loadingDetect: boolean;
  loadingMask: boolean;
  maskType: MaskType;
  processingMode: ProcessingMode;
  onBack: () => void;
  onDetect: (file: File) => Promise<void>;
  onProcessingModeChange: (mode: ProcessingMode) => void;
  onMaskTypeChange: (type: MaskType) => void;
  onProcess: (scope: 'high' | 'all' | 'custom', selectedIds?: string[]) => Promise<void>;
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
          <UploadPanel
            loading={loadingDetect}
            onDetect={props.onDetect}
            processingMode={props.processingMode}
            onProcessingModeChange={props.onProcessingModeChange}
          />
          <ImagePreview
            imageUrl={toAssetUrl(result?.originalImageUrl)}
            items={result?.items}
            title="原图与隐私检测框"
            emptyText="上传图片后，这里会展示原图和标注出的隐私检测框。"
          />
        </div>
        <div className="right-column">
          {processedUrl && result && (
            <section className="card safe-preview">
              <div className="section-title">
                <span>05</span>
                <div>
                  <h3>原图 / 处理后对比</h3>
                  <p>打码完成后对照检查，确认无误再对外分享。</p>
                </div>
              </div>
              <div className="comparison-grid">
                <ImageCompareCard title="原图" imageUrl={toAssetUrl(result.originalImageUrl)} />
                <ImageCompareCard title="处理后" imageUrl={processedUrl} />
              </div>
              <a className="primary-button download-btn" href={toAssetUrl(processedUrl)} download>
                导出处理后图片
              </a>
            </section>
          )}
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
    </>
  );
}
