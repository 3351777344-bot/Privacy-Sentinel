# GuardianHub 平台说明

GuardianHub 是由 Privacy Sentinel 扩展而来的高校数字安全防护平台。当前版本是 React + Vite + TypeScript 前端、FastAPI 后端的本地 PC Web Demo，优先保证比赛演示稳定运行。

## 模块

1. Privacy Sentinel 隐私哨兵：图片分享前隐私检测与一键打码。
2. Scam Radar 反诈雷达：基于本地规则识别聊天文本中的验证码、转账、补贴中奖、冒充身份、刷单兼职等诈骗风险。
3. Link Guard 链接卫士：检查 URL 的 HTTPS、短链接、可疑关键词和异常域名。
4. Doc Shield 提交护盾：用户输入材料提交要求并上传一个或多个文件，系统解析要求，检查材料完整性、格式与命名规范，并识别文件文本中的手机号、身份证号、银行卡号、地址等隐私风险，生成提交前检查报告。

所有模块统一使用 `high`、`medium`、`low` 风险等级。

## Doc Shield 当前能力

- 支持提交要求解析：文件格式、命名规则、必需材料、字数/页数要求、截止时间。
- 支持读取 `txt`、`md`、`pdf`、`docx`。
- 对 `png`、`jpg`、`zip` 等暂不解析内容的文件，仍检查文件名、后缀和上传状态。
- 不接入付费大模型 API，不强依赖 OCR。

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

## 使用示例

在 Doc Shield 中输入课程论文提交要求：

```text
请于 2026年7月20日 18:00 前提交 PDF 文件，命名规则为 学号-姓名-课程论文。材料需包含封面、摘要、正文、参考文献；正文不少于3000字。
```

上传课程论文 PDF 后，系统会检查：

- 文件是否为 PDF。
- 文件名是否大致符合“学号-姓名-课程论文”。
- 文档内容是否包含封面、摘要、正文、参考文献。
- 是否存在手机号、身份证号、银行卡号、地址等隐私风险。
- 输出总体风险等级、提交安全评分和修改建议。
