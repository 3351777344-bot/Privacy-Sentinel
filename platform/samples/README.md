# GuardianHub 演示样本

本目录只包含虚构数据，用于初赛演示和端到端验收，不包含真实个人信息或有效密钥。

## Privacy Sentinel

使用后端已有图片：

- `../backend/static/samples/privacy_sentinel_demo.png`
- `../backend/static/samples/privacy_sentinel_demo_qr.png`

## Code Guardian

`code-risky/` 包含刻意加入的安全问题。生成上传用 ZIP：

```powershell
.\build-samples.ps1
```

生成结果为 `generated/guardianhub-code-risky.zip`。脚本会覆盖同名生成物，`generated/` 不提交到 Git。

后端启动后，可以一次验收四模块接口：

```powershell
.\verify-api.ps1
```

如后端不是默认地址，可传入 `-BaseUrl`。脚本默认只跑本地规则路径（不花模型额度）；
要连带验收提交护盾的联网解析，加 `-OnlineDoc`，此时会显式带 `X-Guardian-Consent: explicit`
与 `processing_mode=online` 调两次模型：

```powershell
.\verify-api.ps1 -OnlineDoc
```

## Link Guard

推荐演示地址：

```text
http://xn--campus-login.example/login?redirect=payment&token=demo123456789
```

该地址只用于静态分析，GuardianHub 不会主动访问它。

## Doc Shield

提交要求：

```text
提交课程论文 PDF、封面和签字承诺书；文件名使用学号_姓名_课程名称；截止时间 2026 年 7 月 26 日 20:00。
```

上传 `doc-risky/` 中的文本文件，可以演示命名不规范、隐私信息和材料缺失提示。

同一份要求也能演示联网解析：`processing_mode=online` 时由模型读原文，除格式、命名、材料清单、
篇幅和截止时间外，还会读出只有模型能识别的**内容类要求**（例如「正文不少于 3000 字」
「需给出测试结论」），并逐条判定材料是否满足。`doc-risky/course-paper.txt` 正文只有 72 字、
没有结论也没有参考文献，正好让这些判定有确定的对照结果。对着真模型自检提示词用
`python tools/doc-intent-check.py`，对线上部署复验用 `analysis/verify-doc-online/`。
