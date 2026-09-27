# GuardianHub HarmonyOS 客户端

当前构建目标为 HarmonyOS 6.0.2 API 22。默认端侧处理，网络分析逐次授权。图片离线能力限于二维码解析，不包括完整 OCR；ZIP 扫描是受大小和深度限制的静态分析，不执行代码。

## 构建

调试：运行 `.\build.ps1`，输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`。脚本优先使用 DevEco CLI；未安装 CLI 时，通过 `DEVECO_HOME` 或未跟踪 `local.properties` 中的 `sdk.dir` 找到 DevEco Studio 自带的 Node、Hvigor 和 SDK。无需把个人安装路径写入仓库。

发布：**编译与签名是分开的两步**，完整步骤与口令格式要求见 [BUILD_AND_SIGN.md](BUILD_AND_SIGN.md)。要点是 `build-profile.json5` 保持 `signingConfigs: []`，hvigor 只产出 unsigned HAP，再由 SDK 自带的 hap-sign-tool（`tools/sign-hap.ps1`）完成本地签名。`build.ps1 -BuildMode release` 期望 hvigor 直接产出 `entry-default-signed.hap`，而签名被有意移出工程配置后这一步不会发生，因此它不能作为发布路径。

编译前需把生产后端地址写进 `services/ApiConfig.ets`；`build.ps1 -ApiBaseUrl` 会临时注入并在结束时还原。仓库里的默认值是模拟器用的 `http://10.0.2.2:8001`，**从源码直接构建出的包连不上生产后端**，演示用包必须显式注入 `https://api.guardianhub.tech`。

签名证书及私钥留在库外，Git 历史中的旧凭据必须轮换。未配置可信情报公钥时，端侧生产情报安装被拒绝；内置 EICAR 明确标为测试规则。

产物名与版本号无关：hvigor 按「模块-产品」命名为 `entry-default-unsigned.hap`，签名后为 `entry-default-signed.hap`，**文件名里没有版本号**；带 `GuardianHub-2.0.0-release-signed.hap` 这种名字的是打包/交付阶段按「应用名-versionName-构建模式-签名状态」重命名的结果。两者只是名字不同，包内容与签名有效性不受影响——判断包的身份请用 SHA-256（`tools/release-check.py --write` 生成清单），不要用文件名：交付目录里曾同时存在两个同名不同内容的 HAP。

构建产物里的 `versionName`/`versionCode` 只来自 `AppScope/app.json5`，且必须与发布 Profile 一致。

演示或真机验证用的包必须注入生产地址（见上一节）；也可以装好后从包内自证——HAP 是 zip，`ets/modules.abc` 里应当出现 `api.guardianhub.tech`，且不出现 `10.0.2.2:8001`。

## 安装与版本

包内 `versionCode` 必须与发布 Profile 一致（当前 2.0.0 / versionCode 2），否则真机安装会被签名校验拒绝。注意它低于早期开发版的 1000000：**已装过旧版的设备会把新包判为降级安装并拒绝**，需要先卸载，或去 AGC 用更大的 versionCode 重新签发 Profile。release 签名的包可直接安装到模拟器，这一点已在模拟器上验证。

当前没有连接真实设备，系统分享面板、相册授权与 Share Kit 交互仍须回归。编译通过和模拟器验证都不代替这三项。

## 联网额度与部署错配

四模块的联网路径都会消耗后端的模型额度，并计入限流（`/api/*` 600 次/60 秒，
模型端点 120 次/300 秒）。**默认的仅本地模式不消耗任何额度**；提交护盾的 online 模式
一次检查最多两次模型调用（解析要求 + 判定材料内容），实测单次 2–29 秒，
端侧读超时 150 秒留有余量。

部署是手工的，所以**客户端可能比线上后端新**，客户端据此做前向兼容判断：

- 提交护盾：响应里如果拿不到 `parsedRequirements.source`（既不是 `local` 也不是 `online`），
  就说明线上后端还不支持联网解析，页面明确提示，而不是把联网结果标成「服务端规则识别」
  ——后者正是本轮要避免的静默降级。
- 隐私哨兵：`detectorDetail` 字段缺失不是错误，只说明线上后端早于 `b7159fb`；
  该字段存在时才会显示联网失败原因。字段存在也正是判断线上是否已更新的最快依据。
