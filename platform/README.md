# GuardianHub 开发与联调指南

`platform/` 包含 GuardianHub 的三个可运行部分：

| 目录 | 技术栈 | 用途 |
| --- | --- | --- |
| `harmony/` | HarmonyOS 6、ArkTS、Stage 模型 | 初赛主要客户端，调用 FastAPI 完成四模块检测 |
| `frontend/` | React 18、TypeScript、Vite | PC Web 完整能力演示与接口验收 |
| `backend/` | FastAPI、Pydantic、SQLite | 检测、脱敏、历史记录与统一 API |

## 后端

要求 Python 3.10+。

```powershell
cd backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

使用 `0.0.0.0` 是为了允许 HarmonyOS 模拟器通过 `http://10.0.2.2:8000` 访问开发电脑。只运行 Web 时也可以监听 `127.0.0.1`。

主要入口：

- `GET /api/health`：健康检查
- `/docs`：Swagger API 文档
- `POST /api/detect`、`/api/privacy/process`：图片检测与脱敏
- `POST /api/code/analyze`：代码或项目 ZIP 扫描
- `POST /api/link/check`、`/api/link/qr/decode`：链接与二维码检查
- `POST /api/doc/check`：提交材料检查（`processing_mode=local|online`，online 需 `X-Guardian-Consent: explicit`）
- `GET /api/history`：本地历史记录

完整字段以 `platform/backend/schemas/models.py` 为准（接口文档随提交材料单独存放，不在本仓库内）。

## PC Web

Vite 8 要求 Node.js 20.19+ 或 22.12+。

```powershell
cd frontend
npm install
npm run dev
```

默认地址为 `http://127.0.0.1:5173`，默认调用 `http://127.0.0.1:8000`。

## HarmonyOS

用 DevEco Studio 打开 `harmony/`，等待同步后选择 API 22 设备运行 `entry`。命令行构建：

```powershell
cd harmony
.\build.ps1
```

当前已接入系统图片/文件 Picker、四模块 API、ArkData 本地历史、处理图预览/系统保存与 Share Kit，可产出 release 签名的 HAP（见 [harmony/BUILD_AND_SIGN.md](harmony/BUILD_AND_SIGN.md)）。模拟器上已验证首页与四个模块页的路由、文案与配色，并在应用内走通了一次联网链接检查（服务端访问日志确认收到该请求）；**真实设备**上的系统分享面板、相册授权与 Share Kit 交互仍未回归，编译与模拟器验证都不能替代这一项。

详细环境和联调说明见 [harmony/README.md](harmony/README.md)。

## 环境配置

后端从 `platform/.env` 读取可选配置。首次使用可复制示例：

```powershell
Copy-Item .env.example .env
```

本地模式无需 API 密钥。DeepSeek 默认关闭；它是后端唯一的外部模型（文本隐私分析、代码审计、图片视觉都走它）。不要把真实密钥写入 `.env.example` 或提交到 Git。

关键限制的默认值：

| 项目 | 默认限制 |
| --- | --- |
| 图片 | 10 MB、2500 万像素 |
| 单个代码文件 | 1 MB |
| 项目 ZIP | 10 MB、300 个条目、解压后 50 MB |
| 单个材料文件 | 10 MB |
| 单次材料 | 8 个文件、合计 25 MB |
| 本地产物保留 | 24 小时 |
| 每客户端 `/api/*` 请求 | 600 次 / 60 秒 |
| 每客户端模型调用 | 120 次 / 300 秒 |

限流面向公网部署：后端没有账号鉴权，而 `/api/detect`、`/api/code/analyze`、`/api/code/fix`、
`/api/doc/check` 会消耗付费模型额度，所以这四条路径按客户端 IP 单独计额。上限刻意远高于真实用量
（一次完整演示约 2–6 次模型调用），只用于拦截脚本洪水。可用 `GUARDIANHUB_RATE_LIMIT_ENABLED=false`
整体关闭，或把某项额度设为 0 停用该项。客户端身份取 `X-Forwarded-For` 的**最后一段**
（反向代理实际观察到的地址），首段由客户端自行填写、可伪造，取它等于形同虚设。

`/api/doc/check` 只有 online 请求会真正调用模型，但额度是按路径选择的（模式藏在 multipart 请求体里，
中间件不应读取请求体），所以它的两种模式都计入模型额度——这是把限流器保持为纯 ASGI 包装的代价。

## 提交护盾的联网解析

`processing_mode` 决定 `/api/doc/check` 用哪种方式读提交要求：

| 模式 | 要求解析 | 材料核对 | 是否调用模型 |
| --- | --- | --- | --- |
| `local`（默认） | 规则表 + 关键词（`modules/doc_shield/requirement_parser.py`） | 格式、命名、材料关键词、字数、截止时间、隐私正则 | 否 |
| `online` | 大模型读原文，抽格式/命名/材料清单/篇幅/截止时间/内容要求 | 在前者基础上，由模型对每条内容要求给出 满足/需确认/不满足 | 是（最多两次调用） |

联网路径的两条硬性约束：

- **逐字段回退。** 模型没给出的字段保留规则表的解析结果，所以一次只读懂一半的原文仍能产出完整报告；
  模型完全读不懂时，`parsedRequirements.source` 保持 `local`，`modelWarning` 说明原因，报告与纯本地模式完全一致。
- **不猜。** 服务端只认请求里的 `processing_mode`，不会因为「客户端大概开着联网」就调用模型；
  online 请求缺少 `X-Guardian-Consent: explicit` 一律 403，与 `/api/detect`、`/api/code/analyze` 同一套写法。

发给模型的是**提取出的纯文本节选**（每份材料 6000 字、合计 12000 字，见 `GUARDIANHUB_DOC_CONTENT_CHARS_*`），
不是原文件；图片和压缩包提取不到正文时跳过内容判定，并提示转人工确认。字数和隐私检查仍在完整文本上运行。

自检工具（对着**真模型**跑一次，验证提示词与真实返回对得上；单元测试注入的是固定返回，验不了这一层）：

```powershell
python tools/doc-intent-check.py --brief samples/doc-risky/requirement.txt --file samples/doc-risky/course-paper.txt
```

它只读本地文件与 `.env`，不写历史、不碰 API；未启用模型时打印回退路径并以 0 退出（这是受支持的结果），
只有「模型答了但答案不可用」才返回 1。`--enable --base http://127.0.0.1:8099 --key x` 可指向本地桩服务联调。

## 联网分析失败时怎么定位

`POST /api/detect` 的响应里有两个容易混淆的字段，区别是「给用户看的」和「给运维看的」：

| 字段 | 面向 | 内容 |
| --- | --- | --- |
| `detectorMessage` | 用户 | 只有结论，例如「联网图像分析调用失败，已保留本机识别结果。」，不含任何内部标识 |
| `detectorDetail` | 运维/支持 | 真实原因，例如 `AuthenticationError \| HTTP 401 \| ...`、`APITimeoutError \| ...`、`unparseable_response \| finish_reason=length \| ...`；正常时为 `ok`，未启用时为 `vision_disabled`，模型确实没发现内容时为 `empty_result` |

这条链路是「托管后端、从外部诊断」：用户可见的文案必须保持干净，而失败与成功原本从 API
上完全看不出差别，所以原因必须落在响应里，而不是只能登服务器看日志。客户端**不渲染**该字段
（隐私哨兵只把它记进用户自己的历史记录），它不是第二个消息通道。

视觉调用在网络类失败（超时、连接中断、5xx、429）时会**自动重试一次**，其余失败（密钥、
模型、不可解析的返回）立即降级为「保留本机识别结果」，以免重复消耗额度。策略与原因文案
由 `backend/model_retry.py` 统一提供，`backend/tests/test_model_retry.py` 与
`tests/test_vision_diagnostics.py` 固定住这两条契约。

`GUARDIANHUB_DEEPSEEK_TIMEOUT_SECONDS` 是**单次**请求的超时：一次调用最多占用它两倍时间
（首试 + 重试），客户端读超时必须大于这个总和。

## 测试与构建

```powershell
cd backend
python -m pip install -r requirements-dev.txt
python -m pytest

cd ..\frontend
npm test
npm run build

cd ..\harmony
.\build.ps1
```

仓库 CI 会运行后端测试和前端构建；HarmonyOS 构建目前需在已安装 DevEco Studio 与 SDK 的 Windows 环境执行。

## 演示样本

`samples/` 中提供虚构的代码和材料样本；隐私图片位于 `backend/static/samples/`。生成 Code Guardian 上传用 ZIP：

```powershell
cd samples
.\build-samples.ps1
```

具体演示输入见 [samples/README.md](samples/README.md)。

## 数据与隐私

- 图片 OCR、二维码解析、规则扫描和图像脱敏可在本机或私有后端完成。
- 项目 ZIP 在内存中只读扫描，不执行代码，不安装依赖。
- Link Guard 不访问用户输入的目标网址。
- SQLite、上传文件、处理结果、构建目录和 `.env` 均已排除在版本控制之外。
- 联网增强只在用户选择对应模式、启用开关并配置服务后生效。

返回仓库总览、初赛文档和源码打包说明请查看 [根目录 README](../README.md)。
