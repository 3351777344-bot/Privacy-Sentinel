# GuardianHub · 高校数字安全防护平台

GuardianHub 是面向高校学生的“操作前安全闸门”，把风险检查前置到图片分享、代码提交、链接点击和材料上传之前。项目同时提供 HarmonyOS 客户端、PC Web 演示端和 FastAPI 检测服务；四个模块统一输出风险等级、0–100 安全评分、命中证据与处置建议。

> 当前状态（复赛阶段）：HarmonyOS 6.0.2 工程已配置正式发布签名（AGC 发布证书 + Profile），可构建可安装到真机的签名 HAP；端侧已内置本地规则引擎与 17 个静态扫描器（PE/PDF/ZIP/宏/熵/IoC/哈希黑名单等），断网时 Code Guardian 与 Doc Shield 仍可完整工作。**新增「分享路径安全闸门」**：GuardianHub 已注册进系统分享面板，分享图片 / 文档 / 链接 / 文本时可直接选择「GuardianHub 隐私安检」，四条通道均支持「检测 → 决策 → 继续分享」。PC Web 四模块、项目 ZIP 扫描、历史记录和自动化测试均已跑通；后端新增 DeepSeek 隐私引擎（可选增强，默认关闭）。

## 分享路径安全闸门

GuardianHub 在 `module.json5` 中以 `ohos.want.action.sendData` 注册了 `ShareCheckAbility`，声明 9 类 UTD，因此在系统分享面板中可直接选中。内容先经过安检，再由用户决定是否继续分享：

| 通道 | 检测位置 | 决策后可做什么 |
| --- | --- | --- |
| 图片 | 后端 OCR + 二维码 | 三种打码生成安全图片 → **分享安全图片**，或**仍分享原图** |
| 文档 | **纯端侧** 扫描器矩阵（离线可用） | **继续分享文件**（源 URI 不可分享时回退沙箱副本） |
| 链接 | 后端静态检查（不访问目标） | **继续分享链接** |
| 代码 | **纯端侧** 规则引擎（离线可用） | **继续分享代码** |

按钮文案随风险变化（低风险「继续分享」/ 中高风险「已知晓风险，仍继续分享」），每次续接都写入本地历史。边界说明：这是**并列的分享目标**而非拦截器——HarmonyOS 未开放改写其他应用分享行为的能力，因此续接时由用户重新选择分享对象。

## 四个安全节点

| 操作节点 | 模块 | 已实现能力 |
| --- | --- | --- |
| 分享图片前 | Privacy Sentinel 隐私哨兵 | OCR、二维码与隐私规则检测，黑条/模糊/马赛克脱敏，导出安全图片 |
| 提交代码前 | Code Guardian 代码卫士 | 代码片段、单文件和项目 ZIP 静态扫描，文件级证据、行号与修复建议；端侧本地引擎离线可用 |
| 点击链接前 | Link Guard 链接卫士 | URL 与二维码内容静态检查，不主动访问目标地址 |
| 上传材料前 | Doc Shield 提交护盾 | PDF、DOCX、TXT、Markdown 的完整性、格式、命名与隐私检查；命名模板与要求解析已端内化 |

项目坚持“本地优先、联网可选”。核心规则、OCR、二维码解析和图像处理可在本机或自建后端运行；DeepSeek 与 Qwen VL 仅作为可选增强，默认关闭，只有用户主动选择联网模式并配置服务后才会调用。HarmonyOS 端在完全离线时仍可执行代码扫描、威胁检测与文档检查（端侧扫描器矩阵 + 本地规则引擎兜底）。

## 项目结构

```text
GuardianHub/
├── README.md
├── .github/workflows/ci.yml
├── tools/threat-tests/           # 威胁样本 fixture 生成与批量测试运行器
├── scripts/                      # 辅助启动脚本
└── platform/
    ├── harmony/                 # HarmonyOS 6 / ArkTS 客户端（含端侧扫描器矩阵）
    ├── frontend/                # React + Vite + TypeScript PC Web
    ├── backend/                 # FastAPI、检测引擎、SQLite 与测试
    ├── contracts/               # 前后端契约用例（requirement_cases.json）
    ├── samples/                 # 不含真实隐私的演示与验收样本
    ├── docs/                    # 介绍、接口、展示稿与能力说明
    ├── .env.example             # 后端配置示例
    └── README.md                # 开发与联调说明
```

## 快速运行

### 1. 启动后端

要求 Python 3.10 或更高版本。若要让 HarmonyOS 模拟器访问服务，后端必须监听 `0.0.0.0`。客户端默认请求端口 **8001**（`GuardianApi.ets` 中的 `API_BASE_URL`），启动后端时请保持一致：

```powershell
cd platform\backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8001
```

启动后可访问：

- 健康检查：`http://127.0.0.1:8001/api/health`
- Swagger API 文档：`http://127.0.0.1:8001/docs`

### 2. 启动 PC Web

Vite 8 要求 Node.js 20.19+ 或 22.12+。

```powershell
cd platform\frontend
npm install
npm run dev
```

浏览器打开 `http://127.0.0.1:5173`。PC Web 默认调用后端的 **8000** 端口（`privacyApi.ts`，可用 `VITE_API_BASE_URL` 覆盖）。

> **各端后端地址是分离的（有意设计）**：HarmonyOS 客户端默认 `10.0.2.2:8001`、PC Web 默认 `127.0.0.1:8000`，因为两者面向不同的运行环境——HAP 提交后评委端无法访问开发机本地后端，需要独立的公网服务；Web 端则由构建期注入地址。因此同时联调时请让后端同时监听 8000 与 8001。
>
> **出提交版 HAP 前必须改地址**：`GuardianApi.ets` 的 `API_BASE_URL` 会在编译期写入 HAP，`10.0.2.2` 仅模拟器可用，真机上无法解析。提交前需替换为已部署后端的公网 HTTPS 地址并重新构建；Web 端需在构建时注入 `VITE_API_BASE_URL`，否则产物会去连访问者自己的 `127.0.0.1`。

### 3. 打开 HarmonyOS 客户端

1. 启动 DevEco Studio，选择 **Open**。
2. 打开 `platform\harmony`，等待工程同步完成。
3. 启动 API 22 手机模拟器，选择 `entry` 模块后点击 **Run**。

也可以在 PowerShell 中构建：

```powershell
cd platform\harmony
.\build.ps1
```

HAP 输出到（配置发布签名后为 signed 包，可直接安装到真机）：

```text
platform/harmony/entry/build/default/outputs/default/entry-default-signed.hap
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

## 文档与材料

- [800 字项目介绍](platform/docs/初赛800字介绍.md)
- [完整项目介绍](platform/docs/项目介绍文档.md)
- [接口文档](platform/docs/接口文档.md)
- [鸿蒙能力说明](platform/docs/鸿蒙能力说明.md)
- [5 分钟展示文稿](platform/docs/展示.md)
- [初赛冲刺计划](platform/docs/2026鸿蒙高校创新赛初赛冲刺计划.md)
- [复赛差距诊断与提升路线](platform/docs/复赛差距诊断与提升路线.html)
- [演示样本说明](platform/samples/README.md)

## 源码压缩包建议

赛事若要求提交“项目源码”，建议提交整个项目，而不是只提交 `harmony/`。源码包至少保留：

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
