import { useEffect, useMemo, useState } from 'react';
import {
  analyzeScamText,
  checkDoc,
  checkLink,
  detectImage,
  fetchHistory,
  maskImage,
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
  SuggestionList,
  riskText
} from './components/RiskComponents';
import UploadPanel from './components/UploadPanel';
import type {
  DetectResult,
  DocCheckResponse,
  HistoryRecord,
  LinkCheckResponse,
  MaskType,
  RiskLevel,
  ScamAnalyzeResponse,
  TextFinding
} from './types/privacy';

type Page = 'home' | 'privacy' | 'scam' | 'link' | 'doc';
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
    title: '隐私哨兵',
    subtitle: '图片分享前隐私检测与打码',
    detail: '识别手机号、地址、二维码、头像、昵称等敏感区域，生成安全分享版本。',
    accent: 'blue'
  },
  {
    id: 'scam',
    title: '反诈雷达',
    subtitle: '聊天文本诈骗风险识别',
    detail: '识别诱导转账、高额回报、催促决策、脱离平台、隐瞒他人和可疑链接。',
    accent: 'red'
  },
  {
    id: 'link',
    title: '链接卫士',
    subtitle: 'URL 体检与访问建议',
    detail: '检查 HTTPS、短链接、可疑关键词、异常域名、过长 URL、随机字符和可疑参数。',
    accent: 'teal'
  },
  {
    id: 'doc',
    title: '提交护盾',
    subtitle: '材料提交前安全检查',
    detail: '按提交要求、上传材料、生成报告的流程检查完整性、格式、隐私风险和评分。',
    accent: 'amber'
  }
];

const sampleScamText =
  '老师通知：奖学金补贴今日截止，请点击链接填写银行卡和验证码，逾期视为放弃。不要告诉其他同学，名额有限。';

const sampleDocRequirement =
  '课程论文提交要求：请于 2026年7月10日 18:00 前提交 PDF 文件，命名规则为 学号-姓名-课程论文。材料需包含封面、摘要、正文、参考文献；正文不少于 3000 字。';

function scoreFromRisk(level: RiskLevel) {
  if (level === 'high') return 48;
  if (level === 'medium') return 74;
  return 92;
}

function privacyScore(result?: DetectResult | null) {
  if (!result) return undefined;
  const penalty = result.items.reduce((total, item) => {
    if (item.riskLevel === 'high') return total + 18;
    if (item.riskLevel === 'medium') return total + 9;
    return total + 2;
  }, 0);
  return Math.max(0, 100 - penalty);
}

function overallScore(records: HistoryRecord[], latestScores: Array<number | undefined>) {
  const recordPenalty = records.slice(0, 6).reduce((total, record) => {
    if (record.riskLevel === 'high') return total + 9;
    if (record.riskLevel === 'medium') return total + 5;
    return total + 1;
  }, 0);
  const activeScores = latestScores.filter((score): score is number => typeof score === 'number');
  const sessionAverage = activeScores.length
    ? Math.round(activeScores.reduce((total, score) => total + score, 0) / activeScores.length)
    : 96;
  return Math.max(45, Math.min(100, Math.round((sessionAverage + (96 - recordPenalty)) / 2)));
}

function makeHistoryRecord(moduleName: string, riskLevel: RiskLevel, summary: string, status = '已生成报告'): HistoryRecord {
  return {
    imageId: moduleName,
    originalImageUrl: '',
    processedImageUrl: null,
    riskLevel,
    summary,
    createdAt: new Date().toLocaleString('zh-CN', { hour12: false }),
    status
  };
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

export default function App() {
  const [page, setPage] = useState<Page>('home');
  const [detectResult, setDetectResult] = useState<DetectResult | null>(null);
  const [processedUrl, setProcessedUrl] = useState('');
  const [history, setHistory] = useState<HistoryRecord[]>([]);
  const [sessionHistory, setSessionHistory] = useState<HistoryRecord[]>([]);
  const [maskType, setMaskType] = useState<MaskType>('black');
  const [loadingDetect, setLoadingDetect] = useState(false);
  const [loadingMask, setLoadingMask] = useState(false);
  const [error, setError] = useState('');

  const [scamText, setScamText] = useState(sampleScamText);
  const [scamResult, setScamResult] = useState<ScamAnalyzeResponse | null>(null);
  const [loadingScam, setLoadingScam] = useState(false);

  const [url, setUrl] = useState('http://bit.ly/scholarship-verify?bank=1&code=login');
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

  const mergedHistory = useMemo(() => [...sessionHistory, ...history], [sessionHistory, history]);
  const score = useMemo(
    () =>
      overallScore(mergedHistory, [
        privacyScore(detectResult),
        scamResult?.score,
        linkResult ? scoreFromRisk(linkResult.riskLevel) : undefined,
        docResult?.score
      ]),
    [detectResult, docResult, linkResult, mergedHistory, scamResult]
  );

  const moduleStatus = useMemo(() => {
    return {
      privacy: {
        riskLevel: detectResult?.riskLevel ?? history[0]?.riskLevel ?? ('low' as RiskLevel),
        score: privacyScore(detectResult) ?? (history[0] ? scoreFromRisk(history[0].riskLevel) : 92),
        status: detectResult ? detectResult.summary : history[0]?.summary ?? '等待图片检测'
      },
      scam: {
        riskLevel: scamResult?.riskLevel ?? ('low' as RiskLevel),
        score: scamResult?.score ?? 92,
        status: scamResult ? `识别到 ${scamResult.reasons.length} 条风险证据` : '等待文本分析'
      },
      link: {
        riskLevel: linkResult?.riskLevel ?? ('low' as RiskLevel),
        score: linkResult ? scoreFromRisk(linkResult.riskLevel) : 92,
        status: linkResult ? `完成 ${linkResult.checks.length} 项链接体检` : '等待 URL 体检'
      },
      doc: {
        riskLevel: docResult?.riskLevel ?? ('low' as RiskLevel),
        score: docResult?.score ?? 92,
        status: docResult?.summary ?? '等待材料检查'
      }
    };
  }, [detectResult, docResult, history, linkResult, scamResult]);

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

    const selectedItems = detectResult.items
      .filter((item) => {
        if (scope === 'all') return true;
        if (scope === 'high') return item.riskLevel === 'high';
        return selectedIds.includes(item.id);
      })
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

  async function handleScamAnalyze() {
    setLoadingScam(true);
    setError('');
    try {
      const result = await analyzeScamText(scamText);
      setScamResult(result);
      setSessionHistory((current) => [
        makeHistoryRecord('反诈雷达', result.riskLevel, `诈骗风险分析：${riskText[result.riskLevel]}`),
        ...current
      ]);
    } catch (err) {
      setError(err instanceof Error ? err.message : '反诈分析失败，请稍后重试。');
    } finally {
      setLoadingScam(false);
    }
  }

  async function handleLinkCheck() {
    setLoadingLink(true);
    setError('');
    try {
      const result = await checkLink(url);
      setLinkResult(result);
      setSessionHistory((current) => [
        makeHistoryRecord('链接卫士', result.riskLevel, `链接体检：${result.normalizedUrl}`),
        ...current
      ]);
    } catch (err) {
      setError(err instanceof Error ? err.message : '链接检测失败，请稍后重试。');
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
      setSessionHistory((current) => [
        makeHistoryRecord('提交护盾', result.riskLevel, result.summary),
        ...current
      ]);
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
              <h2>统一的 AI 数字安全防护平台</h2>
              <p className="header-copy">
                GuardianHub 面向高校与个人数字生活场景，把图片分享、聊天反诈、链接访问、材料提交四类高频风险整合到同一个安全中心。
                当前版本基于本地规则和可解释报告运行，不接入付费大模型 API，也不强依赖复杂 OCR。
              </p>
            </div>
            <ScoreCard score={score} title="今日安全评分" />
          </header>

          <section className="intro card">
            <div>
              <h3>从四个安全工具升级为统一安全平台</h3>
              <p>
                平台以“分享前、点击前、转账前、提交前”为防护节点，统一输出 high / medium / low 风险等级、0-100 安全评分、风险证据和建议操作。
              </p>
            </div>
            <div className="intro-tags">
              <span>统一风险报告</span>
              <span>本地规则可解释</span>
              <span>卡片式安全中心</span>
              <span>高校场景优先</span>
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
            title="隐私哨兵"
            copy="图片分享前隐私检测与打码，保留原有图片检测、标注、处理和历史记录能力，并增加处理前后对比与检测报告。"
            onBack={() => setPage('home')}
          />
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

      {page === 'scam' && (
        <>
          <PageHero
            eyebrow="Scam Radar"
            title="反诈雷达"
            copy="输入聊天文本，识别诱导转账、高额回报、催促决策、脱离平台、隐瞒他人、可疑链接等诈骗风险。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>聊天文本分析</h3>
                  <p>粘贴聊天记录或 OCR 后的截图文本，系统会输出风险证据和防骗建议。</p>
                </div>
              </div>
              <textarea value={scamText} onChange={(event) => setScamText(event.target.value)} />
              <button className="primary-button" disabled={loadingScam || !scamText.trim()} onClick={handleScamAnalyze}>
                {loadingScam ? '分析中...' : '开始风险识别'}
              </button>
            </section>
            <RiskReport
              title="诈骗风险报告"
              riskLevel={scamResult?.riskLevel}
              score={scamResult?.score}
              summary={scamResult ? `识别到 ${scamResult.reasons.length} 条风险证据。` : undefined}
              evidence={scamResult?.reasons}
              suggestions={scamResult?.suggestions}
            />
          </div>
        </>
      )}

      {page === 'link' && (
        <>
          <PageHero
            eyebrow="Link Guard"
            title="链接卫士"
            copy="输入 URL 生成链接体检报告，检查 HTTPS、短链接、可疑关键词、异常域名、URL 过长、随机字符和可疑参数。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>URL 体检</h3>
                  <p>二维码解析出的链接也可以粘贴到这里进行本地规则检测。</p>
                </div>
              </div>
              <input value={url} onChange={(event) => setUrl(event.target.value)} placeholder="https://example.com" />
              <button className="primary-button" disabled={loadingLink || !url.trim()} onClick={handleLinkCheck}>
                {loadingLink ? '检测中...' : '生成链接体检报告'}
              </button>
            </section>
            <RiskReport
              title="链接体检报告"
              riskLevel={linkResult?.riskLevel}
              score={linkResult ? scoreFromRisk(linkResult.riskLevel) : undefined}
              summary={linkResult ? `标准化链接：${linkResult.normalizedUrl}` : undefined}
              evidence={linkResult?.checks}
              suggestions={linkResult?.suggestions}
            />
          </div>
        </>
      )}

      {page === 'doc' && (
        <>
          <PageHero
            eyebrow="Doc Shield"
            title="提交护盾"
            copy="按照“输入提交要求 + 上传材料 + 生成提交检查报告”的逻辑，检查材料完整性、格式规范、隐私风险、提交建议和安全评分。"
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
