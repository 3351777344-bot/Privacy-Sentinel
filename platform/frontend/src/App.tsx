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
import { HistoryTimeline, RiskBadge, ScoreCard } from './components/RiskComponents';
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

  return (
    <main className="app-shell">
      <nav className="top-nav">
        <button className="brand" onClick={() => setPage('home')}>
          <span>GH</span>
          <strong>GuardianHub</strong>
        </button>
        <div className="nav-actions">
          <button className={page === 'home' ? 'active' : ''} onClick={() => setPage('home')}>
            安全中心
          </button>
          {modules.map((module) => (
            <button className={page === module.id ? 'active' : ''} key={module.id} onClick={() => setPage(module.id)}>
              {module.title}
            </button>
          ))}
        </div>
      </nav>

      {error && <div className="error-bar">{error}</div>}

      {page === 'home' && (
        <>
          <header className="app-header">
            <div className="hero-copy">
              <p className="eyebrow">GuardianHub / AI Digital Safety Platform</p>
              <h1>安全中心</h1>
              <h2>面向高校场景的 AI 数字安全防护平台</h2>
              <p className="header-copy">
                GuardianHub 将图片隐私检测、代码安全检测、链接安全体检和材料提交检查整合到同一平台。当前版本基于本地规则、正则和关键词运行，适合比赛演示与离线 Demo。
              </p>
            </div>
            <ScoreCard score={score} title="今日安全评分" />
          </header>

          <section className="intro card">
            <div>
              <h3>从提交前、打开前、分享前建立统一防护</h3>
              <p>
                平台统一输出 high / medium / low 风险等级、0-100 安全评分、风险证据和建议操作，让学生项目、课程材料和日常链接都能先体检再处理。
              </p>
            </div>
            <div className="intro-tags">
              <span>图片隐私检测</span>
              <span>代码安全检测</span>
              <span>链接安全体检</span>
              <span>材料提交检查</span>
            </div>
          </section>

          <section className="module-grid">
            {modules.map((module) => {
              const status = moduleStatus[module.id];
              return (
                <article className={`module-card ${module.accent}`} key={module.id}>
                  <div className="module-card-top">
                    <span>{status.status}</span>
                    <RiskBadge level={status.riskLevel} compact />
                  </div>
                  <div>
                    <h3>{module.title}</h3>
                    <p>{module.subtitle}</p>
                  </div>
                  <p>{module.detail}</p>
                  <div className="module-score">
                    <small>最近安全评分</small>
                    <strong>{status.score}</strong>
                  </div>
                  <button onClick={() => setPage(module.id)}>进入模块</button>
                </article>
              );
            })}
          </section>

          <div className="dashboard-grid">
            <section className="card posture-card">
              <div className="section-title">
                <span>S</span>
                <div>
                  <h3>平台安全态势</h3>
                  <p>结合最近检测记录与当前会话报告生成今日评分。</p>
                </div>
              </div>
              <div className="score-meter">
                <b>{score}</b>
                <span>Score</span>
              </div>
              <div className="posture-row">
                <span>高风险记录</span>
                <strong>{mergedHistory.filter((item) => item.riskLevel === 'high').length}</strong>
              </div>
              <div className="posture-row">
                <span>最近检测</span>
                <strong>{mergedHistory.length}</strong>
              </div>
            </section>
            <HistoryTimeline records={mergedHistory} />
          </div>
        </>
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
    </main>
  );
}
