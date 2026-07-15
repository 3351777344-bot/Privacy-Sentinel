import { useEffect, useRef, useState } from 'react';
import { DecisionCard, PageHero } from '../components/PageComponents';
import { RiskBadge, RiskReport } from '../components/RiskComponents';
import type { CodeAnalyzeResponse, CodeVulnerability, TextFinding } from '../types/privacy';

const languageOptions = [
  { value: 'auto', label: '自动识别' },
  { value: 'python', label: 'Python' },
  { value: 'java', label: 'Java' },
  { value: 'javascript', label: 'JavaScript' },
  { value: 'typescript', label: 'TypeScript' },
  { value: 'sql', label: 'SQL' },
  { value: 'other', label: 'Other' }
];

interface CodePageProps {
  text: string;
  language: string;
  file: File | null;
  result: CodeAnalyzeResponse | null;
  loading: boolean;
  fixedCode: string | null;
  loadingFix: boolean;
  onBack: () => void;
  onTextChange: (value: string) => void;
  onLanguageChange: (value: string) => void;
  onFileChange: (file: File | null) => void;
  onAnalyze: () => Promise<void>;
  onFix: (items: Array<{type: string, title: string, line?: number | null, snippet: string}>) => Promise<void>;
  onExport: () => void;
}

const DETECTOR_LABELS: Record<string, string> = {
  rule: '本地规则',
  deepseek: 'DeepSeek AI',
};

function evidenceFromResult(result: CodeAnalyzeResponse | null): TextFinding[] {
  return (
    result?.vulnerabilities.map((item) => ({
      label: (item.source === 'deepseek' ? '[DeepSeek] ' : '') + (item.line ? `${item.title} / 第 ${item.line} 行` : item.title),
      evidence: `${item.snippet || '未截取到代码片段'}。${item.reason}`,
      riskLevel: item.riskLevel
    })) ?? []
  );
}

function buildVulnLineSet(vulns: CodeVulnerability[]): Set<number> {
  const s = new Set<number>();
  vulns.forEach((v) => { if (typeof v.line === 'number') s.add(v.line); });
  return s;
}

function CodeLines({ lines, vulnSet }: { lines: string[]; vulnSet: Set<number> }) {
  return (
    <div className="code-line-numbers">
      {lines.map((_, idx) => {
        const lineNum = idx + 1;
        return <span key={idx} className={vulnSet.has(lineNum) ? 'vuln-line' : ''}>{lineNum}</span>;
      })}
    </div>
  );
}

export default function CodePage(props: CodePageProps) {
  const [selectedFixIds, setSelectedFixIds] = useState<string[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const linesRef = useRef<HTMLDivElement>(null);

  const vulns = props.result?.vulnerabilities ?? [];
  const vulnLineSet = buildVulnLineSet(vulns);
  const codeLines = props.text.split('\n');

  useEffect(() => {
    const ta = textareaRef.current;
    const ln = linesRef.current;
    if (!ta || !ln) return;
    const sync = () => { ln.scrollTop = ta.scrollTop; };
    ta.addEventListener('scroll', sync, { passive: true });
    return () => ta.removeEventListener('scroll', sync);
  }, []);

  const toggleSelect = (id: string) => {
    setSelectedFixIds((prev) => prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]);
  };

  const handleFix = () => {
    const selected = vulns.filter((v) => selectedFixIds.includes(v.id));
    if (selected.length === 0) return;
    setSelectedFixIds([]);
    props.onFix(selected.map((v) => ({ type: v.type, title: v.title, line: v.line, snippet: v.snippet })));
  };

  const selectAllHigh = () => {
    const ids = vulns.filter((v) => v.riskLevel === 'high').map((v) => v.id);
    setSelectedFixIds(ids);
  };

  return (
    <>
      <PageHero eyebrow="Code Guardian" title="Code Guardian 代码卫士" copy="提交代码之前，先检查潜在安全风险。AI 辅助检测并修复漏洞。" onBack={props.onBack} />
      <div className="tool-grid">
        <section className="card form-card">
          <div className="section-title">
            <span>01</span>
            <div>
              <h3>代码输入区</h3>
              <p>粘贴代码或上传单个代码文件，支持 .py / .java / .js / .ts / .sql / .txt。</p>
            </div>
          </div>
          <label className="field-label">
            代码语言
            <select value={props.language} onChange={(event) => props.onLanguageChange(event.target.value)}>
              {languageOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </label>
          {props.result && (
            <p className="muted">
              识别语言：{props.result.language}（{props.result.languageSource}，{Math.round(props.result.languageConfidence * 100)}%）
              {props.result.detectorSource && <> · {DETECTOR_LABELS[props.result.detectorSource] ?? props.result.detectorSource}</>}
            </p>
          )}
          {props.result?.deepseekWarning && (
            <div className="deepseek-warning">{props.result.deepseekWarning}</div>
          )}
          <div className="code-editor-wrapper">
            <div className="code-line-numbers" ref={linesRef}>
              {codeLines.map((_, idx) => (
                <span key={idx} className={vulnLineSet.has(idx + 1) ? 'vuln-line' : ''}>{idx + 1}</span>
              ))}
            </div>
            <textarea
              ref={textareaRef}
              value={props.text}
              onChange={(event) => props.onTextChange(event.target.value)}
              className="code-textarea"
              spellCheck={false}
              placeholder="在此粘贴代码…"
            />
          </div>
          <label className="upload-box doc-upload-box">
            <input type="file" accept=".py,.java,.js,.ts,.sql,.txt,.zip" onChange={(event) => {
              const f = event.target.files?.[0] ?? null;
              if (f && !f.name.toLowerCase().endsWith('.zip')) {
                f.text().then((t) => props.onTextChange(t));
              }
              props.onFileChange(f);
            }} />
            <span className="upload-icon">+</span>
            <strong>{props.file ? props.file.name : '选择单个代码文件'}</strong>
            <span>.py / .java / .js / .ts / .sql / .txt</span>
          </label>
          {props.file?.name.toLowerCase().endsWith('.zip') && <p className="muted">暂不支持 zip 项目包，请上传单个文件或粘贴代码。</p>}
          <button className="primary-button" disabled={props.loading || (!props.text.trim() && !props.file)} onClick={props.onAnalyze}>
            {props.loading ? '检测中...' : '开始代码安全检测'}
          </button>
        </section>

        <div className="report-stack">
          <RiskReport
            title="代码安全体检报告"
            riskLevel={props.result?.riskLevel}
            score={props.result?.score}
            summary={props.result?.summary}
            evidence={evidenceFromResult(props.result)}
            suggestions={props.result?.suggestions}
          />

          {props.result && vulns.length > 0 && (
            <section className="card result-card">
              <div className="section-title">
                <span>F</span>
                <div>
                  <h3>漏洞修复面板</h3>
                  <p>勾选需要修复的项目，点击按钮由 DeepSeek 自动生成修复代码。</p>
                </div>
              </div>
              <div className="vuln-select-list">
                {vulns.map((vuln) => (
                  <label className="vuln-checkbox" key={vuln.id}>
                    <input type="checkbox" checked={selectedFixIds.includes(vuln.id)} onChange={() => toggleSelect(vuln.id)} />
                    <span className={`finding-label ${vuln.riskLevel}`}>
                      {vuln.source === 'deepseek' ? '[DeepSeek] ' : ''}
                      {vuln.line ? `第 ${vuln.line} 行 · ` : ''}{vuln.title}
                    </span>
                  </label>
                ))}
              </div>
              <div className="fix-actions">
                <button className="secondary-button" onClick={selectAllHigh}>全选高风险</button>
                <button className="primary-button fix-btn" disabled={selectedFixIds.length === 0 || props.loadingFix} onClick={handleFix}>
                  {props.loadingFix ? '修复中...' : `一键修复选中 (${selectedFixIds.length})`}
                </button>
              </div>
            </section>
          )}

          {props.fixedCode && (
            <section className="card result-card">
              <div className="section-title">
                <span>C</span>
                <div>
                  <h3>修复前后对照</h3>
                  <p>左侧原代码风险行已标红，右侧为 AI 修复后版本，请人工复核。</p>
                </div>
              </div>
              <div className="code-compare-grid">
                <div className="code-compare-col">
                  <strong>修复前</strong>
                  <div className="code-compare-box">
                    <div className="code-compare-lines">
                      {codeLines.map((_, idx) => (
                        <span key={idx} className={vulnLineSet.has(idx + 1) ? 'vuln-line' : ''}>{idx + 1}</span>
                      ))}
                    </div>
                    <pre className="code-preview">{props.text}</pre>
                  </div>
                </div>
                <div className="code-compare-col">
                  <strong>修复后</strong>
                  <div className="code-compare-box">
                    <pre className="code-preview fixed">{props.fixedCode}</pre>
                  </div>
                </div>
              </div>
              <button className="primary-button export-btn" onClick={props.onExport}>
                导出修复后代码文件
              </button>
            </section>
          )}

          {props.result && (
            <DecisionCard
              title="是否建议直接提交代码"
              ok={props.result.shouldSubmit}
              positive="可以提交"
              negative={props.result.riskLevel === 'high' ? '不建议提交' : '建议修复后提交'}
            />
          )}
        </div>
      </div>
    </>
  );
}
