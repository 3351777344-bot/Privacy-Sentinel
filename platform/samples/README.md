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

如后端不是默认地址，可传入 `-BaseUrl`。

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
