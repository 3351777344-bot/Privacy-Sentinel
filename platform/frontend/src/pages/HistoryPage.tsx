import { useState } from 'react';
import type { HistoryRecord } from '../types/privacy';
import { PageHero } from '../components/PageComponents';
import { RiskBadge } from '../components/RiskComponents';
import { effectiveScore } from '../utils/scoring';

interface HistoryPageProps {
  records: HistoryRecord[];
  onBack: () => void;
  onNavigate?: (module: string, recordId: string) => void;
  onDelete?: (recordId: string) => Promise<void>;
}

const MODULE_LABELS: Record<string, string> = {
  privacy: '隐私哨兵',
  code: '代码卫士',
  link: '链接卫士',
  doc: '提交护盾',
};

const MODULE_GLYPHS: Record<string, string> = {
  privacy: '🔒',
  code: '⌨',
  link: '🔗',
  doc: '📄',
};

function scoreChange(record: HistoryRecord): string | null {
  if (!record.processed || record.score == null || record.processedScore == null) return null;
  if (record.score === record.processedScore) return `${record.score} / 100`;
  return `${record.score} → ${record.processedScore}`;
}

export default function HistoryPage({ records, onBack, onNavigate, onDelete }: HistoryPageProps) {
  const [filter, setFilter] = useState<string>('all');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const filtered = filter === 'all' ? records : records.filter((r) => r.module === filter);

  const stats = {
    total: records.length,
    processed: records.filter((r) => r.processed).length,
    pending: records.filter((r) => !r.processed).length,
  };

  return (
    <>
      <PageHero
        eyebrow="History"
        title="检测历史记录"
        copy="查看所有模块的历史检测报告，追溯风险变化和处理状态。已完成处理的记录评分将自动提升。"
        onBack={onBack}
      />

      <div className="history-page-grid">
        <aside className="history-filter-bar">
          <div className="history-stats card">
            <div className="stat-row"><span>总记录</span><b>{stats.total}</b></div>
            <div className="stat-row" style={{ color: '#059669' }}><span>已处理</span><b>{stats.processed}</b></div>
            <div className="stat-row" style={{ color: '#d97706' }}><span>待处理</span><b>{stats.pending}</b></div>
          </div>

          <div className="history-filter card">
            <h4>模块筛选</h4>
            <button className={filter === 'all' ? 'active' : ''} onClick={() => setFilter('all')}>全部</button>
            {Object.entries(MODULE_LABELS).map(([key, label]) => (
              <button key={key} className={filter === key ? 'active' : ''} onClick={() => setFilter(key)}>
                <span className="filter-glyph">{MODULE_GLYPHS[key]}</span> {label}
              </button>
            ))}
          </div>
        </aside>

        <section className="history-main">
          {filtered.length === 0 ? (
            <div className="card empty-state">
              <strong>暂无历史检测记录</strong>
              <p>完成任一检测模块后，记录会自动保存在这里。</p>
            </div>
          ) : (
            <div className="history-timeline">
              {filtered.map((record) => {
                const isExpanded = expandedId === record.recordId;
                const module = record.module ?? 'privacy';
                const processed = record.processed ?? false;
                const change = scoreChange(record);
                return (
                  <article
                    className={`history-report-card ${record.riskLevel} ${processed ? 'processed' : ''} ${isExpanded ? 'expanded' : ''}`}
                    key={record.recordId || `${record.imageId}-${record.createdAt}`}
                  >
                    <div className="report-card-header" onClick={() => setExpandedId(isExpanded ? null : record.recordId ?? null)}>
                      <div className="report-card-meta">
                        <span className="module-badge">{MODULE_GLYPHS[module]} {MODULE_LABELS[module]}</span>
                        <RiskBadge level={record.riskLevel} compact />
                        <span className="score-badge">{change ?? `${effectiveScore(record)} 分`}</span>
                        <span className={`status-pill ${processed ? 'done' : ''}`}>{record.status}</span>
                      </div>
                      <p className="report-card-summary">{record.summary}</p>
                      <time>{new Date(record.createdAt).toLocaleString('zh-CN', { hour12: false })}</time>
                      <span className="expand-toggle">{isExpanded ? '收起 ▲' : '查看详情 ▼'}</span>
                    </div>
                    {isExpanded && (
                      <div className="report-card-detail">
                        <dl>
                          <dt>模块</dt>
                          <dd>{MODULE_LABELS[module]}</dd>
                          <dt>风险等级</dt>
                          <dd>{record.riskLevel === 'high' ? '高风险' : record.riskLevel === 'medium' ? '中风险' : '低风险'}</dd>
                          {processed && change ? (
                            <>
                              <dt>评分变化</dt>
                              <dd className="score-improvement">{change} / 100</dd>
                            </>
                          ) : (
                            <>
                              <dt>安全评分</dt>
                              <dd>{effectiveScore(record)} / 100</dd>
                            </>
                          )}
                          <dt>处理状态</dt>
                          <dd>{processed ? '✅ 已处理' : '⏳ 待处理'}</dd>
                          <dt>检测时间</dt>
                          <dd>{new Date(record.createdAt).toLocaleString('zh-CN', { hour12: false })}</dd>
                        </dl>
                        <div className="report-card-summary-detail">
                          <strong>检测摘要</strong>
                          <p>{record.summary}</p>
                        </div>
                        {!processed && onNavigate && record.recordId && (
                          <button className="primary-button restore-btn" onClick={() => onNavigate(module, record.recordId!)}>
                            继续处理 →
                          </button>
                        )}
                        {onDelete && record.recordId && (
                          <button
                            className="delete-btn"
                            disabled={deletingId === record.recordId}
                            onClick={async (e) => {
                              e.stopPropagation();
                              setDeletingId(record.recordId!);
                              try { await onDelete(record.recordId!); } finally { setDeletingId(null); }
                            }}
                          >
                            {deletingId === record.recordId ? '删除中...' : '删除此记录'}
                          </button>
                        )}
                      </div>
                    )}
                  </article>
                );
              })}
            </div>
          )}
        </section>
      </div>
    </>
  );
}
