# GuardianHub：面向高校场景的 AI 数字安全防护平台

当前主要运行和维护的 PC Web Demo 项目位于：

```text
platform/
```

该目录内包含 GuardianHub 平台的后端、前端、文档和项目级 README。Privacy Sentinel 保留为平台中的“隐私哨兵”模块名称：

```text
platform/
├── backend/
├── frontend/
├── docs/
└── README.md
```

外层目录仅作为仓库总目录使用。旧 HarmonyOS 工程和 Codex 运行临时文件已归档到 `_archive/`，不会影响当前 PC Web Demo 的启动和维护。

## 当前主项目

- 后端：`platform/backend`
- 前端：`platform/frontend`
- 文档：`platform/docs`
- 项目说明：`platform/README.md`

## 平台模块

- Privacy Sentinel 隐私哨兵：图片分享前隐私检测与一键打码。
- Scam Radar 反诈雷达：聊天文本 / 聊天截图 OCR 文本中的诈骗风险识别。
- Link Guard 链接卫士：URL 和二维码解析链接的风险检测。
- Doc Shield 提交护盾：作业、报名材料、报告提交前的隐私与格式检查。

## 归档目录

- `_archive/harmonyos-old/`：旧 HarmonyOS / ArkTS 工程文件。
- `_archive/codex-work/`：Codex 工作目录和本地运行日志。

## 启动命令

后端：

```bash
cd platform/backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

前端：

```bash
cd platform/frontend
npm install
npm run dev
```

默认访问地址：

- 前端：`http://127.0.0.1:5173`
- 后端：`http://127.0.0.1:8000`
