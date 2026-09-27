# 构建、签名与发布清单

本文件说明如何从当前源码产出一份可交付的签名 HAP。适用于本机 Windows + DevEco Studio。

## 为什么分两步

DevEco 的 `build-profile.json5` 在配置签名时要求填它自己的**加密口令串**（长度 ≥ 32），
明文口令会被拒绝：

```
00303116 Configuration Error
The length of the storePassword or keyPassword field in the signature configuration is less than 32.
```

因此本项目把「编译」与「签名」拆开：

- hvigor 只负责编译出 `entry-default-unsigned.hap`；
- 签名交给 SDK 自带的 `hap-sign-tool.jar`（脚本 `tools/sign-hap.ps1`），明文口令不写入工程。

`platform/harmony/build-profile.local.json5`（被 `.gitignore` 忽略）保持 `signingConfigs: []`，
既满足 DevEco 的 schema，也让 `tools/release-check.py` 的口令检查保持通过。

## 一、编译

编译脚本会临时把生产后端地址写进 `ApiConfig.ets`，结束自动还原：

```powershell
cd E:\GuardianHub\platform\harmony
$env:DEVECO_SDK_HOME = 'E:\DevEcoStudio\sdk'
& 'E:\DevEcoStudio\tools\node\node.exe' 'E:\DevEcoStudio\tools\hvigor\bin\hvigorw.js' `
  --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap --no-daemon
```

> `build.ps1 -BuildMode release` 走的是 DevEco CLI，本机可能被
> `Ensure the project source is trustworthy before proceeding.` 拦住；
> 用上面的 hvigor 命令可以绕开该信任确认。
>
> 生产地址也可以用 `-ApiBaseUrl` 注入来改：当前固定为 `https://api.guardianhub.tech`。

产物：`platform/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`

## 二、签名

```powershell
cd E:\GuardianHub
& .\tools\sign-hap.ps1 `
  -StoreFile 'E:\GuardianHub-signing\guardianhub-release.p12' `
  -StorePassword '<keystore 口令>' `
  -ProfileFile 'D:\GuardianHubRelease.p7b' `
  -CertFile 'D:\GuardianHub.cer' `
  -InFile 'E:\GuardianHub\platform\harmony\entry\build\default\outputs\default\entry-default-unsigned.hap'
```

脚本会调用 SDK 的 `hap-sign-tool.jar sign-app -mode localSign`，输出
`entry-default-signed.hap` 并打印字节数与 SHA-256。成功的日志特征：

```
INFO - profile type is: release
INFO - Sign Hap success!
```

## 三、生成哈希清单

清单不入库（`*.hap` 被忽略，CI 在全新 checkout 上拿不到产物，入库会让 CI 失败）。
发布时在出包机器上生成，随交付物一起提供：

```powershell
python tools/release-check.py --write platform/harmony/entry/build/default/outputs/default/entry-default-signed.hap
```

它会打印每个产物的**实际**字节数与 SHA-256。`tools/release-check.py` 在清单存在时
会逐条复算校验和；清单不存在时只提示，不报错。

## 四、交付前自检

```powershell
python tools/release-check.py        # 配置无口令、清单一致、文档链接有效
```

## 五、安装验证（必做）

```powershell
$hdc = 'E:\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
& $hdc install -r "E:\GuardianHub\platform\harmony\entry\build\default\outputs\default\entry-default-signed.hap"
```

手机上若装过**不同证书**签名的旧版本，需先卸载再安装。

## 六、签名材料与口令

| 材料 | 位置 | 说明 |
| --- | --- | --- |
| keystore | `E:\GuardianHub-signing\guardianhub-release.p12` | 别名 `guardianhub`，ECC P-256 |
| 发布证书 | `D:\GuardianHub.cer` | AGC 签发 |
| Provision Profile | `D:\GuardianHubRelease.p7b` | type=release，不限设备 |
| CSR | `E:\GuardianHub-signing\GuardianHubRelease.csr` | 申请证书时用，留档 |

口令只存在于出包机器上。**不要**写入任何受 Git 跟踪的文件；`build-profile.local.json5`
已被忽略，必要时可临时使用。历史提交 `363b88d` 曾包含明文口令，按仓库 README 的
说明在正式发布前完成轮换。
