import { useEffect, useState } from 'react';
import { detectImage, fetchHistory, maskImage, toAssetUrl } from './api/privacyApi';
import Header from './components/Header';
import HistoryList from './components/HistoryList';
import ImagePreview from './components/ImagePreview';
import MaskControl from './components/MaskControl';
import PrivacyItemList from './components/PrivacyItemList';
import RiskSummary from './components/RiskSummary';
import UploadPanel from './components/UploadPanel';
import type { DetectResult, HistoryRecord, MaskType } from './types/privacy';

export default function App() {
  const [detectResult, setDetectResult] = useState<DetectResult | null>(null);
  const [processedUrl, setProcessedUrl] = useState('');
  const [history, setHistory] = useState<HistoryRecord[]>([]);
  const [maskType, setMaskType] = useState<MaskType>('black');
  const [loadingDetect, setLoadingDetect] = useState(false);
  const [loadingMask, setLoadingMask] = useState(false);
  const [error, setError] = useState('');

  async function refreshHistory() {
    try {
      setHistory(await fetchHistory());
    } catch {
      setHistory([]);
    }
  }

  useEffect(() => {
    refreshHistory();
  }, []);

  async function handleDetect(file: File) {
    setLoadingDetect(true);
    setError('');
    setProcessedUrl('');
    try {
      const result = await detectImage(file);
      setDetectResult(result);
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '检测失败，请稍后重试。');
    } finally {
      setLoadingDetect(false);
    }
  }

  async function handleMask(scope: 'high' | 'all') {
    if (!detectResult) return;
    setLoadingMask(true);
    setError('');
    const selectedItems = detectResult.items
      .filter((item) => scope === 'all' || item.riskLevel === 'high')
      .map((item) => item.box);

    try {
      const result = await maskImage(detectResult.imageId, maskType, selectedItems);
      setProcessedUrl(toAssetUrl(result.processedImageUrl));
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '打码失败，请稍后重试。');
    } finally {
      setLoadingMask(false);
    }
  }

  return (
    <main className="app-shell">
      <Header />

      <section className="intro card">
        <div>
          <h3>项目定位</h3>
          <p>
            Privacy Sentinel 用 AI 在图片分享前进行隐私巡检，识别手机号、地址、二维码、头像等敏感区域，
            并通过风险分级和一键打码帮助用户生成更安全的分享图片。
          </p>
        </div>
        <div className="intro-tags">
          <span>主动检测</span>
          <span>风险分级</span>
          <span>隐私框标注</span>
          <span>一键打码</span>
          <span>安全预览</span>
        </div>
      </section>

      {error && <div className="error-bar">{error}</div>}

      <div className="workflow-grid">
        <div className="left-column">
          <UploadPanel loading={loadingDetect} onDetect={handleDetect} />
          <ImagePreview
            imageUrl={toAssetUrl(detectResult?.originalImageUrl)}
            items={detectResult?.items}
            title="原图与隐私检测框"
            emptyText="上传图片后，这里会展示原图和 AI 标注出的隐私检测框。"
          />
        </div>
        <div className="right-column">
          <RiskSummary result={detectResult} />
          <PrivacyItemList items={detectResult?.items ?? []} />
          <MaskControl
            disabled={!detectResult}
            loading={loadingMask}
            maskType={maskType}
            items={detectResult?.items ?? []}
            onMaskTypeChange={setMaskType}
            onProcess={handleMask}
          />
        </div>
      </div>

      <div className="bottom-grid">
        <section className="card safe-preview">
          <div className="section-title">
            <span>06</span>
            <div>
              <h3>处理后图片</h3>
              <p>打码完成后在这里查看安全分享版本，确认无误后再对外发送。</p>
            </div>
          </div>
          {processedUrl ? (
            <div className="safe-content">
              <img src={processedUrl} alt="处理后的安全图片" />
              <div className="safe-verdict">
                <span>安全预览</span>
                <b>已生成可分享前复核版本</b>
                <p>高风险隐私区域已按当前策略处理。建议在正式分享前进行最后一次人工确认。</p>
              </div>
            </div>
          ) : (
            <div className="safe-empty">
              <strong>等待打码处理</strong>
              <p className="muted">完成检测并点击一键打码后，这里会展示处理后的图片。</p>
            </div>
          )}
        </section>
        <HistoryList records={history} />
      </div>
    </main>
  );
}
