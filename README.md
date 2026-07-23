# GuardianHub · 高校数字安全防护平台

GuardianHub 是面向高校学生的“操作前安全闸门”，把风险检查前置到图片分享、代码提交、链接点击和材料上传之前。项目同时提供 HarmonyOS 客户端、PC Web 演示端和 FastAPI 检测服务；四个模块统一输出风险等级、0–100 安全评分、命中证据与处置建议。

> 当前状态：HarmonyOS 6.0.2 工程可编译并生成调试 HAP，已在 API 22 手机模拟器完成安装、页面路由和 Link Guard 真实请求验证；系统 Picker、四模块 API、ArkData 本地历史、处理图预览/保存和 Share Kit 均已完成代码接入。PC Web 四模块、项目 ZIP 扫描、历史记录和自动化测试均已跑通。

## 四个安全节点

| 操作节点 | 模块 | 已实现能力 |
| --- | --- | --- |
| 分享图片前 | Privacy Sentinel 隐私哨兵 | OCR、二维码与隐私规则检测，黑条/模糊/马赛克脱敏，导出安全图片 |
| 提交代码前 | Code Guardian 代码卫士 | 代码片段、单文件和项目 ZIP 静态扫描，文件级证据、行号与修复建议 |
| 点击链接前 | Link Guard 链接卫士 | URL 与二维码内容静态检查，不主动访问目标地址 |
| 上传材料前 | Doc Shield 提交护盾 | PDF、DOCX、TXT、Markdown 的完整性、格式、命名与隐私检查 |

项目坚持“本地优先、联网可选”。核心规则、OCR、二维码解析和图像处理可在本机或自建后端运行；DeepSeek 与 Qwen VL 仅作为可选增强，默认关闭，只有用户主动选择联网模式并配置服务后才会调用。

## 项目结构

```text
GuardianHub/
├── README.md
├── .github/workflows/ci.yml
└── platform/
    ├── harmony/                 # HarmonyOS 6 / ArkTS 客户端
    ├── frontend/                # React + Vite + TypeScript PC Web
    ├── backend/                 # FastAPI、检测引擎、SQLite 与测试
    ├── samples/                 # 不含真实隐私的演示与验收样本
    ├── docs/                    # 初赛介绍、接口、展示稿与冲刺计划
    ├── .env.example             # 后端配置示例
    └── README.md                # 开发与联调说明
```

## 快速运行

### 1. 启动后端

要求 Python 3.10 或更高版本。若要让 HarmonyOS 模拟器访问服务，后端必须监听 `0.0.0.0`。

```powershell
cd platform\backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

启动后可访问：

- 健康检查：`http://127.0.0.1:8000/api/health`
- Swagger API 文档：`http://127.0.0.1:8000/docs`

### 2. 启动 PC Web

Vite 8 要求 Node.js 20.19+ 或 22.12+。

```powershell
cd platform\frontend
npm install
npm run dev
```

浏览器打开 `http://127.0.0.1:5173`。

### 3. 打开 HarmonyOS 客户端

1. 启动 DevEco Studio，选择 **Open**。
2. 打开 `platform\harmony`，等待工程同步完成。
3. 启动 API 22 手机模拟器，选择 `entry` 模块后点击 **Run**。

也可以在 PowerShell 中构建：

```powershell
cd platform\harmony
.\build.ps1
```

调试 HAP 输出到：

```text
platform/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap
```

鸿蒙工程的环境、签名和联调细节见 [platform/harmony/README.md](platform/harmony/README.md)。

## 配置

后端不配置 `.env` 也能以本地模式运行。需要调整上传限制、保留时间或启用联网模型时，将 `platform/.env.example` 复制为 `platform/.env` 并修改；`.env` 和密钥不得提交到 Git。

常用开关：

- `GUARDIANHUB_PRIVACY_ENGINE`：`ocr` / `agent` / `hybrid` / `vision_api`
- `GUARDIANHUB_CODE_ENGINE`：`rule` / `deepseek`
- `GUARDIANHUB_QWEN_ENABLED`：Qwen VL 总开关，默认 `false`
- `GUARDIANHUB_DEEPSEEK_ENABLED`：DeepSeek 总开关，默认 `false`
- `GUARDIANHUB_DEMO_MODE`：固定演示数据开关，默认 `false`

## 验证

```powershell
cd platform\backend
python -m pip install -r requirements-dev.txt
python -m pytest

cd ..\frontend
npm test
npm run build

cd ..\harmony
.\build.ps1
```

## 初赛材料

- [800 字项目介绍](platform/docs/初赛800字介绍.md)
- [完整项目介绍](platform/docs/项目介绍文档.md)
- [接口文档](platform/docs/接口文档.md)
- [5 分钟展示文稿](platform/docs/展示.md)
- [初赛冲刺计划](platform/docs/2026鸿蒙高校创新赛初赛冲刺计划.md)
- [演示样本说明](platform/samples/README.md)

## 源码压缩包建议

初赛若要求提交“项目源码”，建议提交整个项目，而不是只提交 `harmony/`。源码包至少保留：

- 根目录 `README.md`
- `platform/harmony/`
- `platform/backend/`
- `platform/frontend/`
- `platform/docs/`
- `platform/.env.example`

打包前排除 `.git/`、`.idea/`、`.hvigor/`、`.cache/`、`node_modules/`、`oh_modules/`、`build/`、`dist/`、`.env`、日志、SQLite 数据库和用户上传文件。HAP、作品说明 PDF 与演示视频按赛事提交入口要求作为独立产物上传，不要混入源码目录。

## 安全边界

- Code Guardian 的 ZIP 扫描只读文件，不解压落盘、不安装依赖、不执行代码；它是轻量静态规则检查，不等同于完整 SAST 或依赖漏洞扫描。
- Link Guard 只做静态分析，不主动访问目标 URL，避免把检查服务变成 SSRF 入口。
- 图片和材料设置大小、格式与数量限制；历史和上传产物默认保留 24 小时。
- “未命中规则”不代表绝对安全，最终报告始终保留人工复核建议。
