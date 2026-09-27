# GuardianHub HarmonyOS 客户端

当前构建目标为 HarmonyOS 6.0.2 API 22。默认端侧处理，网络分析逐次授权。图片离线能力限于二维码解析，不包括完整 OCR；ZIP 扫描是受大小和深度限制的静态分析，不执行代码。

## 构建

运行 .\build.ps1。脚本优先使用 DevEco CLI；未安装 CLI 时，通过 DEVECO_HOME 或未跟踪 local.properties 中的 sdk.dir 找到 DevEco Studio 自带的 Node、Hvigor 和 SDK。无需把个人安装路径写入仓库。

默认输出 entry/build/default/outputs/default/entry-default-unsigned.hap，仅为未签名调试产物。

发布构建运行 .\build.ps1 -BuildMode release。必须先设置 GUARDIANHUB_API_BASE_URL 为 HTTPS 源地址，并在本地未跟踪的 build-profile.local.json5 中配置轮换后的签名。可从 build-profile.example.json5 复制结构后在本机配置。脚本临时应用发布配置并在结束后恢复受跟踪文件。

签名证书及私钥留在库外，Git 历史中的旧凭据必须轮换。未配置可信情报公钥时，端侧生产情报安装被拒绝；内置 EICAR 明确标为测试规则。

当前未连接真机，分享入口、权限对话框和实际设备安装仍须回归。编译成功不代替这些验证。详见 ../docs/验收报告.md。
