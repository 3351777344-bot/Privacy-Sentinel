# GuardianHub：面向高校场景的 AI 数字安全防护平台

GuardianHub 是由单一 Privacy Sentinel 隐私哨兵升级而来的高校场景 AI 数字安全防护平台。Privacy Sentinel 继续作为平台中的隐私哨兵模块保留，平台整体扩展为覆盖图片分享、聊天反诈、链接访问和材料提交四类高频校园数字安全场景的安全中心。

项目当前是 PC Web Demo，使用 React + Vite + TypeScript 构建前端，FastAPI 提供本地接口，规则和 mock 数据保证离线稳定演示。

## 模块

1. Privacy Sentinel 隐私哨兵：图片分享前隐私检测与一键打码。
2. Scam Radar 反诈雷达：聊天文本 / 聊天截图 OCR 文本中的诈骗风险识别。
3. Link Guard 链接卫士：URL 和二维码解析链接的风险检测。
4. Doc Shield 提交护盾：作业、报名材料、报告提交前的隐私与格式检查。

所有模块统一使用 `high`、`medium`、`low` 风险等级。

## 当前能力

- 首页安全中心：四个功能卡片、平台介绍、今日安全评分、最近检测记录。
- Privacy Sentinel：保留完整图片上传、隐私检测、风险汇总、检测项列表、打码控制、处理后预览和历史记录能力。
- Scam Radar：支持输入聊天文本，通过规则识别验证码、转账、补贴中奖、紧迫话术、冒充身份、刷单兼职等风险。
- Link Guard：支持输入 URL，检查 HTTPS、短链接、可疑关键词和异常域名。
- Doc Shield：静态 / mock 页面，展示文件命名检查、隐私检查、材料清单检查。

## 技术栈

- 前端：React + Vite + TypeScript
- 后端：Python FastAPI
- 图像处理：Pillow
- 检测策略：本地规则 + mock 数据

## 启动方法

以下命令均以 `platform/` 为工作目录。

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

默认前端访问地址为 `http://127.0.0.1:5173`，后端地址为 `http://127.0.0.1:8000`。

## 后续计划

- 接入真实 OCR、二维码识别和人脸检测。
- 将 Scam Radar 扩展为聊天截图 OCR + 文本联合检测。
- 将 Link Guard 扩展为二维码图片解析。
- 将 Doc Shield 扩展为真实文件解析、格式检查和材料模板核验。
- 迁移到 HarmonyOS / ArkTS 多端体验。
