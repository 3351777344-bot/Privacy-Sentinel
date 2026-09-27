# GuardianHub 鸿蒙分享链路安全预检

GuardianHub 在 HarmonyOS 系统分享菜单中接收图片、链接、代码和文件，先执行端侧检查，再由用户决定是否继续分享或授权增强分析。它是分享目标，不是系统级拦截器；未命中规则不代表安全。

## 当前验收状态

本次改进基于 ebf6e37，位于 codex/contest-release-hardening。工程验证与比赛发布验收分开：当前可以构建未签名调试 HAP；正式签名、真实设备分享回归、生产 HTTPS 服务和演示视频尚待完成。不得将此状态描述为已具备正式参赛提交条件。

## 数据处理边界

| 入口 | 默认行为 | 需要授权的行为 |
| --- | --- | --- |
| 鸿蒙分享图片与图片页 | 端侧二维码解析；不执行端侧 OCR | 上传原图进行后端 OCR；敏感二维码原图禁止上传 |
| 鸿蒙链接与代码片段 | 端侧静态规则 | 代码页选择联网增强并逐次授权后发送代码 |
| 鸿蒙 ZIP 与文档 | 端侧结构、威胁和命名规则 | 文档增强上传原文件；代码增强上传 ZIP |
| 文档信誉查询 | 默认关闭 | 发送 SHA256 与风险等级，不发送原文件、文件名和 URL 参数 |
| PC Web | 私有后端演示端，非浏览器离线扫描器 | 每次分析或处理 POST 前确认上传；规则模式不调用模型 |

鸿蒙处理模式定义为 local_only、hybrid、online，默认 hybrid；hybrid 当前执行端侧检测，增强需用户主动选择和逐次确认。后端兼容的 local 表示服务器规则模式，绝不表示文件没有离开客户端。网络错误不自动重试上传。

## 启动

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-alongside-hekgemi.ps1
```

API 使用 8001，Web 使用 5174；8000 和 5173 属于 HekGemi，不要停止或占用。

- [健康检查](http://127.0.0.1:8001/api/health)
- [Web 演示](http://127.0.0.1:5174/)

## 验证与构建

```powershell
cd platform/backend
python -m pytest
cd ../frontend
npm test
npm run build
cd ../harmony
.\build.ps1
```

端侧威胁验证：先运行 python tools/threat-tests/make_fixtures.py，再运行 node tools/threat-tests/prepare.mjs、node --experimental-strip-types tools/threat-tests/run-tests.mjs 和 node tools/threat-tests/privacy-contract.mjs。

## 交付文档

- [工程基线](platform/docs/工程基线报告.md)
- [部署与签名配置](platform/docs/部署配置说明.md)
- [鸿蒙能力边界](platform/docs/鸿蒙能力说明.md)
- [项目说明](platform/docs/项目介绍文档.md)
- [验收报告](platform/docs/验收报告.md)
- [比赛材料目录](submission/README.md)

签名密码曾进入 Git 历史。当前配置已清理，但历史仍需持有人安排凭据轮换和历史处置。不要把真实凭据或证书写入版本库。
