# GuardianHub 平台说明

GuardianHub 是由 Privacy Sentinel 扩展而来的统一 AI 数字安全防护平台。当前版本是 React + Vite + TypeScript 前端、FastAPI 后端的本地 PC Web Demo，优先保证比赛演示和本地运行稳定。

## 安全中心

首页已升级为“安全中心”，展示：

- GuardianHub 项目介绍
- 今日安全评分
- 隐私哨兵、反诈雷达、链接卫士、提交护盾四个模块卡片
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

1. 隐私哨兵：保留图片检测和打码能力，新增原图/处理后对比、检测报告，以及“只处理高风险、处理全部、自定义选择”三种策略。
2. 反诈雷达：输出风险等级、风险证据和防骗建议，识别诱导转账、高额回报、催促决策、脱离平台、隐瞒他人、可疑链接等风险类型。
3. 链接卫士：输出链接体检报告，检查 HTTPS、短链接、可疑关键词、异常域名、URL 过长、随机字符和可疑参数。
4. 提交护盾：按“输入提交要求 + 上传材料 + 生成提交检查报告”的逻辑，输出材料完整性、格式规范、隐私风险、提交建议和安全评分。

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
- 不强依赖复杂 OCR
- 统一使用 `high` / `medium` / `low` 风险等级
- 统一输出 0-100 安全评分
- 保持卡片式、科技、安全、简洁的视觉风格
