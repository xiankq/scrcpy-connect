# 依赖升级记录（2026-10-20）

对象：本次工作区，在 [ADB 性能修复回归](adb-performance-2026-10-19.md)之后升级依赖。核对时间为北京时间 2026-10-19 至 20 日；版本结论是该时间的上游快照。Flutter SDK 由使用者升级，本次没有执行 `flutter upgrade`；验证时使用 Flutter 3.47.7、Dart 3.13.5、Rust 1.99.1、Linux x86_64、JDK 21。

## 实际升级

版本以升级前后的锁文件及受控构建输入为准，不将仅提高 manifest 下限记为已安装版本变化。

| 范围 | 原版本 → 本次版本 |
| --- | --- |
| Rust ADB / Core | base64 0.22.1 → 0.23.1；mdns-sd 0.21.2 → 0.21.6 |
| Rust 密码接口 | aes 0.8.4 → 0.9.3；aes-gcm 0.10.3 → 0.11.1；curve25519-dalek 4.1.3 → 5.0.0；hkdf 0.12.4 → 0.13.0；sha2 0.10.9 → 0.11.1；x509-cert 0.2.5 → 0.3.0 |
| Rust 测试与接口桥接 | 测试随机数改用 rand 0.10.3；新增 signature 3.0.0 元数据接口；Core 显式依赖 hex 0.4.3 |
| Rust 传递依赖 / 独立助手 | cc 1.8.0 → 1.9.0；find-msvc-tools 0.1.14 → 0.1.15；libc 0.2.190 → 0.2.191（含独立助手锁文件） |
| Dart | archive 3.6.1 → 4.5.2；shelf 1.4.2 → 1.4.3；新增 archive 所需 posix 6.5.2 |
| Android 应用与 JAR 构建 | AGP 9.1.0 → 9.4.1；Gradle 9.3.1 → 9.8.1；Kotlin 2.4.0 → 2.4.21；desugar_jdk_libs / configuration 2.1.4 → 2.1.5 |
| 被控产物构建输入 | Build Tools 36.0.0 → 37.0.0；D8/R8/L8 9.1.31 → 9.4.24；助手 NDK 28.2.13676358 → 30.0.16248370 |

其余直接依赖也核对了注册表。FRB runtime / hooks / codegen 与 Cargo 均保持已是最新版的 2.13.0，fvp 保持社区原版 0.39.1，scrcpy 保持已是最新的 5.0.1；Node 官方 DESIGN.md 解析器保持 0.4.0，`npm update --package-lock-only --ignore-scripts` 无锁文件差异。RSA 0.9.10、rustls 0.23.46、Tokio 1.53.3 等升级前已解析到这些版本，部分 manifest 仅同步最低要求。

## 上游约束与保留项

本次未添加 `dependency_overrides`、修改 pub 缓存或强行混用不兼容的密码 trait。

| 保留项 | 依据与影响 |
| --- | --- |
| build_runner 2.16.2、build 4.0.11、build_config 1.3.3 | 最新 build_runner 2.17.1 需要 build 5；最新 go_router_builder / riverpod_generator 仍约束 build < 5。build_runner 2.17.0 和 build 4.1.0 已被上游撤回，不能作为中间升级方案。 |
| cross_file 0.3.5+5 | 最新 file_picker / share_plus 仍依赖 0.3 系列，0.4.0 无法统一解析。 |
| qr 3.0.2 | 最新 qr_flutter 4.1.0 仍依赖 qr 3，不能直接换成 qr 4。 |
| material_color_utilities 0.13.0、test_api 0.7.12 | 验证时 Flutter SDK 精确锁定；SDK 升级后需重新解析、检查生成与测试。 |
| sha1 0.10.7 | 最新稳定 RSA 0.9.10 的 ADB AUTH 签名需要 digest 0.10；sha1 0.11 的接口不兼容。RSA 的 SHA-256 签名也沿用其重新导出的旧 digest 接口。 |
| 旧密码传递依赖 | rustls-rustcrypto / RSA 仍需要旧 aes、sha2、rand_core 等；它们与新版本在锁文件并存不代表主调用路径未升级。 |
| rustls-rustcrypto 0.0.2-alpha | 原有指定 provider 没有更新发布；保持原有版本和验证策略，不改换 TLS provider。 |

`flutter pub outdated --json` 在成功升级后仅报告上表中的七个 Dart 包有更新但不可解析。riverpod_analyzer_utils 的现有开发版由上游生成器要求，不能因其稳定版版本号较低而回退。

Dart 依据为 [build_runner 发布元数据](https://pub.dev/api/packages/build_runner)、[build 发布元数据](https://pub.dev/api/packages/build)、[go_router_builder](https://pub.dev/api/packages/go_router_builder)、[riverpod_generator](https://pub.dev/api/packages/riverpod_generator)、[file_picker](https://pub.dev/api/packages/file_picker)、[share_plus](https://pub.dev/api/packages/share_plus) 和 [qr_flutter](https://pub.dev/api/packages/qr_flutter) 的官方包约束。Rust 版本和 trait 依赖来自 crates.io sparse index 及本机下载的对应发布包源码。

## 兼容性与来源链

archive 4 的 API 迁移覆盖构建、APK 检查、交付与服务端打包工具。新版 `decodeBytes(verify: true)` 不再自动校验 CRC，且解码后的文件列表会合并同名项。因此 APK 与 vendor 的 ZIP 输入检查均在原始 header 层拒绝重复名，逐条验证实际解压数据 CRC，并要求 central/local CRC 一致。APK 现有的 `.duplicate` 文件测试并不是真正的同名 ZIP，新增测试覆盖两个同名条目各自 CRC 正确、第二份内容相同或不同的情况。损坏数据、单侧 CRC、两侧一致但错误 CRC 均有回归；vendor 候选 JAR 的本地 CRC 损坏也已覆盖。这两个遗漏均先实际复现旧检查接受，再确认修复拒绝，并经独立只读复核。符号链接继续拒绝，含空链接目标；存储 ZIP 的字节结构不变。

SHA-256 的新接口不再提供原有十六进制格式化，Core 统一用 `hex::encode` 保持小写输出，设备身份、授权指纹、缩略图缓存与部署摘要格式不变。x509-cert 0.3 使用官方 builder，加一个私有元数据适配器连接稳定 RSA 签名器；不手写证书 ASN.1 编码。新增测试检查 serial、CN、有效期、SPKI、扩展顺序/critical 标志/内容，并验证真实 RSA 签名；原有 AEAD / SPAKE2 向量继续运行。

NDK r30 的实际 API 下限由 [固定 r30 元数据](https://android.googlesource.com/platform/ndk/+/refs/tags/ndk-r30/meta/platforms.json)确认，四个助手按 API 21 重建，并检查 ELF Android ident 为 21。JAR 的 minApi 21 与 compileSdk/targetApi 36 保留；应用平台版本继续继承 Flutter，不随工具版本提升被控最低系统。desugar 2.1.5 的对应源码归档、许可证、输入摘要及构建清单随构建链更新。来源及重建入口仍以 [vendor](../../servers/vendor/README.md)、[companion](../../servers/companion/README.md)、[helpers](../../servers/helpers/README.md) 为准。

AGP 与工具版本依据为 [Google Maven](https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml)、[Gradle 发布记录](https://gradle.org/releases/)、[Kotlin Gradle 兼容表](https://kotlinlang.org/docs/gradle-configure-project.html)。Kotlin 2.4.21 文档中的完整支持上限低于这次最新 AGP/Gradle 组合，因此是否可用需要以下实际构建结果，不能仅凭解析成功判断。

## 验证回执

| 验证 | 结果 |
| --- | --- |
| `cargo test --workspace` | 391 passed、0 failed、72 ignored，含文档测试 |
| 严格 Clippy、Rust 格式、ADB 无默认 feature 编译 | 全部退出 0 |
| 应用 / 桥接层 / 设计系统 Flutter 测试 | 分别 373 / 148 / 28 项全过 |
| `flutter test --no-pub tool/test tool/e2e/tests` | 58 项全过，含真实同名 ZIP、CRC 与来源漂移检查 |
| Flutter 全仓静态分析、最后 ZIP 改动的定向分析 | 均无问题 |
| `dart tool/generate.dart --check` | 压缩资产、FRB 2.13.0 Rust/Dart、build_runner 均通过，无生成漂移；DESIGN.md 官方解析器保留原有 68 项警告 |
| 服务端 tooling / package 回归及最终 package `--check` | 全过，覆盖固定 ZIP 字节、CRC、重复项、链接/路径、六资源摘要及只读漂移检查 |
| vendor / companion / helpers 重建 | 全过；vendor 从全新源码目录重建逐字节一致，四 ABI helper 重建也一致 |
| helper 宿主与 companion 旧 API 夹具 | helper 7 项通过，companion API 21/23/30/31 签名与生命周期检查通过；scrcpy API 21 探针编译通过 |
| Node | 生成器 4 项测试通过，官方 lint 退出 0，锁文件无变化 |
| Android 应用 | Gradle 9.8.1 配置及普通 `lib/main.dart` 三 ABI debug APK 实际构建通过；ZIP/CRC、Flutter/Rust ELF、六资源、签名、16 KB 对齐与 Manifest 独立核验全过；三 ABI `libfvp.so` 均无 `libass.so` 必需依赖 |

ZIP 校验补强后再次更新 vendor manifest 并重建；scrcpy JAR 仍为 2,954,916 字节，SHA-256 `8b17b95193943be3ce16682d0ca69890a7f4078d87a4f8c61afc2a4dff620d8b`。manifest 来源摘要与当前构建器一致。

最终 [Android APK](/home/xiankq/git/scrcpy-connect/app/build/app/outputs/flutter-apk/app-debug.apk) 为 137,219,824 字节，SHA-256 `9c7740d909f3790a59d9fd5a7974b9c8c2cd82f96831be0e91bc42b05a5539e8`，包含 armeabi-v7a、arm64-v8a、x86_64。`flutter build apk --debug --no-pub --target-platform android-arm,android-arm64,android-x64` 退出 0，Gradle 阶段耗时 813.7 秒，含新版 Flutter 引擎的首次下载。独立验证命令为 `dart tool/check_android.dart`，回执在 `android-apk-receipt.json`；原生播放器库的必要依赖和实际分发字节摘要另记 `android-native-links.log`。保留此普通 debug APK，已删除相同字节的 Gradle 中间 APK；没有覆盖或删除既有 release APK。

日志目录为本机临时验收产物 `/tmp/connect-dependency-upgrade-lzxfg3va/`，主要日志：`workspace-tests.log`、`clippy.log`、`app-tests.log`、`bridge-tests-final.log`、`flutter-tools-tests-final.log`、`generate-check-final.log`、`android-build.log`。早期的助手资源尚未重打包导致的测试失败，已在资源同步后完整重跑通过。首次 APK 构建与配置检查并行，因 Gradle 项目锁超时退出；后续单独构建，不修改锁超时门槛。

默认主机测试、受控产物重建、Android APK 构建与真实设备运行是不同证据层级。本次没有将 ignored 设备测试、未运行宿主、实机吞吐或长时间稳定性记为通过；也没有将当前 Flutter 的验证结果外推到使用者后续升级的 SDK。升级依赖本身不能作为 ADB 实机性能改善的证据。
