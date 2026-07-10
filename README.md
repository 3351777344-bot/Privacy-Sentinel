# GuardianHub

GuardianHub 是面向高校场景的本地数字安全防护平台 Demo。项目将风险检查前置到“分享前、提交前、点击前、上传前”，当前 PC Web 实现位于 `platform/`。

## 核心模块

- Privacy Sentinel 隐私哨兵：通过本地 OCR 与二维码检测识别手机号、证件号、银行卡号、邮箱、地址等敏感区域，并支持黑条、模糊和马赛克处理。
- Code Guardian 代码卫士：自动识别常见代码语言，检查硬编码凭据、SQL 注入、命令执行、路径穿越、弱加密、敏感日志、危险配置和 XSS。
- Link Guard 链接卫士：检查 HTTP/HTTPS 协议、域名、IP、短链、可疑参数、Punycode、来源场景等风险，不主动访问目标地址。
- Doc Shield 提交护盾：解析提交要求，检查材料完整性、格式、命名、隐私信息和提交风险。

所有模块统一输出 `high` / `medium` / `low` 风险等级、0–100 安全评分、命中证据和建议操作。检测以本地可解释规则为主，不会把用户材料发送给第三方模型 API。

## 本地启动

后端（首次安装会加入 RapidOCR 与 ONNX Runtime）：

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

- 前端：`http://127.0.0.1:5173`
- 后端：`http://127.0.0.1:8000`
- API 文档：`http://127.0.0.1:8000/docs`

## 安全与隐私

- 默认限制图片 10 MB、代码 1 MB、单个材料 10 MB、单次材料总计 25 MB。
- 上传图片会校验真实格式和像素尺寸，而不是只相信文件名或 MIME 类型。
- 原图、处理图和历史默认保留 24 小时；可通过 `platform/.env.example` 中的环境变量调整。
- CORS 默认只允许本地 Vite 地址。
- 历史记录使用本地 SQLite；上传文件和数据库均不会提交到 Git。
- 设置 `GUARDIANHUB_DEMO_MODE=true` 才会显式启用固定演示框，默认使用真实 OCR。

## 验证

```bash
cd platform/backend
python -m pip install -r requirements-dev.txt
python -m pytest

cd ../frontend
npm run build
```

仓库已配置 GitHub Actions，在推送和拉取请求时执行后端测试与前端构建。
