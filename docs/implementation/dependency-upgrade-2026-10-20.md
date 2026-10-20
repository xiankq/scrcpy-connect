# 依赖升级记录（2026-10-20）

对象：本次工作区，在协议/持久化回归后升级依赖，结果归[验证记录](validation.md#协议与持久化回归)。核对时间为北京时间 2026-10-19 至 20 日；版本结论是该时间的上游快照。Flutter SDK 由使用者升级，本次没有执行 `flutter upgrade`；验证时使用 Flutter 3.47.7、Dart 3.13.5、Rust 1.99.1、Linux x86_64、JDK 21。

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

当次核对还覆盖其余直接依赖；下述“最新”仅指2026-10-19至20日注册表快照。FRB runtime / hooks / codegen 与 Cargo 均保持已是最新版的 2.13.0，fvp 保持社区原版 0.39.1，scrcpy 保持已是最新的 5.0.1；Node 官方 DESIGN.md 解析器保持 0.4.0，`npm update --package-lock-only --ignore-scripts` 无锁文件差异。RSA 0.9.10、rustls 0.23.46、Tokio 1.53.3 等升级前已解析到这些版本，部分 manifest 仅同步最低要求。

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

## 验证范围

升级后的workspace测试、严格Clippy/格式、ADB无默认feature、Flutter应用/桥接/设计系统/工具测试、分析与token/FRB/builder生成检查通过。ZIP真实重名、损坏CRC、来源漂移与链接/路径负例覆盖于工具回归；没有把旧的 `.duplicate` 不同名样本当作重复条目证明。

vendor/companion/helpers重建通过；vendor在全新源码目录逐字节一致，四ABI helper也一致。固定API21/23/30/31的Java签名/生命周期夹具及scrcpy API21探针编译通过，不替代各系统设备运行。

同轮实际构建普通 `app/lib/main.dart` 三ABI debug APK，独立核对ZIP/CRC、签名、16KiB对齐、Manifest、Flutter/Rust ELF、六共享资源及libfvp无libass必需依赖。升级记录只证明该工作区/Flutter3.47.7组合可构建；未覆盖物理设备、其他主控整包、实机吞吐或长稳，ignored条件仍按各测试声明。

重复APK和过期中间输出按[产物边界](repository-tooling.md#构建与产物边界)处理；来源、许可证和对应源码仍保留。具体运行证据层级见[验证记录](validation.md)，不把依赖升级视为ADB实机性能改善。
