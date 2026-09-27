# GuardianHub 鸿蒙分享链路安全预检

GuardianHub 在 HarmonyOS 系统分享菜单中接收图片、链接、代码和文件，先执行端侧检查，再由用户决定是否继续分享或授权增强分析。它是分享目标，不是系统级拦截器；未命中规则不代表安全。

## 当前状态

发布签名 HAP 由 `platform/harmony/BUILD_AND_SIGN.md` 的流程在本机构建（产物与哈希清单不入库）；
生产后端已部署在 `https://api.guardianhub.tech`，以 systemd 服务 `guardianhub.service` 运行
（`Restart=always` 且已设开机自启，只监听 `127.0.0.1:8001`，由 Caddy 对外终止 TLS）；
真实设备分享回归与演示视频尚待完成。
**服务器不会自动获取代码更新**，部署是手工的，仓库领先于线上属于常态；而 `/api/health`
只要进程存活就返回 200，无法反映代码是否已更新，确认线上版本必须靠一次真实业务请求。详见下文「部署」。
不得将此状态描述为已具备正式参赛提交条件。

## 数据处理边界

| 入口 | 默认行为 | 需要授权的行为 |
| --- | --- | --- |
| 鸿蒙分享图片与图片页 | 端侧二维码解析；不执行端侧 OCR | 上传原图进行后端 OCR；敏感二维码原图禁止上传 |
| 鸿蒙链接与代码片段 | 端侧静态规则 | 代码页选择联网增强并逐次授权后发送代码 |
| 鸿蒙 ZIP 与文档 | 端侧结构、威胁和命名规则 | 文档增强上传原文件；代码增强上传 ZIP |
| 鸿蒙提交护盾的联网解析 | 默认仅端侧与后端规则解析要求 | 材料正文节选与提交要求发送给模型服务；失败自动回退本地规则 |
| 文档信誉查询 | 默认关闭 | 发送 SHA256 与风险等级，不发送原文件、文件名和 URL 参数 |
| PC Web | 私有后端演示端，非浏览器离线扫描器 | 每次分析或处理 POST 前确认上传；规则模式不调用模型 |

鸿蒙各模块提供 local_only 和 online 两种处理模式，默认仅本地。隐私图片页默认联网分析：选择图片时先执行端侧二维码检查，再申请本次上传授权；同一张图片后续生成或调整脱敏预览复用该授权。敏感或无法可靠解析二维码时，阻止原图上传。后端兼容的 local 表示服务器规则模式，绝不表示文件没有离开客户端。网络错误不自动重试上传。

提交护盾的 online 模式由后端大模型读提交要求（格式、命名、材料清单、篇幅、截止时间、内容要求），并逐条判定材料是否满足内容要求；模型没给出的字段回退到规则表解析，模型不可用时报告标注为本地规则并说明原因，不会静默降级。发给模型的是提取出的正文节选，不是原文件。

## 启动

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-alongside-hekgemi.ps1
```

API 使用 8001，Web 使用 5174；8000 和 5173 属于 HekGemi，不要停止或占用。

- [健康检查](http://127.0.0.1:8001/api/health)
- [Web 演示](http://127.0.0.1:5174/)

## 部署

生产后端位于服务器 `/root/guardianhub`，从本仓库 `main` 分支手工部署：

```bash
cd /root/guardianhub
git pull
systemctl restart guardianhub
systemctl is-active guardianhub
```

公网部署默认启用按客户端限流：`/api/*` 每客户端 600 次 / 60 秒，模型端点
（`/api/detect`、`/api/code/analyze`、`/api/code/fix`、`/api/doc/check`）120 次 / 300 秒。上限刻意远高于真实用量，
只用于拦截脚本洪水；`GUARDIANHUB_RATE_LIMIT_ENABLED=false` 可整体关闭，重启服务即清空计数。
完整配置见 `platform/.env.example`。

部署完确认线上版本：`/api/health` 只说明进程活着，`privacyDetector` 也只反映引擎名，
两者都不代表代码已更新，**必须发一次真实业务请求**。最快的判定是 `POST /api/detect`：
响应里出现 `detectorDetail` 字段，说明线上已包含 `b7159fb` 之后的代码。

```bash
curl -s -X POST https://api.guardianhub.tech/api/detect \
  -H 'X-Guardian-Consent: explicit' -F processing_mode=online \
  -F 'file=@platform/samples/emulator-gallery/03_form_demo.png;type=image/png'
```

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

对**线上部署**的复验不在这套单元测试里：单元测试注入固定的模型返回，验不了提示词与真实返回是否对得上。
`tools/doc-online-probe/` 放的是对着真实服务跑过的探针与实测记录（`probe.py` 五个用例、
`probe2.py` 的回退与限流检查），改完提示词或合并逻辑后可以重跑一遍。

## 交付文档

本仓库只保留代码与开发文档。比赛提交材料（项目说明、功能清单、数据流与隐私说明、演示脚本、
版本说明、验收报告、能力说明、接口文档等）单独存放，不随代码提交。

- 构建与签名：[platform/harmony/BUILD_AND_SIGN.md](platform/harmony/BUILD_AND_SIGN.md)
- 平台开发说明：[platform/README.md](platform/README.md)
- 发布自检：`python tools/release-check.py`（清单与产物通过 `GUARDIANHUB_DELIVERY_DIR` 指向交付目录）

签名密码曾进入 Git 历史。当前配置已清理，但历史仍需持有人安排凭据轮换和历史处置。不要把真实凭据或证书写入版本库。
