# Privacy Sentinel

隐私哨兵：基于 HarmonyOS 的 AI 安全分享助手

本项目是用于鸿蒙高校创新赛的 HarmonyOS ArkTS 前端静态原型。当前版本只包含页面、导航与 mock 数据，不接入后端，便于后续对接 FastAPI 检测服务。

## 页面

- 首页 `Index`
- 图片选择页 `ImageSelect`
- 检测结果页 `DetectResult`
- 打码编辑页 `EditMask`
- 安全预览页 `SafePreview`
- 历史记录页 `History`

## 目录结构

```text
PrivacySentinel/
├── AppScope/
│   └── app.json5
├── entry/
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   └── src/main/
│       ├── ets/
│       │   ├── components/
│       │   │   ├── AppHeader.ets
│       │   │   ├── MockPhoto.ets
│       │   │   └── RiskBadge.ets
│       │   ├── data/
│       │   │   └── MockData.ets
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets
│       │   ├── models/
│       │   │   └── PrivacyModels.ets
│       │   └── pages/
│       │       ├── DetectResult.ets
│       │       ├── EditMask.ets
│       │       ├── History.ets
│       │       ├── ImageSelect.ets
│       │       ├── Index.ets
│       │       └── SafePreview.ets
│       ├── module.json5
│       └── resources/
│           └── base/
│               ├── element/
│               │   ├── color.json
│               │   └── string.json
│               └── profile/
│                   └── main_pages.json
├── build-profile.json5
├── hvigorfile.ts
└── oh-package.json5
```

## 后续接入建议

- 在 `entry/src/main/ets/models/PrivacyModels.ets` 扩展接口字段，保持前后端数据结构一致。
- 将 `entry/src/main/ets/data/MockData.ets` 替换为 `services/DetectService.ets`，通过 HTTP 调用 FastAPI。
- 页面层只消费 `DetectResult`、`PrivacyItem`、`HistoryRecord`，减少后续改动面。

