# GuardianHub 平台说明

GuardianHub 由 React + Vite + TypeScript 前端和 FastAPI 后端组成，是一个优先本地运行、强调可解释结果的高校数字安全 Demo。

## 已实现能力

1. Privacy Sentinel：RapidOCR 中文/英文文字识别、OpenCV 二维码定位、隐私正则分类、坐标标注、黑条/模糊/马赛克处理和处理前后对比。
2. Code Guardian：自动语言识别、文件后缀识别、多行上下文扫描、命中行号与修复建议。
3. Link Guard：协议与域名合法性、HTTPS、短链、IP/内网地址、Punycode、关键词、参数、随机 token、来源风险检查。
4. Doc Shield：PDF、DOCX、TXT、Markdown 内容提取，以及完整性、格式、命名和隐私检查。

四个模块使用统一风险等级与评分函数，检测历史统一保存到 SQLite，刷新页面后仍可查看。

## 目录

```text
platform/
├── backend/          FastAPI、检测器、规则、SQLite 存储和测试
├── frontend/         React + TypeScript 用户界面
├── docs/             项目与接口文档
└── .env.example      可配置的安全限制
```

## 启动与测试

```bash
cd backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

```bash
cd frontend
npm install
npm run dev
```

```bash
cd backend
python -m pip install -r requirements-dev.txt
python -m pytest
```

默认前端地址为 `http://127.0.0.1:5173`，后端地址为 `http://127.0.0.1:8000`。

## 设计边界

- OCR、二维码和规则检测都在本机运行，不调用付费大模型 API。
- Link Guard 只做静态分析，不访问用户输入的目标 URL，避免引入 SSRF 风险。
- 当前 Code Guardian 面向单文件和代码片段，还不是完整 SAST 或依赖漏洞扫描器。
- 图片检测不包含人脸识别；“未命中规则”不等于绝对安全，界面会保留人工复核提示。
- 固定演示框只能通过 `GUARDIANHUB_DEMO_MODE=true` 显式开启。
