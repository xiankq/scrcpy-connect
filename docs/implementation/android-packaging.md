# Android 打包、签名与安装

> 仓库打包工具入口在根目录，Flutter 应用在 `app/`；工具行为以 `tool/android.dart`、`app/android/` 工程和 [工具链契约](repository-tooling.md) 为准。本文同时保留各阶段签名、构建和 APK 摘要；下文“当前产物”只属于所在阶段，不能据历史构建推定当前代码或物理设备运行通过。

2026-10-18用户报告直接`flutter build apk`很慢，安装器显示英文的“包信息为空”。本批保持应用ID`dev.scrcpyconnect.scrcpy_connect`和中文名称“邻接”，补可更换的本机签名与真实安装验证，不把用户未提供的原APK当作已检查。

## 已复现的原因与修复

旧Gradle仅在`android/key.properties`存在时配置release签名；文件不存在仍让release构建成功。改动前x64 release真实构建86.773秒，日志`/tmp/connect-release-baseline.log`。SDK apksigner明确`DOES NOT VERIFY / Missing META-INF/MANIFEST.MF`；同一APK向主控实验AVD尝试安装，独立PackageManager拒绝`INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed to collect certificates ... Attempt to get length of null array`，原debug安装未被替换。这证明项目可产生该类不可安装包，不声称已读取用户原手机安装器日志。

现在release任务图在执行前校验签名配置，无配置实际8秒失败、仅4个已有Gradle任务up-to-date，未进入Flutter/Rust编译，`/tmp/connect-release-signing-guard.log`。`tool/android.dart init-signing`显式创建本机持久RSA3072/JKS身份、随机密码，`key.properties`及密钥权限600且Git忽略；重复执行保留原身份，不自动替换、不回退debug签名。现有配置示例可用于替换自有发布密钥。该生成身份用于当前本机侧载，尚未建立商店发布／远程密钥托管流程。

另一个真实缺陷是`--target-platform android-x64`仍包含ARM的fvp等插件库，却没有对应Flutter/Rust。当前Flutter3.47.6插件默认ABI过滤列表始终包括三架构；app默认配置现按请求平台收紧，`--split-per-abi`保持Flutter自身拆包路径。旧x64包73.9MB，新x64包50.2MB，实际检查只剩完整x86_64。新通用包保留完整三ABI。

## 构建速度与边界

开启Gradle本机任务缓存；日常入口默认只编译常见arm64，仍保留原生release优化、R8和资源裁剪，不以debug包替代release。未启用尚无兼容证据的configuration cache，未盲改Rust优化级别。Native hook依赖的Cargo release构建仍由FRB维护，冷构建不能视为热构建。

| 实际命令／状态 | 耗时与产物 |
| --- | --- |
| 改动前x64 release，清理过Gradle产物，native缓存仍有 | 墙钟86.773秒，Flutter assemble约32.3秒，Gradle缓存关闭、R8／资源输出缺失而重建；未签名，不可安装 |
| 修复后`dart tool/android.dart build --abi x64 --no-pub` | 墙钟63.32秒／Gradle62.5秒，50,218,157字节，ZIP／签名／manifest／启动入口／ELF／16KB ZIP对齐全部通过；不能把与上一行的差值全部归因缓存 |
| 修复后与用户相同`flutter build apk`，切回三ABI | 墙钟73.468秒／Gradle71.2秒，128,895,459字节，三个完整ABI全部验证 |
| 同源码再次`flutter build apk`，未clean | 墙钟10.760秒／Gradle9.1秒，产物SHA-256不变；属于增量构建证据，不保证任意改动／干净检出同样耗时 |
| 单架构正式入口`dart tool/android.dart build --no-pub`切到arm64 | 墙钟59.96秒／Gradle59.3秒，46,625,578字节，完整包检查通过；这次含切架构／从E2E切回main，不能与上行热构建直接比 |

日志依次`/tmp/connect-release-signed-x64-r1.log`、`/tmp/connect-release-default-signed.log`、`/tmp/connect-release-default-repeat.log`。构建时曾并行冷启动第三台软件渲染AVD，宿主可用内存降到2.9GiB／swap约7.1GiB；已停止多余AVD和确认IDLE的旧Gradle daemon，后续安装独立分时执行，不以这种资源争用作为正常编译基准。

arm64正式入口日志`/tmp/connect-release-arm64.log`，SHA-256`82bafbe09f8ca803e45204f3b49696e1946c04931ee4ff4135890986d5057cc2`。仅完整arm64-v8a，签名身份与通用包相同；没有以x64模拟器声称执行arm64。可安装原件留在`/tmp/connect-artifacts/connect-arm64-release.apk`，三架构包留在同目录的`connect-universal-release.apk`；中间构建产物按批清理，原件不随清理删除。实际release仍有Flutter提示未打包CupertinoIcons字体，该提示尚未定位到实际缺失图标，未因警告删除图标或关闭tree shaking。

## 实际签名、安装与启动

通用包SHA-256：`64ddf4277feaa788464c3b8131ecfdb74a0549f49cf0c4cf08c98696ce87c6b8`；公开签名证书SHA-256：`fa3aa1d220afce83e6b9cb467bb66ee6b1f8df5d9d380fa31394e843108461cd`。证书摘要不是私钥。`tool/android.dart verify`真实调用SDK的apksigner、aapt2、zipalign及ZIP／ELF读取，截断4KiB包负例被拒绝。工程Android门禁增加该验证，不仅相信Flutter“Built”输出。

在明确无已有产品安装的第三台API36 x64 AVD执行安装：`adb install /tmp/connect-artifacts/connect-universal-release.apk`成功；`am start -W`冷启动Activity成功、TotalTime3584ms，独立dumpsys确认前台MainActivity，实际截图`/tmp/connect-artifacts/release-installed.png`已目视为正常浅色设备列表。之后`adb install -r`同签名更新亦成功。实验后卸载本次安装并关闭该AVD，未卸载主控原debug应用，未更换其授权身份／数据。

这不是量产手机安装或arm64执行证据；它证明当前release签名、解析、x64安装／同身份更新、Flutter/FRB实际启动闭合。若原先装过不同证书的debug版本，Android仍会拒绝跨签名覆盖；需保留原密钥，或由用户明确处理旧安装及数据，脚本不自动卸载。

## 可复现入口与清理

仓库根目录，Flutter、JDK21在PATH，ANDROID_HOME指向SDK：

```sh
dart tool/android.dart init-signing
dart tool/android.dart build                 # arm64 release + 完整APK检查
dart tool/android.dart build --abi universal # 三架构通用包
dart tool/android.dart build --abi x64       # Android模拟器
dart tool/android.dart verify app/build/app/outputs/flutter-apk/app-release.apk
```

直接在 `app/` 运行 `flutter build apk`也使用相同签名与过滤。不要每次clean；清理调试过期build／Kotlin状态，保留仍复用的native hooks和Gradle缓存，最终安装包与必要验证证据可保留于/tmp。本批不把构建过程写入产品页面，也不上传私钥。

一手依据：[Flutter Android发布与签名](https://docs.flutter.dev/deployment/android)、[Gradle构建缓存](https://docs.gradle.org/9.3.1/userguide/build_cache.html)、[Android apksigner](https://developer.android.com/tools/apksigner)。实际Flutter默认ABI行为另按本机固定3.47.6的`FlutterPlugin.kt::configureAbiWithoutSplits`源码核查，未改SDK源。

最终清理已执行：普通main构建／R热重启并detach后，移除过期Gradle／Flutter中间产物、debug APK、Kotlin状态与Rust incremental；build目录仅保留最终arm64 APK及其摘要，实际45MiB，磁盘剩余78GiB。原先未跟踪的用户测试／examples未改动。复用native hooks 3.2GiB与Gradle缓存保留，不将必要缓存当垃圾全删；被删输出下次会按需恢复，10.760秒是清理前同源热构建实测。

## 媒体缓存批次后的实际release复验

新增缓存实现后，`dart tool/android.dart build`实际38.86秒（Gradle37.0秒）通过，当前arm64产物46,740,766字节，SHA-256 `a948e13cbd98c3552e4462415e9e964505b16c60d54e6e85c919be18242865e0`。签名证书仍为上述同一身份；ZIP完整性／16KB ZIP对齐／manifest／完整arm64 ELF均由工具复验。原件另存 `/tmp/connect-artifacts/connect-arm64-cache-release.apk`，与前一批A60原件区分；该包没有在物理arm64手机执行，不复用旧通用包的x64安装证据冒称当前ARM执行。

本轮还实际复现了Flutter3.47.6的构建模式注册问题：E2E留下integration_test的Java注册文件，随后`--no-pub` release在51.7秒时因`package dev.flutter.plugins.integration_test does not exist`失败。正常命令重新准备release插件注册后上述38.86秒成功。固定SDK源码`flutter_plugins.dart::injectPlugins`在release过滤dev依赖，`project.dart`的准备流程负责刷新；跳过准备不能假设注册文件仍匹配。更早一次进程以143中断，没有计作通过或签名失败。

打包脚本现在对该明确组合提前拒绝并提示移除`--no-pub`，不手改生成的Java文件、不改Flutter SDK、不把测试插件塞入正式包。公开脚本回归先红后绿，证明拒绝发生在执行Flutter之前；同模式热构建仍可使用`--no-pub`，但在E2E与release之间切换时应使用默认命令。`--no-pub`不是所有状态下的无成本加速开关。

## 视频性能批次的当前产物与缓存

`25c2ddc`/`d0215db`后，当前arm64签名release实际78.42秒通过，同模式`--no-pub`第二次4.64秒通过；两次APK摘要一致。不是把4.64秒解释成冷构建或三ABI构建时间。日志`/tmp/connect-video-latency-release.log`、`/tmp/connect-video-latency-release-warm.log`；ZIP/签名/manifest/完整arm64 ELF/16KB ZIP对齐均由脚本检查，证书身份与此前一致，没有重建scrcpy JAR。

产物另存`/tmp/connect-artifacts/connect-arm64-video-release.apk`，46,740,766字节，SHA-256 `506f80ff966bed5669640c66e397120a0a400b9a3271a5fa319b7f7ae657ffd9`。这是当前源码的ARM产物，未在物理ARM执行，不借用早期x64安装结果宣称当前包已上机。

清理时发现并修正筛选错误：Flutter的release缓存同样可能含`app.dill`，不能仅凭它判断debug目录。本批曾误清旧Dart AOT中间缓存，随后以上述当前release重建恢复有效缓存，旧成品/签名/Rust native hooks未受影响。后续仅按明确构建模式识别过期缓存；无法确认模式的hash目录应保留。实际清理406处、释放3345MiB，重建和热构建后空闲73.8GiB；记录`/tmp/connect-video-latency-cleanup.json`，保留当前release/Gradle/CMake/Rust缓存，不再全clean。

## 连接级启动优化与TCP恢复后的产物

`9542e05`/`25e9bac`后，当前arm64包65.03秒构建（Gradle63.9秒）、同模式`--no-pub`复验4.09秒，两次摘要一致；`/tmp/connect-catalog-release.log`及`/tmp/connect-catalog-release-warm.log`。签名证书仍为同一身份，ZIP完整性、manifest、arm64 ELF及16KB ZIP对齐通过。当前通用视频路径`/tmp/connect-artifacts/connect-arm64-video-release.apk`已更新为46,757,150字节、SHA-256 `f701f9690d5e00c4ee9ae23fcefb8c1e96e5c1f99a5a2540985d4309a3d759fb`；前一批`506f80ff...`包保留在`/tmp/connect-artifacts/connect-arm64-before-tcp-release.apk`。这是新源码的签名ARM产物，未在物理ARM执行。

本批仅按Core日志中的准确路径删除非视频测试可执行文件/对应incremental、旧Android测试二进制和debug APK，实际释放8259MiB，空闲65.0GiB。所有release/native hooks/CMake/Gradle与模式不明的Flutter hash缓存保留，闲置Gradle已停止；没有重新删除Dart AOT缓存。记录`/tmp/connect-catalog-cleanup.json`；scrcpy JAR未改、未重建。


## 原生视频持续交互优化后的产物

`a694b78`后，ARM64签名release实际63.53秒构建通过；`/tmp/connect-native-final-release.log`。现有身份不变，ZIP完整性、manifest、arm64 ELF、16KB ZIP对齐及签名均由脚本复验。当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节，SHA-256 `c9cc21d19df2b5d5ca726ad5b182854bbb5721a10fa06de0981e171e6f5a285f`。前一批f701f969…包另存`/tmp/connect-artifacts/connect-arm64-before-native-latency-release.apk`。这是当前ARM产物，未在物理ARM手机执行；本批双AVD E2E运行的是x64 debug，不能替代ARM安装测试。两个scrcpy JAR仍沿用既有摘要，没有重建。


同模式`--no-pub`复建22.59秒，APK摘要一致；`/tmp/connect-native-final-release-warm.log`。高于前批4.09秒，没有将不同批次增量时间当作继续加速的证据，也没有改签名/降低优化级别换速度。随后停止闲置Gradle并清理明确debug产物，释放1379.4MiB、剩余63.0GiB；release/native hooks/CMake/Gradle和无法判断模式的Flutter缓存保留。


## 捕获身份校验并行化后的产物

`657990c`后，ARM64签名release实际59.50秒构建通过，同模式`--no-pub`复建2.40秒且APK摘要一致。日志`/tmp/connect-cold-release.log`及`/tmp/connect-cold-release-warm.log`。当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节、SHA-256 `9411b4f9ab12a20c75d18c4ad0942e93b2d8a0fa024c391a7af6ef5a672a66ae`；签名证书身份、ZIP完整性、manifest、arm64 ELF及16KB ZIP对齐均由工具复验。前一批c9cc21d1…包另存`connect-arm64-before-cold-ownership-release.apk`。未在物理ARM运行，不以x64 AVD结果代替。冷构建含源码变更、缓存仍保留，2.40秒不能当作干净检出构建时间；JAR仍未重建。


本批所有构建/测试结束后停止闲置Gradle、清理明确debug及过期测试产物59处，释放1373.8MiB、空闲62.6GiB；保留有效release/native hooks/CMake/Gradle、当前视频测试和模式不明的Flutter缓存。原始证据及最终APK继续放/tmp，没有重新全clean。


## 合作暂停修复后的产物

`91ae381`后仅捕获扩展JAR因两项真实暂停缺陷重建；普通APK构建仍直接嵌入提交产物，
官方scrcpy JAR未改。当前ARM64签名release实际62.74秒、同模式--no-pub复建2.50秒，
摘要一致，日志`/tmp/connect-pause-release{,-warm}.log`。签名身份仍为原证书，ZIP完整性、
manifest、arm64 ELF及16KB ZIP对齐通过；另逐字节确认libinterop_bridge.so包含当前
`b46cd074…`完整捕获JAR，`/tmp/connect-pause-release-artifact.json`。x64 debug也单独确认。

当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节，SHA-256
`5ea20787311dec169eaed3a911b3a1c88eb7139947ff83de6e2190217e1fc9cb`。旧9411b4…包
另存`connect-arm64-before-pause-gate-release.apk`。未在物理ARM手机运行；本批动态压力
曾有MDK原生SIGABRT，仍须定位，不能把签名/整包验证或后续40循环成功称为稳定验收。

本批清理382处明确debug输出，实际释放1488.5MiB、空闲62.5GiB，
`/tmp/connect-pause-cleanup.json`；保留release/native hooks/Gradle/CMake及模式不明的
Flutter缓存。原始结果、目标线程栈、主控tombstone及对应MDK x64二进制均留/tmp。


## 显式异步解码后的arm64包（2026-10-18）

`24379bb`改为Android显式AMediaCodec async，`53bcf10`增加optin系统观测。首次集成
测试后直接`flutter build apk --release --target-platform android-arm64 --no-pub`在76.2秒
因GeneratedPluginRegistrant引用release未带入的integration_test而失败，未交付该结果。
既有tool/android.dart的no-pub保护已覆盖此状态；随后用其普通build入口重新生成注册，
47.36秒完成（Gradle45.9秒）。两次准备状态不同，不据此报告打包加速。

新原件`/tmp/connect-artifacts/connect-arm64-decoder-async-release.apk`，46920990字节，
SHA-256 `fc6db347d819e42abaa630b452f5a7f32edab8b82b2ed37b6ed39aa951f9d022`。同一证书身份，签名／manifest／
ZIP完整性／16KB对齐／完整arm64 ELF检查均通过。日志
`/tmp/connect-decoder-async-release{,-fixed}.log`、回执
`/tmp/connect-decoder-async-release-receipt.json`。这是实际ARM包构建验证，未上物理ARM，
不拿x64 debug的五编码及输入性能E2E替代ARM运行。两个scrcpy JAR未变、未重建。


首次配对候选修复`bb0b339`后arm64 release61.33秒完成；46,937,374字节，SHA-256
`cf23f8100f5166517cb299629a0c1cc0f412f4866463da56d5d406eccd64e577`，独立ZIP／签名／
manifest／arm64 ELF／16KB ZIP页对齐均通过，证书身份未变。保留
`/tmp/connect-artifacts/connect-arm64-pair-candidates-release.apk`，回执
`/tmp/connect-pair-candidates-release-receipt.json`；未做相同源码重复打包，也未在
物理ARM安装运行。此次Rust主控变化不需要重建scrcpy JAR，两份摘要均保持一致。
