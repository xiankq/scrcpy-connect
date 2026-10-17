# Android 打包、签名与安装

2026-10-18用户报告直接`flutter build apk`很慢，安装器显示英文的“包信息为空”。本批保持应用ID`dev.scrcpyconnect.scrcpy_connect`和中文名称“邻接”，补可更换的本机签名与真实安装验证，不把用户未提供的原APK当作已检查。

## 已复现的原因与修复

旧Gradle仅在`android/key.properties`存在时配置release签名；文件不存在仍让release构建成功。改动前x64 release真实构建86.773秒，日志`/tmp/connect-release-baseline.log`。SDK apksigner明确`DOES NOT VERIFY / Missing META-INF/MANIFEST.MF`；同一APK向主控实验AVD尝试安装，独立PackageManager拒绝`INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed to collect certificates ... Attempt to get length of null array`，原debug安装未被替换。这证明项目可产生该类不可安装包，不声称已读取用户原手机安装器日志。

现在release任务图在执行前校验签名配置，无配置实际8秒失败、仅4个已有Gradle任务up-to-date，未进入Flutter/Rust编译，`/tmp/connect-release-signing-guard.log`。`tool/android.py init-signing`显式创建本机持久RSA3072/JKS身份、随机密码，`key.properties`及密钥权限600且Git忽略；重复执行保留原身份，不自动替换、不回退debug签名。现有配置示例可用于替换自有发布密钥。该生成身份用于当前本机侧载，尚未建立商店发布／远程密钥托管流程。

另一个真实缺陷是`--target-platform android-x64`仍包含ARM的fvp等插件库，却没有对应Flutter/Rust。当前Flutter3.47.6插件默认ABI过滤列表始终包括三架构；app默认配置现按请求平台收紧，`--split-per-abi`保持Flutter自身拆包路径。旧x64包73.9MB，新x64包50.2MB，实际检查只剩完整x86_64。新通用包保留完整三ABI。

## 构建速度与边界

开启Gradle本机任务缓存；日常入口默认只编译常见arm64，仍保留原生release优化、R8和资源裁剪，不以debug包替代release。未启用尚无兼容证据的configuration cache，未盲改Rust优化级别。Native hook依赖的Cargo release构建仍由FRB维护，冷构建不能视为热构建。

| 实际命令／状态 | 耗时与产物 |
| --- | --- |
| 改动前x64 release，清理过Gradle产物，native缓存仍有 | 墙钟86.773秒，Flutter assemble约32.3秒，Gradle缓存关闭、R8／资源输出缺失而重建；未签名，不可安装 |
| 修复后`python3 tool/android.py build --abi x64 --no-pub` | 墙钟63.32秒／Gradle62.5秒，50,218,157字节，ZIP／签名／manifest／启动入口／ELF／16KB ZIP对齐全部通过；不能把与上一行的差值全部归因缓存 |
| 修复后与用户相同`flutter build apk`，切回三ABI | 墙钟73.468秒／Gradle71.2秒，128,895,459字节，三个完整ABI全部验证 |
| 同源码再次`flutter build apk`，未clean | 墙钟10.760秒／Gradle9.1秒，产物SHA-256不变；属于增量构建证据，不保证任意改动／干净检出同样耗时 |
| 单架构正式入口`python3 tool/android.py build --no-pub`切到arm64 | 墙钟59.96秒／Gradle59.3秒，46,625,578字节，完整包检查通过；这次含切架构／从E2E切回main，不能与上行热构建直接比 |

日志依次`/tmp/connect-release-signed-x64-r1.log`、`/tmp/connect-release-default-signed.log`、`/tmp/connect-release-default-repeat.log`。构建时曾并行冷启动第三台软件渲染AVD，宿主可用内存降到2.9GiB／swap约7.1GiB；已停止多余AVD和确认IDLE的旧Gradle daemon，后续安装独立分时执行，不以这种资源争用作为正常编译基准。

arm64正式入口日志`/tmp/connect-release-arm64.log`，SHA-256`82bafbe09f8ca803e45204f3b49696e1946c04931ee4ff4135890986d5057cc2`。仅完整arm64-v8a，签名身份与通用包相同；没有以x64模拟器声称执行arm64。可安装原件留在`/tmp/connect-artifacts/connect-arm64-release.apk`，三架构包留在同目录的`connect-universal-release.apk`；中间构建产物按批清理，原件不随清理删除。实际release仍有Flutter提示未打包CupertinoIcons字体，该提示尚未定位到实际缺失图标，未因警告删除图标或关闭tree shaking。

## 实际签名、安装与启动

通用包SHA-256：`64ddf4277feaa788464c3b8131ecfdb74a0549f49cf0c4cf08c98696ce87c6b8`；公开签名证书SHA-256：`fa3aa1d220afce83e6b9cb467bb66ee6b1f8df5d9d380fa31394e843108461cd`。证书摘要不是私钥。`tool/android.py verify`真实调用SDK的apksigner、aapt2、zipalign及ZIP／ELF读取，截断4KiB包负例被拒绝。工程Android门禁增加该验证，不仅相信Flutter“Built”输出。

在明确无已有产品安装的第三台API36 x64 AVD执行安装：`adb install /tmp/connect-artifacts/connect-universal-release.apk`成功；`am start -W`冷启动Activity成功、TotalTime3584ms，独立dumpsys确认前台MainActivity，实际截图`/tmp/connect-artifacts/release-installed.png`已目视为正常浅色设备列表。之后`adb install -r`同签名更新亦成功。实验后卸载本次安装并关闭该AVD，未卸载主控原debug应用，未更换其授权身份／数据。

这不是量产手机安装或arm64执行证据；它证明当前release签名、解析、x64安装／同身份更新、Flutter/FRB实际启动闭合。若原先装过不同证书的debug版本，Android仍会拒绝跨签名覆盖；需保留原密钥，或由用户明确处理旧安装及数据，脚本不自动卸载。

## 可复现入口与清理

仓库根目录，Flutter、JDK21在PATH，ANDROID_HOME指向SDK：

```sh
python3 tool/android.py init-signing
python3 tool/android.py build                 # arm64 release + 完整APK检查
python3 tool/android.py build --abi universal # 三架构通用包
python3 tool/android.py build --abi x64       # Android模拟器
python3 tool/android.py verify apps/connect/build/app/outputs/flutter-apk/app-release.apk
```

直接在apps/connect运行`flutter build apk`也使用相同签名与过滤。不要每次clean；清理调试过期build／Kotlin状态，保留仍复用的native hooks和Gradle缓存，最终安装包与必要验证证据可保留于/tmp。本批不把构建过程写入产品页面，也不上传私钥。

一手依据：[Flutter Android发布与签名](https://docs.flutter.dev/deployment/android)、[Gradle构建缓存](https://docs.gradle.org/9.3.1/userguide/build_cache.html)、[Android apksigner](https://developer.android.com/tools/apksigner)。实际Flutter默认ABI行为另按本机固定3.47.6的`FlutterPlugin.kt::configureAbiWithoutSplits`源码核查，未改SDK源。

最终清理已执行：普通main构建／R热重启并detach后，移除过期Gradle／Flutter中间产物、debug APK、Kotlin状态与Rust incremental；build目录仅保留最终arm64 APK及其摘要，实际45MiB，磁盘剩余78GiB。原先未跟踪的用户测试／examples未改动。复用native hooks 3.2GiB与Gradle缓存保留，不将必要缓存当垃圾全删；被删输出下次会按需恢复，10.760秒是清理前同源热构建实测。
