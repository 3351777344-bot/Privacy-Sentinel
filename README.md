# GuardianHub

GuardianHub 是面向高校场景的数字安全防护平台 Demo，当前 PC Web 项目位于：

```text
platform/
```

## 当前项目

- 后端：`platform/backend`
- 前端：`platform/frontend`
- 文档：`platform/docs`

旧 HarmonyOS 工程和历史运行文件已归档到 `_archive/`，不影响当前 PC Web Demo 启动。

## 平台模块

- Privacy Sentinel 隐私哨兵：图片分享前隐私检测与一键打码。
- Scam Radar 反诈雷达：聊天文本中的诈骗话术风险识别。
- Link Guard 链接卫士：URL 风险检测。
- Doc Shield 提交护盾：根据提交要求检查材料完整性、文件格式、命名规范，并识别文档隐私风险，生成提交前检查报告。

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
