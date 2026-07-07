# GuardianHub

GuardianHub 是一个面向高校与个人数字生活场景的统一 AI 数字安全防护平台 Demo，而不是单一隐私工具。当前 PC Web 项目位于：

```text
platform/
```

## 平台定位

GuardianHub 以“分享前、转账前、点击前、提交前”为防护节点，整合四个安全模块：

- 隐私哨兵：图片分享前隐私检测、风险报告、原图/处理后对比和打码处理。
- 反诈雷达：聊天文本诈骗风险识别，输出风险证据与防骗建议。
- 链接卫士：URL 体检，检查 HTTPS、短链接、可疑关键词、异常域名、过长 URL、随机字符和可疑参数。
- 提交护盾：按“输入提交要求 + 上传材料 + 生成提交检查报告”的流程检查材料完整性、格式规范、隐私风险和提交建议。

所有模块统一使用 `high` / `medium` / `low` 风险等级、0-100 安全评分、卡片式 UI 和可解释报告。

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

当前版本不接入付费大模型 API，不强依赖复杂 OCR，优先保证本地 Demo 稳定运行。
