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
            面向截图、聊天记录、快递单、订单页面等图片分享场景，AI 在分享前主动识别隐私风险，
            并一键生成安全分享版图片。当前为 PC Web 原型，复赛阶段可迁移到 HarmonyOS 多端。
          </p>
        </div>
        <div className="intro-tags">
          <span>主动检测</span>
          <span>风险分级</span>
          <span>真实打码</span>
          <span>安全预览</span>
        </div>
      </section>

      {error && <div className="error-bar">{error}</div>}

      <div className="main-grid">
        <div className="left-column">
          <UploadPanel loading={loadingDetect} onDetect={handleDetect} />
          <ImagePreview
            imageUrl={toAssetUrl(detectResult?.originalImageUrl)}
            items={detectResult?.items}
            title="检测结果标注"
            emptyText="上传图片后，这里会显示原图和 AI 模拟标注区域。"
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
              <h3>安全预览</h3>
              <p>确认高风险信息已处理后，再进入分享流程。</p>
            </div>
          </div>
          {processedUrl ? (
            <div className="safe-content">
              <img src={processedUrl} alt="处理后的安全图片" />
              <div>
                <b>当前安全等级：可分享前复核</b>
                <p>已处理高风险隐私信息，当前图片风险已降低，建议确认后再分享。</p>
              </div>
            </div>
          ) : (
            <p className="muted">完成打码后，这里会展示安全分享版图片。</p>
          )}
        </section>
        <HistoryList records={history} />
      </div>
    </main>
  );
}
