import { useEffect, useMemo, useState } from 'react';
import {
  analyzeCode,
  checkDoc,
  checkLink,
  decodeQrImage,
  detectImage,
  fetchHistory,
  processPrivacyImage,
  toAssetUrl
} from './api/privacyApi';
import { RiskBadge } from './components/RiskComponents';
import CodePage from './pages/CodePage';
import DocPage from './pages/DocPage';
import LinkPage from './pages/LinkPage';
import PrivacyPage from './pages/PrivacyPage';
import type {
  CodeAnalyzeResponse,
  DetectResult,
  DocCheckResponse,
  HistoryRecord,
  LinkCheckResponse,
  MaskType,
  RiskLevel
} from './types/privacy';
import { calculateOverallScore } from './utils/scoring';

type Page = 'home' | 'privacy' | 'code' | 'link' | 'doc';
type ToolPage = Exclude<Page, 'home'>;

const modules: Array<{
  id: ToolPage;
  title: string;
  subtitle: string;
  detail: string;
  accent: string;
}> = [
  {
    id: 'privacy',
    title: 'Privacy Sentinel 隐私哨兵',
    subtitle: '图片隐私检测与打码',
    detail: '识别手机号、证件号、银行卡号、邮箱、地址和二维码等敏感区域，生成安全分享版本。',
    accent: 'blue'
  },
  {
    id: 'code',
    title: 'Code Guardian 代码卫士',
    subtitle: '提交代码前的安全体检',
    detail: '检测硬编码密钥、SQL 注入、命令执行、路径穿越、弱加密、敏感日志、危险配置和 XSS 风险。',
    accent: 'red'
  },
  {
    id: 'link',
    title: 'Link Guard 链接卫士',
    subtitle: '链接与二维码安全体检',
    detail: '从协议、域名、参数、关键词、随机 token 和来源场景生成完整链接安全报告。',
    accent: 'teal'
  },
  {
    id: 'doc',
    title: 'Doc Shield 提交护盾',
    subtitle: '材料提交前检查',
    detail: '检查提交要求、材料完整性、格式规范、隐私风险和提交建议。',
    accent: 'amber'
  }
];

const sampleCode = `import os

api_key = "sk-demo-hardcoded-secret"
name = input("name:")
sql = "SELECT * FROM users WHERE name = '" + name + "'"
os.system("ping " + name)
print("token", api_key)`;

const sampleDocRequirement =
  '课程论文提交要求：请于 2026 年 7 月 10 日 18:00 前提交 PDF 文件，命名规则为 学号-姓名-课程论文。材料需包含封面、摘要、正文、参考文献；正文不少于 3000 字。';

function scoreFromRisk(level: RiskLevel) {
  if (level === 'high') return 48;
  if (level === 'medium') return 74;
  return 92;
}

export default function App() {
  const [page, setPage] = useState<Page>('home');
  const [detectResult, setDetectResult] = useState<DetectResult | null>(null);
  const [processedUrl, setProcessedUrl] = useState('');
  const [history, setHistory] = useState<HistoryRecord[]>([]);
  const [maskType, setMaskType] = useState<MaskType>('black');
  const [loadingDetect, setLoadingDetect] = useState(false);
  const [loadingMask, setLoadingMask] = useState(false);
  const [error, setError] = useState('');

  const [codeText, setCodeText] = useState(sampleCode);
  const [codeLanguage, setCodeLanguage] = useState('auto');
  const [codeFile, setCodeFile] = useState<File | null>(null);
  const [codeResult, setCodeResult] = useState<CodeAnalyzeResponse | null>(null);
  const [loadingCode, setLoadingCode] = useState(false);

  const [url, setUrl] = useState('https://example.com/login?redirect=pay&token=abc123abc123abc123abc123');
  const [linkSource, setLinkSource] = useState('短信');
  const [qrFile, setQrFile] = useState<File | null>(null);
  const [qrMessage, setQrMessage] = useState('');
  const [loadingQr, setLoadingQr] = useState(false);
  const [linkResult, setLinkResult] = useState<LinkCheckResponse | null>(null);
  const [loadingLink, setLoadingLink] = useState(false);

  const [docRequirement, setDocRequirement] = useState(sampleDocRequirement);
  const [docFiles, setDocFiles] = useState<File[]>([]);
  const [docResult, setDocResult] = useState<DocCheckResponse | null>(null);
  const [loadingDoc, setLoadingDoc] = useState(false);

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

  const mergedHistory = history;
  const score = useMemo(
    () =>
      calculateOverallScore(mergedHistory, {
        privacy: detectResult?.score,
        code: codeResult?.score,
        link: linkResult?.score,
        doc: docResult?.score
      }),
    [detectResult, docResult, linkResult, mergedHistory, codeResult]
  );

  const moduleStatus = useMemo(() => {
    const latest = (module: 'privacy' | 'code' | 'link' | 'doc') => history.find((item) => (item.module ?? 'privacy') === module);
    const latestPrivacy = latest('privacy');
    const latestCode = latest('code');
    const latestLink = latest('link');
    const latestDoc = latest('doc');
    return {
      privacy: {
        riskLevel: detectResult?.riskLevel ?? latestPrivacy?.riskLevel ?? ('low' as RiskLevel),
        score: detectResult?.score ?? latestPrivacy?.score ?? (latestPrivacy ? scoreFromRisk(latestPrivacy.riskLevel) : 92),
        status: detectResult ? detectResult.summary : latestPrivacy?.summary ?? '等待图片检测'
      },
      code: {
        riskLevel: codeResult?.riskLevel ?? latestCode?.riskLevel ?? ('low' as RiskLevel),
        score: codeResult?.score ?? latestCode?.score ?? (latestCode ? scoreFromRisk(latestCode.riskLevel) : 92),
        status: codeResult ? `发现 ${codeResult.vulnerabilities.length} 项代码风险` : latestCode?.summary ?? '等待代码检测'
      },
      link: {
        riskLevel: linkResult?.riskLevel ?? latestLink?.riskLevel ?? ('low' as RiskLevel),
        score: linkResult?.score ?? latestLink?.score ?? (latestLink ? scoreFromRisk(latestLink.riskLevel) : 92),
        status: linkResult ? `完成 ${linkResult.checks.length} 项链接体检` : latestLink?.summary ?? '等待链接体检'
      },
      doc: {
        riskLevel: docResult?.riskLevel ?? latestDoc?.riskLevel ?? ('low' as RiskLevel),
        score: docResult?.score ?? latestDoc?.score ?? (latestDoc ? scoreFromRisk(latestDoc.riskLevel) : 92),
        status: docResult?.summary ?? latestDoc?.summary ?? '等待材料检查'
      }
    };
  }, [detectResult, docResult, history, linkResult, codeResult]);

  const riskCounts = useMemo(
    () => ({
      high: mergedHistory.filter((item) => item.riskLevel === 'high').length,
      medium: mergedHistory.filter((item) => item.riskLevel === 'medium').length,
      low: mergedHistory.filter((item) => item.riskLevel === 'low').length
    }),
    [mergedHistory]
  );

  const moduleGlyphs: Record<ToolPage, string> = {
    privacy: '◇',
    code: '</>',
    link: '↗',
    doc: '▤'
  };

  const moduleLabels: Record<ToolPage, string> = {
    privacy: '隐私哨兵',
    code: '代码卫士',
    link: '链接卫士',
    doc: '提交护盾'
  };

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

  async function handleMask(scope: 'high' | 'all' | 'custom', selectedIds: string[] = []) {
    if (!detectResult) return;
    setLoadingMask(true);
    setError('');
    try {
      const result = await processPrivacyImage(detectResult.imageId, maskType, scope, selectedIds);
      setProcessedUrl(toAssetUrl(result.processedImageUrl));
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '打码失败，请稍后重试。');
    } finally {
      setLoadingMask(false);
    }
  }

  async function handleCodeAnalyze() {
    if (codeFile?.name.toLowerCase().endsWith('.zip')) {
      setError('项目级扫描为后续扩展功能，请先上传单个代码文件或粘贴代码。');
      return;
    }
    setLoadingCode(true);
    setError('');
    try {
      const result = await analyzeCode(codeLanguage, codeText, codeFile);
      setCodeResult(result);
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '代码安全检测失败，请稍后重试。');
    } finally {
      setLoadingCode(false);
    }
  }

  async function handleLinkCheck() {
    setLoadingLink(true);
    setError('');
    try {
      const result = await checkLink(url, linkSource);
      setLinkResult(result);
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '链接安全体检失败，请稍后重试。');
    } finally {
      setLoadingLink(false);
    }
  }

  async function handleQrUpload(file: File | null) {
    setQrFile(file);
    setQrMessage('');
    if (!file) return;
    setLoadingQr(true);
    setError('');
    try {
      const result = await decodeQrImage(file);
      setUrl(result.primaryText);
      setLinkSource('二维码');
      setQrMessage(result.message);
    } catch (err) {
      setError(err instanceof Error ? err.message : '二维码解析失败，请换一张更清晰的图片。');
    } finally {
      setLoadingQr(false);
    }
  }

  async function handleDocCheck() {
    setLoadingDoc(true);
    setError('');
    try {
      const result = await checkDoc(docRequirement, docFiles);
      setDocResult(result);
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '材料检查失败，请稍后重试。');
    } finally {
      setLoadingDoc(false);
    }
  }

  function openHistory() {
    setPage('home');
    window.setTimeout(() => document.getElementById('recent-history')?.scrollIntoView({ behavior: 'smooth' }), 0);
  }

  return (
    <main className="app-shell">
      <aside className="side-nav">
        <button className="brand" onClick={() => setPage('home')}>
          <span className="brand-mark">GH</span>
          <strong>GuardianHub</strong>
        </button>
        <div className="side-nav-links">
          <button className={page === 'home' ? 'active' : ''} onClick={() => setPage('home')}>
            <span className="nav-glyph">⌂</span><span>总览</span>
          </button>
          {modules.map((module) => (
            <button aria-label={module.title} className={page === module.id ? 'active' : ''} key={module.id} onClick={() => setPage(module.id)}>
              <span className="nav-glyph">{moduleGlyphs[module.id]}</span>
              <span><strong>{module.title.split(' ')[0]}</strong><small>{moduleLabels[module.id]}</small></span>
            </button>
          ))}
          <div className="nav-separator" />
          <button onClick={openHistory}><span className="nav-glyph">◷</span><span>历史记录</span></button>
        </div>
        <div className="local-promise">
          <strong>本地防护 · 安心可控</strong>
          <p>✓ 本地可解释规则检测</p>
          <p>✓ 材料不出本地设备</p>
          <p>✓ 不调用第三方模型 API</p>
        </div>
        <small className="version-dot">● GuardianHub v0.1.0</small>
      </aside>

      <section className="app-main">
        <header className="top-nav">
          <div>
            <p>GuardianHub 安全中心</p>
            <strong>{page === 'home' ? '面向高校场景的本地数字安全防护平台' : modules.find((item) => item.id === page)?.title}</strong>
          </div>
          <div className="top-status"><span>◆</span> Local-Only / 本地处理</div>
        </header>

        <div className="workspace">
          {error && <div className="error-bar">{error}</div>}

          {page === 'home' && (
            <div className="home-dashboard">
              <h1 className="sr-only">安全中心</h1>
              <section className="overview-grid">
                <article className="card overview-score">
                  <div className="overview-title"><strong>整体安全评分</strong><span title="由当前会话与历史检测综合计算">i</span></div>
                  <div className="score-overview-body">
                    <div><b>{score}</b><span>/100</span><p>● {score >= 85 ? '安全状态良好' : score >= 65 ? '存在待复核风险' : '建议优先处理风险'}</p></div>
                    <div className="score-gauge" style={{ '--score': `${score * 3.6}deg` } as React.CSSProperties}><span>✓</span></div>
                  </div>
                </article>
                <article className="card risk-overview">
                  <div className="overview-title"><strong>风险总览</strong><span title="来自最近检测历史">i</span></div>
                  <div className="risk-counts">
                    <div className="high"><span>高风险</span><b>{riskCounts.high}</b></div>
                    <div className="medium"><span>中风险</span><b>{riskCounts.medium}</b></div>
                    <div className="low"><span>低风险</span><b>{riskCounts.low}</b></div>
                  </div>
                </article>
                <article className="card scene-overview">
                  <div className="overview-title"><strong>场景速览</strong><span title="打开现有检测模块">i</span></div>
                  <div className="scene-links">
                    {modules.map((module) => <button key={module.id} className={module.accent} onClick={() => setPage(module.id)}><b>{moduleGlyphs[module.id]}</b><span>{module.subtitle.replace('与打码', '').replace('安全体检', '体检').replace('提交前', '')}</span></button>)}
                  </div>
                </article>
              </section>

              <div className="dashboard-content">
                <section className="module-panel-grid">
                  {modules.map((module) => {
                    const status = moduleStatus[module.id];
                    return (
                      <article className={`card dashboard-module ${module.accent}`} key={module.id}>
                        <div className="dashboard-module-head">
                          <div><span className="module-icon">{moduleGlyphs[module.id]}</span><h2>{module.title}</h2></div>
                          <RiskBadge level={status.riskLevel} compact />
                        </div>
                        <div className="dashboard-module-body">
                          <div>
                            <p className="module-subtitle">{module.subtitle}</p>
                            <p>{module.detail}</p>
                            <span className="module-status">● {status.status}</span>
                          </div>
                          <div className="mini-score"><small>最近评分</small><strong>{status.score}</strong><span>/ 100</span></div>
                        </div>
                        <div className="dashboard-module-footer">
                          <span>本地规则检测</span>
                          <button onClick={() => setPage(module.id)}>开始检测 <b>→</b></button>
                        </div>
                      </article>
                    );
                  })}
                </section>

                <aside className="dashboard-aside">
                  <section className="card recent-card" id="recent-history">
                    <div className="aside-title"><h2>最近扫描结果</h2><span>{mergedHistory.length} 条记录</span></div>
                    {mergedHistory.length === 0 ? <div className="empty-history"><span>◷</span><strong>暂无检测记录</strong><p>完成任一模块检测后，结果会显示在这里。</p></div> : (
                      <div className="compact-history">
                        {mergedHistory.slice(0, 6).map((record) => {
                          const recordModule = (record.module ?? 'privacy') as ToolPage;
                          return <article key={record.recordId || `${record.imageId}-${record.createdAt}`}><span className="history-glyph">{moduleGlyphs[recordModule]}</span><div><strong>{record.summary}</strong><small>{moduleLabels[recordModule]} · {new Date(record.createdAt).toLocaleString('zh-CN', { hour12: false })}</small></div><RiskBadge level={record.riskLevel} compact /></article>;
                        })}
                      </div>
                    )}
                  </section>
                  <section className="card distribution-card">
                    <div className="aside-title"><h2>风险分布</h2><span>共 {mergedHistory.length} 项</span></div>
                    <div className="distribution-body">
                      <div className="risk-donut" style={{ '--high': riskCounts.high, '--medium': riskCounts.medium, '--total': Math.max(mergedHistory.length, 1) } as React.CSSProperties}><span><b>{mergedHistory.length}</b><small>总风险</small></span></div>
                      <div className="distribution-legend"><p><i className="high" /> high <b>{riskCounts.high}</b></p><p><i className="medium" /> medium <b>{riskCounts.medium}</b></p><p><i className="low" /> low <b>{riskCounts.low}</b></p></div>
                    </div>
                  </section>
                  <section className="card privacy-note"><strong>◆ 安全与隐私承诺</strong><p>检测基于本地可解释规则完成，上传材料不会发送至第三方模型服务。</p></section>
                </aside>
              </div>
              <footer className="rules-footer"><span>◇ 检测基于本地可解释规则引擎</span><span>当前历史记录：{mergedHistory.length} 条</span></footer>
            </div>
          )}

      {page === 'privacy' && (
        <PrivacyPage
          result={detectResult}
          processedUrl={processedUrl}
          loadingDetect={loadingDetect}
          loadingMask={loadingMask}
          maskType={maskType}
          onBack={() => setPage('home')}
          onDetect={handleDetect}
          onMaskTypeChange={setMaskType}
          onProcess={handleMask}
        />
      )}

      {page === 'code' && (
        <CodePage
          text={codeText}
          language={codeLanguage}
          file={codeFile}
          result={codeResult}
          loading={loadingCode}
          onBack={() => setPage('home')}
          onTextChange={setCodeText}
          onLanguageChange={setCodeLanguage}
          onFileChange={setCodeFile}
          onAnalyze={handleCodeAnalyze}
        />
      )}

      {page === 'link' && (
        <LinkPage
          url={url}
          source={linkSource}
          qrFile={qrFile}
          qrMessage={qrMessage}
          result={linkResult}
          loading={loadingLink}
          loadingQr={loadingQr}
          onBack={() => setPage('home')}
          onUrlChange={setUrl}
          onSourceChange={setLinkSource}
          onQrUpload={handleQrUpload}
          onCheck={handleLinkCheck}
        />
      )}

      {page === 'doc' && (
        <DocPage
          requirement={docRequirement}
          files={docFiles}
          result={docResult}
          loading={loadingDoc}
          onBack={() => setPage('home')}
          onRequirementChange={setDocRequirement}
          onFilesChange={setDocFiles}
          onCheck={handleDocCheck}
        />
      )}
        </div>
      </section>
    </main>
  );
}
