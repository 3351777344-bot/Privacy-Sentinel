# Privacy Sentinel 隐私哨兵

Privacy Sentinel 是一款“AI 隐私安全分享助手”，面向截图、聊天记录、快递单、订单页面、证件照片、校园材料等图片分享场景，在用户分享前主动检测隐私风险，并提供风险分级、一键打码、安全预览和分享建议。

## 当前阶段说明

当前版本是 PC Web Demo，用于初赛展示、功能验证和技术路线说明，不是最终 HarmonyOS / ArkTS / HAP 版本。复赛阶段可将前端体验迁移到 HarmonyOS 多端，并接入更真实的 OCR、二维码识别、人脸检测和端云协同能力。

## 功能列表

- 图片上传
- 隐私检测
- 风险分级
- 敏感区域标注
- 一键打码
- 安全预览
- 历史记录

## 技术栈

- 前端：React + Vite + TypeScript
- 后端：Python FastAPI
- 图像处理：Pillow
- 当前检测：mock 数据，保证本地 Demo 稳定运行

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

默认前端访问地址为 `http://127.0.0.1:5173`，后端地址为 `http://127.0.0.1:8000`。

## 后续计划

- OCR 真实识别
- 二维码检测
- 人脸检测
- HarmonyOS ArkTS 前端
- HAP 打包
- 手机、平板、手表多端协同
