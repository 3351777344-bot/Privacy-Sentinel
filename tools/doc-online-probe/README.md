# 对已部署后端复验「提交护盾联网解析」的探针

这是一份**对着真实部署**跑的复验记录，不是单元测试。单元测试在
`platform/backend/tests/test_doc_intent.py` 里注入固定返回，验的是「模型调用周边的策略」；
这两个探针要回答的是另一层：线上那台机器上的提示词、合并逻辑与回退路径，
对着真模型是不是也这样。

复验时点：2026-09-28，线上 `https://api.guardianhub.tech` 已更新到含
`09d985b` / `94252d5` 的版本（用 `/api/detect` 是否返回 `detectorDetail` 判定部署进度）。

## 怎么跑

```powershell
# 中文输出：先把控制台编码设成 UTF-8，否则 Windows 控制台会把中文显示成乱码
$env:PYTHONIOENCODING = 'utf-8'
python tools/doc-online-probe/probe.py      # 五个用例：基线 / 联网 / 回退 / 授权 / 复跑
python tools/doc-online-probe/probe2.py     # 逐字段回退重试 + 限流额度

# 指向本地或预发后端（默认打生产）
$env:GUARDIANHUB_API_BASE = 'http://127.0.0.1:8001'
```

两个脚本都**只读**服务端：不写历史、不改数据。语料就在本目录
（`requirement-content.txt` / `requirement-vague.txt`），材料用
`platform/samples/doc-risky/course-paper.txt`；`probe.py` 也可以接一个目录参数从别处读语料。

## 语料的设计意图

| 文件 | 用来问什么 |
| --- | --- |
| `requirement-content.txt` | 要求里混入**只有模型能读出的内容类要求**（「正文不少于 3000 字」「需给出测试结论」「需包含参考文献列表」），规则表没有对应项 —— 用来验证模型真的读懂了原文，而不只是格式/命名 |
| `requirement-vague.txt` | 一句「随便交点东西就行」 —— 模型无从抽取字段，用来验证**逐字段回退**是否干净 |

`course-paper.txt` 正文只有 72 字、没有结论也没有参考文献，正好让内容判定有确定的对照依据。

## 实测结果（2026-09-28）

| 用例 | 结果 |
| --- | --- |
| ① `local` 基线 | HTTP 200，**0.2–0.6 秒**（无模型调用特征）；`source=local`、`sourceFields=[]`、`contentRequirements=[]`、`modelWarning=None`；10 项检查，与旧版一致 |
| ② `online` + 授权头 | HTTP 200，8–29 秒（同一次部署下波动较大）；`source=online`；`sourceFields` 列出 6 个字段；`contentRequirements` 读出三条内容类要求；并逐条判定（「正文不少于3000字」→ fail，依据「可解析正文仅72字」；另两条 → 需人工确认） |
| ③ 模糊要求 `online` | HTTP 200，1.6–2.4 秒；`source=local`、`sourceFields=[]`、`modelWarning=「联网解析未能从这段文字中识别出具体提交要求，已改用本地规则解析。」`；3 项检查，未被半成品字段污染 |
| ④ `online` 缺授权头 | HTTP **403**「联网模型分析需要本次明确授权。」，0.2 秒（未调模型）。注意 `probe.py` 走 `curl.exe`，偶发 `HTTP -1` / `curl 000` 是**客户端连接层**中断，不是服务端判定——重跑即可，这也是 `probe2.py` 改用标准库的原因 |
| ⑤ 复跑稳定性 | 结构稳定（字段与来源一致）；检查条数在 8–12 之间浮动，个别条目在 fail / 需人工确认之间摆动 |
| ⑥ 限流额度 | 连打 6 次 online 全部 HTTP 200，无 429 |

`/api/detect` 的 `detectorDetail` 随同一次部署上线，实测返回
`empty_result: 模型返回空结果（图片可能确无敏感内容，或本次未识别到）`——
即视觉调用**成功但模型没发现内容**，与「调用失败」在字段上可区分。

## 已知的不确定性（不要当成缺陷）

模型判定本身有抖动，所以**同一份输入的报告条数不固定**（8–12 项）。
代码把不确定的判定降级为「需人工确认」，这是设计选择而非缺陷；
演示时不要承诺固定条数，也不要把条数变化讲成回归。

## 这份探针**没有**覆盖的部分

端侧报告页的展示（来源徽标、「在线 AI 识别 / 服务端规则识别」前缀、联网提示文案）
无法用命令行点击验证，只能由设备上的人工操作确认。接口层字段正确由本探针保证，
文案层由 `tools/threat-tests/run-tests.mjs` 里「联网提示必须追加而非替换原文」的断言看守。
