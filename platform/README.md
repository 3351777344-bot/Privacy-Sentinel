# GuardianHub 平台说明

GuardianHub 是 React + Vite + TypeScript 前端、FastAPI 后端组成的本地 PC Web Demo。项目面向高校场景，把图片分享、代码提交、链接打开、材料提交四类高频风险整合进统一安全中心。

## 安全中心

首页展示：

- GuardianHub 项目介绍
- 今日安全评分
- Privacy Sentinel 隐私哨兵、Code Guardian 代码卫士、Link Guard 链接卫士、Doc Shield 提交护盾四个模块卡片
- 每个模块最近检测状态、风险等级和安全评分
- 最近安全检测历史

## 统一风险展示

前端统一风险组件位于 `frontend/src/components/RiskComponents.tsx`：

- `RiskBadge`：展示 `high` / `medium` / `low`
- `ScoreCard`：展示 0-100 安全评分
- `RiskReport`：展示风险等级、检测摘要、风险证据、建议操作
- `SuggestionList`：展示修改建议
- `HistoryTimeline`：展示历史检测记录

## 模块能力

1. Privacy Sentinel 隐私哨兵：保留图片上传、隐私检测、风险框标注、黑条/模糊/马赛克处理、处理前后对比和历史记录。
2. Code Guardian 代码卫士：支持粘贴代码或上传单个 `.py`、`.java`、`.js`、`.ts`、`.sql`、`.txt` 文件，检测硬编码密钥、SQL 注入、命令执行、路径穿越、弱加密、敏感日志、危险配置和 XSS。
3. Link Guard 链接卫士：支持 URL、短链接、二维码解析内容和来源场景输入，输出 HTTPS、短链、IP 直连、域名结构、URL 长度、关键词、参数、随机 token、仿冒域名和来源风险报告。
4. Doc Shield 提交护盾：按“输入提交要求 + 上传材料 + 生成提交检查报告”的流程，输出材料完整性、格式规范、隐私风险、提交建议和安全评分。

## 启动方法

后端：

```bash
cd backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

前端：

```bash
cd frontend
npm install
npm run dev
```

默认前端地址为 `http://127.0.0.1:5173`，后端地址为 `http://127.0.0.1:8000`。

## 设计约束

- 不接入付费大模型 API
- 不强依赖复杂 OCR 或二维码识别库
- 统一使用 `high` / `medium` / `low` 风险等级
- 统一输出 0-100 安全评分
- 保持卡片式、科技感、安全感、简洁清晰的视觉风格

