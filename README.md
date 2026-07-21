# GuardianHub · 数字安全防护平台

GuardianHub 是面向高校场景的可控数字安全防护平台 Demo，把风险检查前置到「分享前、提交前、点击前、上传前」四个关键时刻。平台采用**本地优先、联网可选**的处理方式：图片隐私检测和代码检测可在界面中选择纯本地处理或联网增强；链接和提交材料始终在本机静态检查。只有用户主动选择联网增强且已配置模型服务时，相关图片或代码才会发送至第三方 API。当前 PC Web 实现位于 `platform/`。

- 前端：React 18 + Vite + TypeScript
- 后端：FastAPI + Pydantic v2
- 本地能力：RapidOCR（ONNX Runtime）文字识别、OpenCV 二维码/人脸检测、正则与规则引擎
- 存储：本地 SQLite（历史记录），本地文件系统（原图 / 处理图 / 检测结果）
- 可选增强：DeepSeek（代码分析与一键修复）、Qwen VL（图片隐私视觉检测），均通过 OpenAI 兼容接口调用，默认关闭

## 核心模块

- **Privacy Sentinel 隐私哨兵**：可选择本地 OCR/二维码/人脸规则检测，或使用 Qwen VL 联网增强识别；支持手机号、证件号、银行卡号、邮箱、订单号、地址等敏感区域，并可按「高风险 / 全部 / 自定义」范围进行黑条、模糊、马赛克处理，导出安全分享版本。
- **Code Guardian 代码卫士**：可选择本地规则或 DeepSeek 联网增强，自动识别代码语言，检查硬编码凭据、SQL 注入、命令执行、路径穿越、弱加密、敏感日志、危险配置和 XSS 等风险；联网模式下还支持 AI 深度分析与一键修复。
- **Link Guard 链接卫士**：检查 HTTP/HTTPS 协议、域名、IP 直连、短链、可疑参数、随机 token、Punycode 仿冒域名、来源场景等风险，并支持本地解析二维码图片，全程不主动访问目标地址。
- **Doc Shield 提交护盾**：解析提交要求，从 PDF / DOCX / TXT / Markdown 等材料中提取内容，检查材料完整性、格式规范、命名规则、隐私信息和提交风险。

所有模块统一输出 `high` / `medium` / `low` 风险等级、0–100 安全评分（分数越高越安全）、命中证据和建议操作。检测历史统一保存在本地 SQLite，刷新页面后仍可查看，并按模块统计平均安全分。

## 目录结构

```text
Privacy-Sentinel/
├── README.md                    # 项目总说明（本文件）
├── .github/workflows/ci.yml     # CI：后端 pytest + 前端 build
└── platform/
    ├── backend/                 # FastAPI 服务
    │   ├── main.py              # 应用入口与所有 API 路由
    │   ├── config.py            # 环境变量与运行配置
    │   ├── detector/            # 隐私检测：OCR / 正则 / 二维码 / 人脸 / 视觉 Agent
    │   ├── image_processor/     # 黑条、模糊、马赛克处理
    │   ├── modules/             # code_guardian / link_guard / doc_shield / 风险评分
    │   ├── schemas/             # Pydantic 数据模型
    │   ├── storage/             # SQLite 历史存储
    │   ├── static/              # 上传图、处理图、示例图
    │   ├── data/                # SQLite 数据库与检测结果 JSON（本地产物）
    │   └── tests/               # pytest 测试
    ├── frontend/                # React + TypeScript 界面
    │   └── src/
    │       ├── pages/           # Privacy / Code / Link / Doc / History 页面
    │       ├── components/      # 上传、预览、打码、风险报告等组件
    │       ├── api/             # 后端接口封装
    │       └── utils/           # 评分等前端工具
    ├── docs/                    # 项目介绍、接口文档、演示脚本
    └── .env.example             # 可配置的安全限制与引擎开关
```

## 本地启动

### 后端（首次安装会加入 RapidOCR 与 ONNX Runtime）

```bash
cd platform/backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

### 前端

```bash
cd platform/frontend
npm install
npm run dev
```

- 前端：`http://127.0.0.1:5173`
- 后端：`http://127.0.0.1:8000`
- API 文档：`http://127.0.0.1:8000/docs`

## API 概览

后端默认地址 `http://127.0.0.1:8000`，详细字段见 `platform/docs/接口文档.md`。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 健康检查，返回当前隐私检测引擎 |
| POST | `/api/detect` | 上传图片进行隐私检测 |
| POST | `/api/mask` | 对指定区域打码 |
| POST | `/api/privacy/process` | 按 `high` / `all` / `custom` 范围批量打码 |
| POST | `/api/export/image/{image_id}` | 下载已处理的安全图片 |
| POST | `/api/code/analyze` | 代码安全检测（JSON 或文件上传） |
| POST | `/api/code/fix` | DeepSeek 一键修复（需启用） |
| POST | `/api/link/check` | 链接静态安全体检 |
| POST | `/api/link/qr/decode` | 本地解析二维码图片 |
| POST | `/api/doc/check` | 提交材料检查 |
| GET | `/api/history` | 分页查询检测历史 |
| GET | `/api/history/module-averages` | 各模块平均安全分 |
| DELETE | `/api/history/{record_id}` | 删除单条历史 |

## 检测引擎配置

隐私检测和代码检测可在对应页面选择「本地处理」或「联网增强」。环境变量（见 `platform/.env.example`）用于配置联网模型、默认后端引擎及功能开关：

- `GUARDIANHUB_PRIVACY_ENGINE`：`ocr`（纯本地）/ `agent`（本地 + 人脸，默认）/ `hybrid`（本地 + Qwen VL）/ `vision_api`（Qwen VL 优先，本地兜底）
- `GUARDIANHUB_FACE_ENGINE`：人脸检测引擎，默认 `disabled`，启用需配置 `GUARDIANHUB_FACE_MODEL_PATH`
- `GUARDIANHUB_CODE_ENGINE`：`rule`（本地正则）/ `deepseek`（AI 分析，需 `GUARDIANHUB_DEEPSEEK_ENABLED=true` 且配置密钥）
- `GUARDIANHUB_QWEN_ENABLED` / `GUARDIANHUB_DEEPSEEK_ENABLED`：外部大模型总开关，默认 `false`

> 界面默认选择本地处理。只有选择联网增强后才会尝试调用外部模型；未配置密钥、开关关闭或调用失败时，会自动回退到本地规则并给出提示。DeepSeek 一键修复属于联网功能，必须配置服务后才能使用。

## 安全与隐私

- 默认限制图片 10 MB、代码 1 MB、单个材料 10 MB、单次材料总计 25 MB、单次最多 8 个材料文件。
- 上传图片会校验真实格式和像素尺寸，而不是只相信文件名或 MIME 类型；图片仅支持 PNG、JPEG、WEBP，默认上限 2500 万像素。
- Link Guard 只做静态分析，不主动访问用户输入的目标 URL，避免引入 SSRF 风险；二维码解析同样在本机完成。
- 原图、处理图和历史默认保留 24 小时，可通过 `platform/.env.example` 中的环境变量调整。
- CORS 默认只允许本地 Vite 地址。
- 历史记录使用本地 SQLite；上传文件、数据库和检测结果均不会提交到 Git。
- 外部大模型能力（DeepSeek / Qwen VL）默认关闭；需显式配置密钥、开启服务并在界面选择联网增强后才会调用。联网模式可能将当前图片或代码发送给所配置的服务商。
- 设置 `GUARDIANHUB_DEMO_MODE=true` 才会显式启用固定演示框，默认使用真实 OCR。

## 验证

```bash
cd platform/backend
python -m pip install -r requirements-dev.txt
python -m pytest

cd ../frontend
npm run build      # tsc --noEmit + vite build
npm run test       # vitest
```

仓库已配置 GitHub Actions，在推送和拉取请求时执行后端测试与前端构建。

## 设计边界

- OCR、二维码、人脸和规则检测都可在本机运行，不强制依赖付费大模型 API。
- Code Guardian 面向单文件和代码片段，尚不是完整的 SAST 或依赖漏洞扫描器（项目级 zip 扫描为后续扩展）。
- 图片检测中的人脸识别为可选能力，需自行配置本地模型；「未命中规则」不等于绝对安全，界面会保留人工复核提示。
