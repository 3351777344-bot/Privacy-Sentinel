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
import HistoryList from './components/HistoryList';
import ImagePreview from './components/ImagePreview';
import MaskControl from './components/MaskControl';
import PrivacyItemList from './components/PrivacyItemList';
import { riskText } from './components/RiskSummary';
import RiskSummary from './components/RiskSummary';
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

const modules: Array<{
  id: Page;
  title: string;
  subtitle: string;
  detail: string;
  accent: string;
  status: string;
}> = [
  {
    id: 'privacy',
    title: 'Privacy Sentinel 隐私哨兵',
    subtitle: '图片分享前隐私检测与一键打码',
    detail: '识别手机号、地址、二维码、头像、昵称等敏感区域，并生成安全分享版本。',
    accent: 'blue',
    status: '已接入'
  },
  {
    id: 'scam',
    title: 'Scam Radar 反诈雷达',
    subtitle: '聊天文本 / 截图诈骗风险识别',
    detail: '用规则识别转账、中奖、验证码、冒充客服、刷单兼职等典型诈骗话术。',
    accent: 'red',
    status: '规则版'
  },
  {
    id: 'link',
    title: 'Link Guard 链接卫士',
    subtitle: 'URL 和二维码风险检测',
    detail: '检查 HTTPS、短链接、可疑关键词、异常域名和访问建议。',
    accent: 'teal',
    status: '规则版'
  },
  {
    id: 'doc',
    title: 'Doc Shield 提交护盾',
    subtitle: '作业、报名材料、报告提交前检查',
    detail: '展示文件命名、隐私内容、材料清单三类提交前自检能力。',
    accent: 'amber',
    status: '已接入'
  }
];

const sampleScamText = '老师通知：奖学金补贴今日截止，请点击链接填写银行卡和验证码，逾期视为放弃。';

const sampleDocRequirement =
  '课程论文提交要求：请于 2026年7月20日 18:00 前提交 PDF 文件，命名规则为 学号-姓名-课程论文。材料需包含封面、摘要、正文、参考文献；正文不少于3000字。';

function riskScore(records: HistoryRecord[]) {
  const penalty = records.slice(0, 5).reduce((total, record) => {
    if (record.riskLevel === 'high') return total + 9;
    if (record.riskLevel === 'medium') return total + 5;
    return total + 1;
  }, 0);
  return Math.max(62, 96 - penalty);
}

function riskClass(level?: RiskLevel) {
  return level ? `risk-pill ${level}` : 'risk-pill low';
}

function FindingList({ findings }: { findings: TextFinding[] }) {
  if (findings.length === 0) {
    return <p className="muted">暂无风险命中项。</p>;
  }

  return (
    <div className="finding-list">
      {findings.map((item, index) => (
        <article className={`finding-item ${item.riskLevel}`} key={`${item.label}-${index}`}>
          <div>
            <strong>{item.label}</strong>
            <span>{item.evidence}</span>
          </div>
          <em className={riskClass(item.riskLevel)}>{riskText[item.riskLevel]}</em>
        </article>
      ))}
    </div>
  );
}

function ResultPanel({
  title,
  result
}: {
  title: string;
  result?: ScamAnalyzeResponse | LinkCheckResponse | DocCheckResponse | null;
}) {
  return (
    <section className="card result-card">
      <div className="section-title">
        <span>R</span>
        <div>
          <h3>{title}</h3>
          <p>所有模块统一使用 high / medium / low 风险等级。</p>
        </div>
      </div>
      {result ? (
        <>
          <div className={`risk-banner ${result.riskLevel}`}>
            <strong>{riskText[result.riskLevel]}</strong>
            <span>{'score' in result ? `规则评分：${result.score}` : '已完成规则检查'}</span>
          </div>
          <FindingList findings={'checks' in result ? result.checks : result.reasons} />
          <div className="suggestion-box">
            <strong>建议操作</strong>
            {result.suggestions.map((suggestion) => (
              <p key={suggestion}>{suggestion}</p>
            ))}
          </div>
        </>
      ) : (
        <p className="muted">提交内容后，这里会显示风险等级、风险原因和建议操作。</p>
      )}
    </section>
  );
}

function DocReportPanel({ result }: { result: DocCheckResponse | null }) {
  const checksByCategory = {
    completeness: result?.checks.filter((item) => item.category === 'completeness') ?? [],
    format: result?.checks.filter((item) => item.category === 'format') ?? [],
    privacy: result?.checks.filter((item) => item.category === 'privacy') ?? []
  };

  if (!result) {
    return (
      <section className="card result-card doc-report">
        <div className="section-title">
          <span>R</span>
          <div>
            <h3>提交前检查报告</h3>
            <p>上传材料并开始检查后，这里会展示解析要求、完整性、格式命名、隐私风险和修改建议。</p>
          </div>
        </div>
        <p className="muted">等待生成报告。</p>
      </section>
    );
  }

  return (
    <section className="card result-card doc-report">
      <div className="section-title">
        <span>R</span>
        <div>
          <h3>提交前检查报告</h3>
          <p>{result.summary}</p>
        </div>
      </div>

      <div className={`risk-banner ${result.riskLevel}`}>
        <strong>{riskText[result.riskLevel]}</strong>
        <span>提交安全评分：{result.score} / 100</span>
      </div>

      <div className="parsed-requirements">
        <h4>解析出的提交要求</h4>
        <div>
          <span>文件格式</span>
          <strong>{result.parsedRequirements.formats.join('、') || '未明确'}</strong>
        </div>
        <div>
          <span>命名规则</span>
          <strong>{result.parsedRequirements.namingRule || '未明确'}</strong>
        </div>
        <div>
          <span>必需材料</span>
          <strong>{result.parsedRequirements.requiredMaterials.join('、') || '未明确'}</strong>
        </div>
        <div>
          <span>字数/页数</span>
          <strong>{result.parsedRequirements.lengthRequirement || '未明确'}</strong>
        </div>
        <div>
          <span>截止时间</span>
          <strong>{result.parsedRequirements.deadline || '未明确'}</strong>
        </div>
      </div>

      <DocCheckGroup title="材料完整性检查结果" items={checksByCategory.completeness} />
      <DocCheckGroup title="文件格式与命名检查结果" items={checksByCategory.format} />
      <DocCheckGroup title="隐私风险检查结果" items={checksByCategory.privacy} />

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

      <div className="suggestion-box">
        <strong>修改建议列表</strong>
        {result.suggestions.map((suggestion) => (
          <p key={suggestion}>{suggestion}</p>
        ))}
      </div>
    </section>
  );
}

function DocCheckGroup({ title, items }: { title: string; items: DocCheckResponse['checks'] }) {
  return (
    <div className="doc-check-group">
      <h4>{title}</h4>
      {items.length > 0 ? <FindingList findings={items} /> : <p className="muted">暂无检查项。</p>}
    </div>
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

  const [scamText, setScamText] = useState(sampleScamText);
  const [scamResult, setScamResult] = useState<ScamAnalyzeResponse | null>(null);
  const [loadingScam, setLoadingScam] = useState(false);

  const [url, setUrl] = useState('http://bit.ly/scholarship-verify');
  const [linkResult, setLinkResult] = useState<LinkCheckResponse | null>(null);
  const [loadingLink, setLoadingLink] = useState(false);

  const [docName, setDocName] = useState('张三_计算机学院_创新创业报名表.docx');
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

  const score = useMemo(() => riskScore(history), [history]);

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

  async function handleScamAnalyze() {
    setLoadingScam(true);
    setError('');
    try {
      setScamResult(await analyzeScamText(scamText));
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
      setLinkResult(await checkLink(url));
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
      setDocResult(await checkDoc(docRequirement, docFiles));
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
          {modules.map((module) => (
            <button
              className={page === module.id ? 'active' : ''}
              key={module.id}
              onClick={() => setPage(module.id)}
            >
              {module.title.split(' ')[0]}
            </button>
          ))}
        </div>
      </nav>

      {error && <div className="error-bar">{error}</div>}

      {page === 'home' && (
        <>
          <header className="app-header">
            <div className="hero-copy">
              <p className="eyebrow">GuardianHub / Campus AI Safety</p>
              <h1>GuardianHub</h1>
              <h2>面向高校场景的 AI 数字安全防护平台</h2>
              <p className="header-copy">
                将 Privacy Sentinel 隐私哨兵升级为 GuardianHub 安全中心，覆盖图片分享、聊天反诈、链接访问和材料提交四个高频数字生活入口。
              </p>
            </div>
            <div className="score-card">
              <span>今日安全评分</span>
              <strong>{score}</strong>
              <p>{score >= 85 ? '整体态势良好' : '建议复核近期高风险记录'}</p>
            </div>
          </header>

          <section className="intro card">
            <div>
              <h3>GuardianHub：面向高校场景的 AI 数字安全防护平台</h3>
              <p>
                GuardianHub 以“提交前、点击前、分享前、转账前”为防护节点，先用本地规则和 mock 数据保证演示稳定，
                后续可平滑升级 OCR、二维码识别、诈骗语义识别和高校身份场景策略。
              </p>
            </div>
            <div className="intro-tags">
              <span>本地稳定运行</span>
              <span>统一风险等级</span>
              <span>高校场景优先</span>
              <span>规则可解释</span>
            </div>
          </section>

          <section className="module-grid">
            {modules.map((module) => (
              <article className={`module-card ${module.accent}`} key={module.id}>
                <div>
                  <span>{module.status}</span>
                  <h3>{module.title}</h3>
                  <p>{module.subtitle}</p>
                </div>
                <p>{module.detail}</p>
                <button onClick={() => setPage(module.id)}>进入模块</button>
              </article>
            ))}
          </section>

          <div className="dashboard-grid">
            <section className="card posture-card">
              <div className="section-title">
                <span>S</span>
                <div>
                  <h3>安全态势</h3>
                  <p>根据最近检测记录生成今日安全评分。</p>
                </div>
              </div>
              <div className="score-meter">
                <b>{score}</b>
                <span>Score</span>
              </div>
              <div className="posture-row">
                <span>高风险记录</span>
                <strong>{history.filter((item) => item.riskLevel === 'high').length}</strong>
              </div>
              <div className="posture-row">
                <span>最近检测</span>
                <strong>{history.length}</strong>
              </div>
            </section>
            <HistoryList records={history} />
          </div>
        </>
      )}

      {page === 'privacy' && (
        <>
          <PageHero
            eyebrow="Privacy Sentinel"
            title="隐私哨兵"
            copy="图片分享前隐私检测与一键打码，保留原有完整检测、标注、处理和历史记录能力。"
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
                  <h3>处理后图片</h3>
                  <p>打码完成后在这里查看安全分享版本，确认无误后再对外发送。</p>
                </div>
              </div>
              {processedUrl ? (
                <div className="safe-content">
                  <img src={processedUrl} alt="处理后的安全图片" />
                  <div className="safe-verdict">
                    <span>安全预览</span>
                    <b>已生成可分享复核版本</b>
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
        </>
      )}

      {page === 'scam' && (
        <>
          <PageHero
            eyebrow="Scam Radar"
            title="反诈雷达"
            copy="输入聊天文本，基于规则识别奖学金补贴、刷单兼职、验证码索取、冒充客服等诈骗风险。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>聊天文本分析</h3>
                  <p>可粘贴聊天记录文本；聊天截图识别后也可把 OCR 文本放在这里检测。</p>
                </div>
              </div>
              <textarea value={scamText} onChange={(event) => setScamText(event.target.value)} />
              <button className="primary-button" disabled={loadingScam || !scamText.trim()} onClick={handleScamAnalyze}>
                {loadingScam ? '分析中...' : '开始风险识别'}
              </button>
            </section>
            <ResultPanel title="诈骗风险结果" result={scamResult} />
          </div>
        </>
      )}

      {page === 'link' && (
        <>
          <PageHero
            eyebrow="Link Guard"
            title="链接卫士"
            copy="输入 URL，检查 HTTPS、短链接、可疑关键词和域名异常，二维码解析后的链接也可复用此能力。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>URL 检测</h3>
                  <p>先做规则检测，保证本地演示稳定运行。</p>
                </div>
              </div>
              <input value={url} onChange={(event) => setUrl(event.target.value)} placeholder="https://example.com" />
              <button className="primary-button" disabled={loadingLink || !url.trim()} onClick={handleLinkCheck}>
                {loadingLink ? '检测中...' : '检查链接风险'}
              </button>
            </section>
            <ResultPanel title="链接风险结果" result={linkResult} />
          </div>
        </>
      )}

      {page === 'doc' && (
        <>
          <PageHero
            eyebrow="Doc Shield"
            title="提交护盾"
            copy="输入提交要求并上传材料，系统会检查材料是否齐全、格式命名是否规范，并识别文件文本中的隐私安全风险。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid doc-tool-grid">
            <section className="card form-card doc-form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>提交要求与材料上传</h3>
                  <p>支持 txt、md、pdf、docx 内容解析；png、jpg、zip 会先做文件名、后缀和上传状态检查。</p>
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
                <span>格式命名检查</span>
                <span>隐私风险检查</span>
              </div>
              <button
                className="primary-button"
                disabled={loadingDoc || !docRequirement.trim() || docFiles.length === 0}
                onClick={handleDocCheck}
              >
                {loadingDoc ? '检查中...' : '开始检查'}
              </button>
            </section>
            <DocReportPanel result={docResult} />
          </div>
        </>
      )}

      {false && page === 'doc' && (
        <>
          <PageHero
            eyebrow="Doc Shield"
            title="提交护盾"
            copy="作业、报名材料、报告提交前的隐私与格式检查。当前为静态 / mock 能力展示。"
            onBack={() => setPage('home')}
          />
          <div className="tool-grid">
            <section className="card form-card">
              <div className="section-title">
                <span>01</span>
                <div>
                  <h3>材料名称检查</h3>
                  <p>输入拟提交文件名，演示文件命名、隐私检查、材料清单检查三类能力。</p>
                </div>
              </div>
              <input value={docName} onChange={(event) => setDocName(event.target.value)} />
              <div className="capability-list">
                <span>文件命名检查</span>
                <span>隐私检查</span>
                <span>材料清单检查</span>
              </div>
              <button className="primary-button" disabled={loadingDoc} onClick={handleDocCheck}>
                {loadingDoc ? '检查中...' : '生成 Mock 检查结果'}
              </button>
            </section>
            <section className="card result-card">
              <div className="section-title">
                <span>R</span>
                <div>
                  <h3>提交前检查结果</h3>
                  <p>当前以 mock 数据展示完整交互闭环。</p>
                </div>
              </div>
              {docResult ? (
                <>
                  <div className={`risk-banner ${docResult!.riskLevel}`}>
                    <strong>{riskText[docResult!.riskLevel]}</strong>
                    <span>已生成提交前检查建议</span>
                  </div>
                  <FindingList findings={docResult!.checks} />
                  <div className="checklist">
                    {docResult!.checklist?.map((item) => (
                      <div className={item.status} key={item.item}>
                        <strong>{item.item}</strong>
                        <span>{item.status}</span>
                      </div>
                    ))}
                  </div>
                  <div className="suggestion-box">
                    <strong>建议操作</strong>
                    {docResult!.suggestions.map((suggestion) => (
                      <p key={suggestion}>{suggestion}</p>
                    ))}
                  </div>
                </>
              ) : (
                <p className="muted">点击按钮后展示文件命名、隐私与材料清单检查结果。</p>
              )}
            </section>
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
