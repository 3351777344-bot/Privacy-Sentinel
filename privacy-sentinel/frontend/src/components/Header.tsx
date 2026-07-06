export default function Header() {
  return (
    <header className="app-header">
      <div className="hero-copy">
        <p className="eyebrow">AI 隐私安全分享助手</p>
        <h1>Privacy Sentinel</h1>
        <h2>分享之前，先让 AI 帮你检查一遍</h2>
        <p className="header-copy">
          面向截图、聊天记录、订单页面和快递单等分享场景，自动识别隐私风险并生成安全分享版本。
        </p>
      </div>
      <div className="hero-panel" aria-label="隐私检测能力概览">
        <span>风险识别</span>
        <strong>AI Guard</strong>
        <small>OCR / QR / 人脸 / 地址 / 电话</small>
      </div>
    </header>
  );
}
