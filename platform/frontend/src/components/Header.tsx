export default function Header() {
  return (
    <header className="app-header">
      <div className="hero-copy">
        <p className="eyebrow">GuardianHub / Campus AI Safety</p>
        <h1>GuardianHub</h1>
        <h2>面向高校场景的 AI 数字安全防护平台</h2>
        <p className="header-copy">
          覆盖图片分享、聊天反诈、链接访问、材料提交四类高频场景，用规则引擎与本地 mock 能力保障 Demo 稳定运行。
        </p>
      </div>
      <div className="hero-panel" aria-label="安全评分">
        <span>今日安全评分</span>
        <strong>86</strong>
        <small>低风险态势，建议继续保持提交前检查习惯</small>
      </div>
    </header>
  );
}
