import { useEffect, useMemo, useState } from 'react';
import {
  analyzeCode,
  checkDoc,
  checkLink,
  detectImage,
  fetchHistory,
  processPrivacyImage,
  saveHistory,
  toAssetUrl
} from './api/privacyApi';
import ImagePreview from './components/ImagePreview';
import MaskControl from './components/MaskControl';
import PrivacyItemList from './components/PrivacyItemList';
import RiskSummary from './components/RiskSummary';
import {
  EvidenceList,
  HistoryTimeline,
  RiskBadge,
  RiskReport,
  ScoreCard,
  SuggestionList
} from './components/RiskComponents';
import UploadPanel from './components/UploadPanel';
import type {
  CodeAnalyzeResponse,
  DetectResult,
  DocCheckResponse,
  HistoryRecord,
  LinkCheckResponse,
  MaskType,
  RiskLevel,
  TextFinding
} from './types/privacy';

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
    detail: '识别手机号、地址、二维码、头像、昵称等敏感区域，生成安全分享版本。',
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

const languageOptions = [
  { value: 'auto', label: '自动识别' },
  { value: 'python', label: 'Python' },
  { value: 'java', label: 'Java' },
  { value: 'javascript', label: 'JavaScript' },
  { value: 'typescript', label: 'TypeScript' },
  { value: 'sql', label: 'SQL' },
  { value: 'other', label: 'Other' }
];

const sourceOptions = ['短信', '群聊', '邮件', '二维码', '二手交易', '客服', '学校通知', '陌生人私信', '其他'];

function scoreFromRisk(level: RiskLevel) {
  if (level === 'high') return 48;
  if (level === 'medium') return 74;
  return 92;
}

function privacyScore(result?: DetectResult | null) {
  return result?.score;
}

function overallScore(records: HistoryRecord[], latestScores: Array<number | undefined>) {
  const activeScores = latestScores.filter((score): score is number => typeof score === 'number');
  const persistedScores = ['privacy', 'code', 'link', 'doc']
    .map((module) => records.find((record) => (record.module ?? 'privacy') === module)?.score)
    .filter((score): score is number => typeof score === 'number');
  const scores = activeScores.length ? activeScores : persistedScores;
  return scores.length ? Math.round(scores.reduce((total, score) => total + score, 0) / scores.length) : 96;
}

function evidenceFromPrivacy(result?: DetectResult | null): TextFinding[] {
  return (
    result?.items.map((item) => ({
      label: item.label,
      evidence: `${item.text}：${item.suggestion}`,
      riskLevel: item.riskLevel
    })) ?? []
  );
}

function evidenceFromCode(result?: CodeAnalyzeResponse | null): TextFinding[] {
  return (
    result?.vulnerabilities.map((item) => ({
      label: item.line ? `${item.title} / 第 ${item.line} 行` : item.title,
      evidence: `${item.snippet || '未截取到代码片段'}。${item.reason}`,
      riskLevel: item.riskLevel
    })) ?? []
  );
}

function evidenceFromLink(result?: LinkCheckResponse | null): TextFinding[] {
  return (
    result?.checks.map((item) => ({
      label: `${item.label} / ${item.status}`,
      evidence: item.message,
      riskLevel: item.riskLevel
    })) ?? []
  );
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
      overallScore(mergedHistory, [
        privacyScore(detectResult),
        codeResult?.score,
        linkResult?.score,
        docResult?.score
      ]),
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
        score: privacyScore(detectResult) ?? latestPrivacy?.score ?? (latestPrivacy ? scoreFromRisk(latestPrivacy.riskLevel) : 92),
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
      await saveHistory('code', result.riskLevel, result.score, result.summary);
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
      await saveHistory('link', result.riskLevel, result.score, result.summary);
      await refreshHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : '链接安全体检失败，请稍后重试。');
    } finally {
      setLoadingLink(false);
    }
  }

  async function handleDocCheck() {
    setLoadingDoc(true);
    setError('');
    try {
      const result = await checkDoc(docRequirement, docFiles);
      setDocResult(result);
      await saveHistory('doc', result.riskLevel, result.score, result.summary);
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
        <>
          <PageHero
            eyebrow="Privacy Sentinel"
            title="Privacy Sentinel 隐私哨兵"
            copy="图片分享前先识别敏感区域并打码，保留原有上传、检测、标注、处理和历史记录能力。"
            onBack={() => setPage('home')}
          />
          <div className="workflow-grid">
            <div className="left-column">
              <UploadPanel loading={loadingDetect} onDetect={handleDetect} />
              <ImagePreview
                imageUrl={toAssetUrl(detectResult?.originalImageUrl)}
                items={detectResult?.items}
                title="原图与隐私检测框"
                emptyText="上传图片后，这里会展示原图和标注出的隐私检测框。"
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
                  <h3>原图 / 处理后对比</h3>
                  <p>打码完成后对照检查，确认无误再对外分享。</p>
                </div>
              </div>
              {processedUrl && detectResult ? (
                <div className="comparison-grid">
                  <ImageCompareCard title="原图" imageUrl={toAssetUrl(detectResult.originalImageUrl)} />
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
              riskLevel={detectResult?.riskLevel}
              score={privacyScore(detectResult)}
              summary={detectResult?.summary}
              evidence={evidenceFromPrivacy(detectResult)}
              suggestions={[
                '优先处理高风险区域，再复核中风险区域是否与分享目的有关。',
                '如果图片包含二维码、证件、住址或联系方式，建议处理后再分享。',
                '正式发布前查看处理后预览，避免误遮挡重要内容或遗漏隐私。'
              ]}
            />
          </div>
        </>
      )}

      {page === 'code' && (
        <>
          <PageHero
            eyebrow="Code Guardian"
            title="Code Guardian 代码卫士"
            copy="提交代码之前，先检查潜在安全风险。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>代码输入区</h3>
                  <p>粘贴代码或上传单个代码文件，当前不强制支持 zip 项目扫描。</p>
                </div>
              </div>
              <label className="field-label">
                代码语言
                <select value={codeLanguage} onChange={(event) => setCodeLanguage(event.target.value)}>
                  {languageOptions.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </label>
              {codeResult && (
                <p className="muted">
                  识别语言：{codeResult.language}（来源：{codeResult.languageSource}，置信度：
                  {Math.round(codeResult.languageConfidence * 100)}%）
                </p>
              )}
              <textarea value={codeText} onChange={(event) => setCodeText(event.target.value)} />
              <label className="upload-box doc-upload-box">
                <input
                  type="file"
                  accept=".py,.java,.js,.ts,.sql,.txt,.zip"
                  onChange={(event) => setCodeFile(event.target.files?.[0] ?? null)}
                />
                <span className="upload-icon">+</span>
                <strong>{codeFile ? codeFile.name : '选择单个代码文件'}</strong>
                <span>.py / .java / .js / .ts / .sql / .txt；zip 为后续扩展功能</span>
              </label>
              {codeFile?.name.toLowerCase().endsWith('.zip') && (
                <p className="muted">当前版本暂不解析 zip 项目包，请上传单个代码文件或直接粘贴核心代码片段。</p>
              )}
              <button
                className="primary-button"
                disabled={loadingCode || (!codeText.trim() && !codeFile)}
                onClick={handleCodeAnalyze}
              >
                {loadingCode ? '检测中...' : '开始代码安全检测'}
              </button>
            </section>
            <div className="report-stack">
              <RiskReport
                title="代码安全体检报告"
                riskLevel={codeResult?.riskLevel}
                score={codeResult?.score}
                summary={codeResult?.summary}
                evidence={evidenceFromCode(codeResult)}
                suggestions={codeResult?.suggestions}
              />
              {codeResult && (
                <DecisionCard
                  title="是否建议直接提交代码"
                  ok={codeResult.shouldSubmit}
                  positive="可以提交"
                  negative={codeResult.riskLevel === 'high' ? '不建议提交' : '建议修复后提交'}
                />
              )}
            </div>
          </div>
        </>
      )}

      {page === 'link' && (
        <>
          <PageHero
            eyebrow="Link Guard"
            title="Link Guard 链接卫士"
            copy="打开链接之前，先做一次安全体检。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>链接安全体检</h3>
                  <p>输入 URL、短链接、二维码解析出的内容或链接来源说明。</p>
                </div>
              </div>
              <input value={url} onChange={(event) => setUrl(event.target.value)} placeholder="https://example.com" />
              <label className="field-label">
                链接来源
                <select value={linkSource} onChange={(event) => setLinkSource(event.target.value)}>
                  {sourceOptions.map((source) => (
                    <option key={source} value={source}>
                      {source}
                    </option>
                  ))}
                </select>
              </label>
              <label className="upload-box doc-upload-box">
                <input type="file" accept="image/*" onChange={(event) => setQrFile(event.target.files?.[0] ?? null)} />
                <span className="upload-icon">+</span>
                <strong>{qrFile ? qrFile.name : '二维码图片占位上传'}</strong>
                <span>当前版本暂不解析二维码图片，请手动输入二维码解析出的链接。</span>
              </label>
              <button className="primary-button" disabled={loadingLink || !url.trim()} onClick={handleLinkCheck}>
                {loadingLink ? '体检中...' : '开始链接安全体检'}
              </button>
            </section>
            <div className="report-stack">
              <RiskReport
                title="链接安全体检报告"
                riskLevel={linkResult?.riskLevel}
                score={linkResult?.score}
                summary={linkResult?.summary}
                evidence={evidenceFromLink(linkResult)}
                suggestions={linkResult?.suggestions}
              />
              {linkResult && (
                <>
                  <section className="card detail-card">
                    <div className="section-title">
                      <span>P</span>
                      <div>
                        <h3>可疑参数与来源风险</h3>
                        <p>{linkResult.normalizedUrl}</p>
                      </div>
                    </div>
                    <EvidenceList
                      evidence={[
                        ...linkResult.suspiciousParams.map((item) => ({
                          label: item.name,
                          evidence: item.reason,
                          riskLevel: item.riskLevel
                        })),
                        {
                          label: `来源场景：${linkResult.sourceRisk.source}`,
                          evidence: linkResult.sourceRisk.reason,
                          riskLevel: linkResult.sourceRisk.riskLevel
                        }
                      ]}
                    />
                  </section>
                  <DecisionCard title="是否建议打开链接" ok={linkResult.shouldOpen} positive="可以谨慎打开" negative="不建议直接打开" />
                </>
              )}
            </div>
          </div>
        </>
      )}

      {page === 'doc' && (
        <>
          <PageHero
            eyebrow="Doc Shield"
            title="Doc Shield 提交护盾"
            copy="按“输入提交要求 + 上传材料 + 生成提交检查报告”的流程，检查材料完整性、格式规范、隐私风险、提交建议和安全评分。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid doc-tool-grid">
            <section className="card form-card doc-form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>提交要求与材料上传</h3>
                  <p>支持 txt、md、pdf、docx 内容解析；图片和压缩包会先检查文件名、后缀和上传状态。</p>
                </div>
              </div>
              <textarea
                value={docRequirement}
                onChange={(event) => setDocRequirement(event.target.value)}
                placeholder="粘贴课程论文、比赛材料、报名附件等提交要求"
              />
              <label className="upload-box doc-upload-box">
                <input
                  multiple
                  type="file"
                  accept=".txt,.md,.pdf,.docx,.png,.jpg,.jpeg,.zip"
                  onChange={(event) => setDocFiles(Array.from(event.target.files ?? []))}
                />
                <span className="upload-icon">+</span>
                <strong>{docFiles.length ? `已选择 ${docFiles.length} 个文件` : '选择或拖入多个材料文件'}</strong>
                <span>PDF / DOCX / TXT / MD / PNG / JPG / ZIP</span>
              </label>
              {docFiles.length > 0 && (
                <div className="file-chip-list">
                  {docFiles.map((file) => (
                    <span key={`${file.name}-${file.size}`}>{file.name}</span>
                  ))}
                </div>
              )}
              <div className="capability-list">
                <span>要求解析</span>
                <span>完整性检查</span>
                <span>格式规范</span>
                <span>隐私风险</span>
              </div>
              <button
                className="primary-button"
                disabled={loadingDoc || !docRequirement.trim() || docFiles.length === 0}
                onClick={handleDocCheck}
              >
                {loadingDoc ? '检查中...' : '生成提交检查报告'}
              </button>
            </section>
            <DocReportPanel result={docResult} />
          </div>
        </>
      )}
    </main>
  );
}

function PageHero({
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

function ImageCompareCard({ title, imageUrl }: { title: string; imageUrl: string }) {
  return (
    <div className="compare-card">
      <strong>{title}</strong>
      <img src={imageUrl} alt={title} />
    </div>
  );
}

function DecisionCard({
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

function DocReportPanel({ result }: { result: DocCheckResponse | null }) {
  if (!result) {
    return (
      <RiskReport
        title="提交检查报告"
        emptyText="上传材料并开始检查后，这里会展示要求解析、材料完整性、格式规范、隐私风险、提交建议和安全评分。"
      />
    );
  }

  const groups = {
    completeness: result.checks.filter((item) => item.category === 'completeness'),
    format: result.checks.filter((item) => item.category === 'format'),
    privacy: result.checks.filter((item) => item.category === 'privacy')
  };

  return (
    <section className="card result-card doc-report">
      <div className="section-title">
        <span>R</span>
        <div>
          <h3>提交检查报告</h3>
          <p>{result.summary}</p>
        </div>
      </div>
      <div className={`risk-banner ${result.riskLevel}`}>
        <RiskBadge level={result.riskLevel} />
        <span>提交安全评分</span>
        <b>{result.score} / 100</b>
      </div>

      <div className="parsed-requirements">
        <h4>解析出的提交要求</h4>
        <RequirementItem label="文件格式" value={result.parsedRequirements.formats.join('、') || '未明确'} />
        <RequirementItem label="命名规则" value={result.parsedRequirements.namingRule || '未明确'} />
        <RequirementItem label="必需材料" value={result.parsedRequirements.requiredMaterials.join('、') || '未明确'} />
        <RequirementItem label="字数/页数" value={result.parsedRequirements.lengthRequirement || '未明确'} />
        <RequirementItem label="截止时间" value={result.parsedRequirements.deadline || '未明确'} />
      </div>

      <DocCheckGroup title="材料完整性" items={groups.completeness} />
      <DocCheckGroup title="格式规范" items={groups.format} />
      <DocCheckGroup title="隐私风险" items={groups.privacy} />

      <div className="uploaded-files">
        <h4>已上传材料</h4>
        {result.files.map((file) => (
          <div key={file.fileName}>
            <strong>{file.fileName}</strong>
            <span>
              .{file.extension || '无后缀'} / {file.status} / {file.wordCount} 字
            </span>
          </div>
        ))}
      </div>

      <SuggestionList suggestions={result.suggestions} />
    </section>
  );
}

function RequirementItem({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function DocCheckGroup({ title, items }: { title: string; items: DocCheckResponse['checks'] }) {
  return (
    <div className="doc-check-group">
      <h4>{title}</h4>
      <EvidenceList evidence={items} />
    </div>
  );
}
