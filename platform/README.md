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
- `POST /api/doc/check`：提交材料检查
- `GET /api/history`：本地历史记录

完整字段见 [docs/接口文档.md](docs/接口文档.md)。

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

当前已接入系统图片/文件 Picker、四模块 API、ArkData 本地历史、处理图预览/系统保存与 Share Kit，已通过 ArkTS 编译并生成调试 HAP。模拟器此前已验证首页、四页面路由及 Link Guard 真实请求；新增保存、分享和历史能力仍需在完成模拟器许可确认后做交互验收。

详细环境和联调说明见 [harmony/README.md](harmony/README.md)。

## 环境配置

后端从 `platform/.env` 读取可选配置。首次使用可复制示例：

```powershell
Copy-Item .env.example .env
```

本地模式无需 API 密钥。DeepSeek 和 Qwen VL 默认关闭；不要把真实密钥写入 `.env.example` 或提交到 Git。

关键限制的默认值：

| 项目 | 默认限制 |
| --- | --- |
| 图片 | 10 MB、2500 万像素 |
| 单个代码文件 | 1 MB |
| 项目 ZIP | 10 MB、300 个条目、解压后 50 MB |
| 单个材料文件 | 10 MB |
| 单次材料 | 8 个文件、合计 25 MB |
| 本地产物保留 | 24 小时 |

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
