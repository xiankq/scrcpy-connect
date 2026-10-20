# Android 打包、签名与安装

构建输入、目录和原生资源归[工具链契约](repository-tooling.md)，实现入口是 `tool/android.dart` 与 `app/android/`。本文件维护签名、ABI、插件准备及独立产物检查；历史包体对照不代表当前工作区已重新构建。

## 签名与ABI

release任务图在编译前校验本机签名配置。旧配置缺失仍构建成功的APK经apksigner拒绝，实际PackageManager报 `INSTALL_PARSE_FAILED_NO_CERTIFICATES`；这复现了项目可生成不可安装包，未声称读取用户原手机的安装日志。

`init-signing`创建本机持久RSA3072/JKS身份、随机密码及权限600的配置，Git忽略；重复执行保留原身份，不回退debug签名或自动替换。可配置用户已有密钥，尚不承担商店发布/远程托管流程。跨证书覆盖仍会被Android拒绝，工具不自动卸载旧应用和数据。

构建按实际请求平台过滤插件、Flutter和Rust的ABI，避免单x64包混入缺少完整engine/core的ARM插件库。通用包包括armeabi-v7a、arm64-v8a、x86_64，`--split-per-abi`遵循Flutter自身路径；检查真实ELF身份，不能仅看目录名称。

## 可复现入口

从仓库根运行，Flutter/JDK21在PATH、ANDROID_HOME指向SDK：

```sh
dart tool/android.dart init-signing
dart tool/android.dart build              # 通用release及独立检查
dart tool/android.dart build --abi arm64  # ARM64对照
dart tool/android.dart build --abi x64    # 模拟器对照
dart tool/android.dart verify app/build/app/outputs/flutter-apk/app-release.apk
```

直接在 `app/` 执行 `flutter build apk` 使用同一签名配置。默认压缩原生库以减小下载；`--no-compress-native`是直接加载的对照，安装后体积与下载大小分开。Gradle/原生编译缓存继续复用，冷构建、切架构/入口和同源热构建的耗时不相互当作加速证据。

独立验证调用SDK apksigner/aapt2/zipalign，并核对Manifest、ZIP条目/CRC、各ABI Flutter/Rust/AOT ELF、共享六资源及16KiB对齐；损坏、真正重复ZIP名、错误架构和来源漂移负例均应拒绝。构建显示Built不替代这些检查。来源见[Flutter发布](https://docs.flutter.dev/deployment/android)、[apksigner](https://developer.android.com/tools/apksigner)。

## 测试插件注册

Flutter在release准备中排除dev测试插件。集成测试后直接 `--no-pub` release曾因生成注册器仍引用integration_test而失败；反方向切debug也曾缺截图插件。正常构建/依赖准备会刷新自动注册，工具对已知不匹配状态提前拒绝并提示重新准备。

模式/入口切换时使用默认准备流程，不手改GeneratedPluginRegistrant、不把测试插件塞入正式包；同模式确认准备一致后才用 `--no-pub`。缺截图插件的失败不通过跳过截图或放宽媒体断言规避。

## 三架构包体对照

2026-10-19，基于8853d975工作区、Flutter3.47.6/Dart3.13.5、Rust1.99.1、SDK36/NDK28.2，三架构普通release在相同功能范围内测得：

| 配置 | APK字节 |
| --- | ---: |
| 原始基线 | 142854555 |
| 六执行资源共享压缩、去除无字幕用途libass，原生库直接加载 | 120699763 |
| 再压缩APK内原生库、安装时解压 | 58021419 |

下载减少59.38%；不代表解压代码或安装后总占用同幅减少。该最终历史包SHA-256为 `cd151f295d2816fa8d9f3b23c459b8005c58093a477b5dac294506bb4425566d`，不据同路径推定当前文件仍为它。原JAR/DEX/helper及四种被控ABI保留，FFmpeg codecs未裁减，fvp/MDK源码和缓存未修改。

该包独立签名/ZIP/资源/三ABI ELF验证通过，64位ELF的PT_LOAD至少16KiB；无libass必需依赖。API36/x64独立主控AVD实际安装/冷启，私有六文件与原输入相符，故意破坏本次缓存后冷启自动修复。

同资源和链接配置的debug集成入口另完成五编码实际首帧/暂停恢复/截图/停止和音频PCM/播放时钟。15秒首帧是功能期限，非性能预算；`audibleContentVerified`/`speakerSamplesVerified`保持false。未验证ARM32/ARM64实机媒体，也未构建其他宿主整包。

## 产物与清理

普通main、debug/profile集成夹具、不同ABI及签名模式分别记录身份。保留交付包和仍复用缓存，清理过期中间目录与重复包；不能仅凭`app.dill`或体积判断debug垃圾。来源归档/许可证是项目输入，不属于可重建产物。

各次源码变更后曾反复构建的ARM64包仅提供构建/签名证据，不能用旧x64运行推断它已上机。当前依赖升级后的构建范围见[升级记录](dependency-upgrade-2026-10-20.md)，工程与运行边界见[验证记录](validation.md)。
