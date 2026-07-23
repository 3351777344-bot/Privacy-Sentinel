# GuardianHub HarmonyOS

四模块 ArkTS 客户端工程，基于 DevEco CLI `1.2.0-stable` 自带的 HarmonyOS 6.0.2 模板结构创建。

## 当前实现

- 首页统一展示 Privacy Sentinel、Code Guardian、Link Guard、Doc Shield。
- Privacy 通过系统相册选择图片，并接入真实检测与脱敏接口。
- Privacy 提供“加载内置演示图”，保证空相册的模拟器也能稳定演示真实 OCR、二维码和隐私检测链路。
- Code 通过系统文件选择器上传 ZIP，并展示文件级项目扫描报告。
- Link 接入 URL 静态检查，并支持从系统相册选择二维码图片解析。
- Doc 支持系统多文件选择，并接入材料完整性、格式与隐私检查。
- 所有 Picker 授权 URI 都先通过 File Kit 受限读取，再以内存 multipart 上传。
- Privacy 处理图会下载到应用缓存并展示，可通过系统相册保存对话框落盘，也可调用 Share Kit 打开系统分享面板。
- 四模块真实检测结果通过 ArkData Preferences 保存在本机，首页展示检测次数、平均分、待复核数和最近记录。
- 工程已通过 ArkTS 编译，并成功生成未签名调试 HAP。

系统 Picker、四模块 API、ArkData、处理图保存和 Share Kit 均已在 HarmonyOS 6.0.2 手机模拟器完成真实交互回归。已验证 Link URL 检测、Code 本地规则与 ZIP 项目扫描、Doc 文件选择与检查、Privacy 演示图检测与脱敏，以及保存到系统相册和打开系统分享面板。

## 已验证环境

- Windows 11
- DevEco Studio `6.1.1.290`
- HarmonyOS SDK `6.0.2(22)`
- DevEco CLI `1.2.0-stable`
- 手机模拟器 `GuardianHub_API22`，HarmonyOS `6.0.2(22)`

本机 DevEco Studio 安装目录为 `E:\DevEcoStudio`。其他机器可以安装到默认目录，不要求使用相同盘符。

## 构建

在 PowerShell 中执行：

```powershell
.\build.ps1
```

脚本会把 npm 缓存隔离在工程的 `.cache` 目录，不修改全局 npm 设置。等价的原始命令为：

```powershell
devecocli build --product default --modules entry@default --build-mode debug
```

如果 PowerShell 提示找不到 `devecocli`，本机安装器的默认命令路径为：

```powershell
$devecoCli = "$env:LOCALAPPDATA\Programs\deveco-cli\devecocli.cmd"
& $devecoCli --version
```

首次启动模拟器前，必须在可交互终端阅读并接受 4 份许可：

```powershell
& $devecoCli emulator license accept
```

构建成功后，HAP 位于：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

当前产物未配置开发者签名。需要安装到真机或提交签名包时，请先在 DevEco Studio 中登录华为开发者账号，并在 `build-profile.json5` 配置自动或手动签名。

## 联调

鸿蒙端开发地址集中定义在：

```text
entry/src/main/ets/services/GuardianApi.ets
```

默认值 `http://10.0.2.2:8000` 用于手机模拟器访问开发电脑。联调前在电脑上启动 FastAPI：

```powershell
cd ..\backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

真机测试时，把 `API_BASE_URL` 改为电脑在同一局域网内可访问的 HTTPS 地址；不要使用 `localhost` 或 `10.0.2.2`。

已验证的模拟器运行命令：

```powershell
& $devecoCli emulator start GuardianHub_API22
& $devecoCli run --module entry@default --device 127.0.0.1:5555 `
  --product default --build-mode debug --ability EntryAbility
```
