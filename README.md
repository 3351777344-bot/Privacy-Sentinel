# GuardianHub

GuardianHub 是面向高校场景的 AI 数字安全防护平台 Demo。当前 PC Web 项目位于：

```text
platform/
```

## 平台定位

GuardianHub 以“分享前、提交前、点击前、上传前”为防护节点，整合四个安全模块：

- Privacy Sentinel 隐私哨兵：图片隐私检测、风险报告、原图/处理后对比和打码处理。
- Code Guardian 代码卫士：面向学生项目、课程实验、竞赛作品和开源代码的轻量级代码安全风险检测。
- Link Guard 链接卫士：URL、短链接、二维码解析内容和来源场景的链接安全体检报告。
- Doc Shield 提交护盾：材料提交前的完整性、格式规范、隐私风险和提交建议检查。

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

当前版本不接入付费大模型 API，不引入复杂依赖，优先保证本地 Demo 稳定运行。

