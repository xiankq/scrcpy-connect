# ADB 依赖链尽量纯 Rust：候选、边界与验证缺口

研究日期：2026-10-16。范围为独立 Rust ADB 主机库；当前实施平台为 Android，未来保留 Windows、macOS、iOS 适配路径。依据 [ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md) 与 [ADR 0004](../adr/0004-local-controller-authorization-identity.md)：用户偏好整个 ADB 依赖链尽量纯 Rust，未绝对禁止原生例外；主控授权身份默认不自动迁移，但尚未选定 Keystore。本文不改变完整功能范围，也不把媒体播放器、Flutter 引擎或被控设备临时 JAR 纳入 ADB crate 的依赖纯度承诺。

方法：先查 Context7 的 rustls、nusb 文档，再核对作者仓库、发布 crate 清单与源码、AOSP 和平台文档。Context7 的 rustls 主分支已出现 0.24 开发接口，因此最终以固定 0.23 源码为准。本次未安装工具、运行 Cargo、编译或做真机测试；“可组合”均不是已验证发布方案。

**后续访谈更新：** Q32 用户未确定严格纯度口径，强调四端都必须可编译。因此下文的纯度分层是分析工具，不是用户已接受的硬约束；跨端构建需实际验收，尚未通过。Q33 要求主控始终不启用调试；本文的 Android 系统 USB 授权和 Keystore 候选不要求主控调试，不能与已否决的本机 ADB 路线混淆。

## 1. 先区分三个口径

| 口径 | 含义 | 本次事实判断 |
| --- | --- | --- |
| 项目源码采用 Rust | ADB 协议与主机服务由 Rust 实现，允许依赖 native 库 | 两个候选均符合，但不足以满足“整个依赖链尽量纯 Rust” |
| 不随 ADB 库构建或分发 C/C++/手写汇编实现 | 正常目标依赖与启用 feature 不拉入 ring、AWS-LC、libusb、zstd-sys 等；平台接口可通过 Rust 声明调用 | 有候选组合，必须修改现有库的 provider/后端边界；密码学成熟度、压缩接入和实际目标依赖图尚未通过验收 |
| 不调用任何平台原生 API | 连系统 socket、USB、Keystore、JNI 等也不调用 | 与 Android USB 授权、系统密钥和普通联网运行的目标不相容；这是与源码语言不同的要求 |

Rust 写的 JNI/WinUSB/IOKit 声明不等于捆绑 C 实现；反过来，一个全是 `.rs` 的 crate 仍可能调用系统库或包含 `asm!`。`build.rs`、`*-sys` 名称本身也不能证明含 C。Rust 标准库与编译器生成机器码不能被解释为违背“无手写汇编”。[JNI 源码](https://github.com/jni-rs/jni-rs/tree/v0.22.4)、[nusb 平台后端](https://github.com/kevinmehall/nusb/tree/c80218d342740321190436bc45304ebbbf16bef0/src/platform)、[rustix 后端说明](https://github.com/bytecodealliance/rustix#implementation)

## 2. 可直接选型的矩阵

“可关”指 Cargo feature 能真正去掉依赖；Cargo feature 是叠加的，调用方 `default-features = false` 不能撤销上游明确启用的 `ring`。[Cargo feature unification](https://doc.rust-lang.org/cargo/reference/features.html#feature-unification)

| 部分 | 已有 Rust 候选 | 当前 native 来源／实际差距 | 保留完整能力的路线 |
| --- | --- | --- | --- |
| ADB 核心、AUTH、流复用、服务 | libadb 0.5.0；DroidMux 0.1.0 工作区 | 协议本体不是 C 瓶颈；两者完整度仍需按 AOSP 服务矩阵验收 | 复用或 fork Rust 核心，补齐服务与协议行为，不从语言选择推导“已完整” |
| TLS | rustls 0.23.46 + 自定义 CryptoProvider | rustls 默认 AWS-LC；两个 ADB 候选显式 ring；rustls-rustcrypto 自称不适合生产 | 修改上游 feature 和配置构造；独立验证纯 Rust provider；或日后由用户明确接受受控例外 |
| SPAKE2 配对 | 两个候选已有 BoringSSL 兼容变体 Rust 源码 | 通用 SPAKE2 不自动兼容；测试向量不等于安全审计 | 复用特定变体并做 AOSP 双向互操作与安全审查，无证据要求必须 FFI |
| USB | nusb；Android UsbManager 授权 FD | libadb 可选 nusb；DroidMux 用 vendored libusb；nusb 不提供 iOS 后端 | Android JNI 获取授权 FD，交 nusb；DroidMux 增加 transport 后端；未来平台分别适配 |
| mDNS | mdns-sd | Rust UDP 实现仍依赖系统 socket/组播授权；libadb 未集成发现 | 与连接核心组合，补 Android 组播锁和本地网络权限；保留手动地址与 IPv6 scope |
| Brotli | brotli 9.0.0 | 有 Rust 编码和解码 | 对 AOSP sync 双向验证 |
| LZ4 | lz4_flex 0.14.0 | 有 Rust frame 编码和解码；不要误接 block API | 使用 frame API，验证流收尾与错误处理 |
| Zstd | ruzstd 0.9.1；Avarok zstd-rs 0.1.0 | 前者已有编码器但 I/O panic/取消接口需处理；后者尚无流式 API；DroidMux 现用 zstd-sys | 替换完整编码和解码路径并验证大文件、并行内存和异常；不能靠关闭 Zstd 达成“完整” |
| Android API 桥 | jni 0.22.4 | 不要求 bundled C shim；仍调用 ART/系统 API | 平台适配层持有 Context、权限与 FD/密钥生命周期，协议层不依赖 Flutter |

候选固定源码：libadb [`bc681df`](https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5)；DroidMux [`9adeb62`](https://github.com/poapoauu/DroidMux/tree/9adeb6258166e9b88808bc6e67845c73763f070c)。服务范围及完整度清单见 [ADB 主机与连接研究](adb-host-and-connectivity.md)，本文不以替换依赖为由缩小该范围。

## 3. 已证事实：两个候选不能靠关闭默认 feature 就变成全链纯 Rust

### libadb

固定源码的默认 feature 为 `tokio`；`nusb`、`rusb`、`keys`、`tls`、`pairing` 分开。`tls` 需要 keys/split，`pairing` 又需要 TLS。`rustls` 依赖虽然关闭默认 feature，却明确启用 `std, ring, logging`；`TlsClientConfig::adb` 也直接构造 ring provider。另有 `from_rustls` 配置入口，可以作为自定义 provider 接口基础，但不修改 Cargo 声明就仍编译 ring。[Cargo.toml](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/Cargo.toml)、[TLS config](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/tls/config.rs)

身份构造使用 RustCrypto RSA、PKCS#8 和 x509-cert；未因自签证书必然引入 rcgen/ring。USB 已提供接收 `nusb::Interface` 的 transport；因此 Android 授权 FD 到 nusb 的路线可与它衔接，尚未在本项目编译或真机验证。sync 协议支持不等于已经完成全部压缩流封装。[identity](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/tls/identity.rs)、[nusb transport](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/transport/nusb.rs)

### DroidMux

默认 feature 含 tcp、pairing、shell、sync；`full` 还加入 package/logcat/screenshot/control/forward/usb/mdns。workspace 的 rustls、tokio-rustls、rcgen 显式启用 ring；USB 的 rusb 启用 vendored，sync 直接依赖 Brotli/LZ4/Zstd。其 Zstd 是 gyscos 的 `zstd` C 绑定路径。禁用 pairing/sync/USB 会损失所要求能力，不能作为完整产品的纯 Rust 解法。[工作区 Cargo](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/Cargo.toml)、[sync Cargo](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-sync/Cargo.toml)、[transport Cargo](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-transport-usb/Cargo.toml)

`control` 还可能引入 ffmpeg；应先明确该模块是否属于本项目独立 ADB 库的复用边界，不能把协议核心对媒体解码器的非必要耦合带入新库。[features 与可选依赖](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux/Cargo.toml)

两仓库锁文件出现 cc/ring/libusb1-sys 等；DroidMux 另有 zstd-sys/ffmpeg-sys。但锁文件包括可选和开发依赖，不能据此断言每个目标都会构建它们。上述确定结论来自启用路径和源代码，而非仅搜索锁文件。[libadb lock](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/Cargo.lock)、[DroidMux lock](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/Cargo.lock)

## 4. 已证事实：纯 Rust 密码学有实现路径，发布成熟度尚未闭合

### TLS provider 与原生依赖

检索时 rustls 最新稳定版为 **0.23.46**，发布源码标记 `f04804fa13341a9b1dc02b5d1dd8a746f2c4b7fb`；0.24.0-dev.2 是开发版。0.23.46 默认启用 AWS-LC 与其 sys/prebuilt-nasm；ring 是另一可选 provider。关闭默认 feature 并显式传入 CryptoProvider 是支持的扩展点，rustls 本体没有强制只能使用这两者。[发布元数据](https://crates.io/api/v1/crates/rustls)、[固定 Cargo](https://github.com/rustls/rustls/blob/f04804fa13341a9b1dc02b5d1dd8a746f2c4b7fb/rustls/Cargo.toml)、[CryptoProvider](https://docs.rs/rustls/0.23.46/rustls/crypto/struct.CryptoProvider.html)

ring 使用源自 BoringSSL 的 C/汇编；aws-lc-rs 的 sys 层调用 AWS-LC。它们采用 Rust API，不符合“不随库构建或分发 C/C++/手写汇编实现”的严格口径。[ring](https://github.com/briansmith/ring)、[aws-lc-rs](https://aws.github.io/aws-lc-rs/)

**rustls-rustcrypto 发布版 0.0.2-alpha** 的包源码是 `838ca01f655335badaec8bbcf0bd03c090da9b92`；当前 HEAD 为 `70f76c039e587192688af18a80d5d6435dedaf22`，不能当作同一发布物。发布版使用 rustls ^0.23、RustCrypto AES-GCM、ChaCha、X25519/ECDSA/RSA，含 TLS 1.3 常用套件及 RSA-PSS 签名。HEAD 已换入多项密码学预发布依赖；追 HEAD 不是已证明的生产升级路径。[发布 Cargo](https://github.com/RustCrypto/rustls-rustcrypto/blob/838ca01f655335badaec8bbcf0bd03c090da9b92/Cargo.toml)、[RSA signer](https://github.com/RustCrypto/rustls-rustcrypto/blob/838ca01f655335badaec8bbcf0bd03c090da9b92/src/sign/rsa.rs)、[HEAD Cargo](https://github.com/RustCrypto/rustls-rustcrypto/blob/70f76c039e587192688af18a80d5d6435dedaf22/Cargo.toml)

上游 README 明确写出 **“DO NOT USE THIS IN PRODUCTION”**。这足以否定“选中它即可宣布生产安全”，但不能推出纯 Rust TLS 不可能。rustls 核心的安全审计不能覆盖任意外部 provider；某些 RustCrypto AEAD 原语接受过审查，也不等于这套 provider、RSA、SPAKE2 与本项目组合获得整体审计。[provider README](https://github.com/RustCrypto/rustls-rustcrypto/blob/70f76c039e587192688af18a80d5d6435dedaf22/README.md)、[rustls security](https://github.com/rustls/rustls/security)、[NCC 对指定 AEAD 实现的报告](https://www.nccgroup.com/research/public-report-rustcrypto-aesgcm-and-chacha20pluspoly1305-implementation-review/)

版本接合也未验证：alpha 发布清单仍直接使用 webpki 0.102，近期 rustls 0.23 使用 0.103 系列。不能因为 semver 都属于 rustls 0.23 就跳过 provider 编译/API 和验证算法互操作检查；本文没有断言两者一定不兼容。[alpha 依赖](https://github.com/RustCrypto/rustls-rustcrypto/blob/838ca01f655335badaec8bbcf0bd03c090da9b92/Cargo.toml)、[rustls workspace 依赖](https://github.com/rustls/rustls/blob/f04804fa13341a9b1dc02b5d1dd8a746f2c4b7fb/Cargo.toml)

### SPAKE2 不能按名称替换

AOSP 使用 BoringSSL 的 Edwards25519 SPAKE2 变体，并结合 TLS exporter、特定角色名、HKDF 与 AES-GCM。libadb 与 DroidMux 都有对应 Rust 实现和兼容向量，故**没有证据表明配对必须链接 BoringSSL**；同样没有证据表明任意标准 `spake2` crate 可直接替代。应复用现有兼容实现并审查、验证，不能为追求纯 Rust 自行设计密码协议。[AOSP pairing](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_auth/pairing_auth.cpp)、[BoringSSL 变体](https://android.googlesource.com/platform/external/boringssl/+/refs/heads/android17-release/src/crypto/curve25519/spake25519.cc)、[libadb 实现](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/pairing/spake2.rs)、[DroidMux 实现](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-pairing/src/crypto.rs)

### RSA、Keystore 与风险适用路径

传统 AUTH 对已经收到的 20 字节 SHA1 摘要做 PKCS#1 v1.5 签名，必须包含正确 DigestInfo；不能对 token 再调用一次 SHA1withRSA，也不能使用 RSA-PSS 默认值代替。TLS 1.3 的 RSA 身份签名则需要 PSS，两套 signer 行为要分开。[AOSP AUTH](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/auth.cpp)、[rustls PSS signer](https://github.com/RustCrypto/rustls-rustcrypto/blob/838ca01f655335badaec8bbcf0bd03c090da9b92/src/sign/rsa.rs)

RustSec 的 RUSTSEC-2023-0071 截至本次查询仍标“无修复版本”，明确包括 rsa 0.9.10 与 0.10.0-rc.18；内容涉及可观测的非恒定时间私钥运算。**不能由此直接写成 ADB 必然泄露私钥**：必须检查实际调用的是解密、PKCS1 签名、PSS 签名还是仅公钥验证，以及攻击者能否反复观察该路径。[advisory 与跟踪链接](https://rustsec.org/advisories/RUSTSEC-2023-0071.html)

若主控授权身份的私钥操作全部交给 Android Keystore 外部 signer，RustCrypto 只处理 RSA 公钥/验证，则不能把该私钥 timing 风险直接套在这条路径上；仍需核查证书自签、AUTH、TLS client-auth 是否任何一步又回到软件私钥。provider 的上游生产成熟度警告也仍存在，不会因换 signer 自动消失。这是调用路径推论，尚未完成本项目安全审查。

Android Keystore 私钥不可导出，两个候选默认接收私钥材料的 builder 不能直接使用它。rustls 的 SigningKey/Signer 与 CertifiedKey 提供外部 signer 扩展点；Android provider 提供 NONEwithRSA/PKCS1 与 PSS 实现。候选路线是 AUTH 使用正确 DigestInfo 的 raw RSA 签名，TLS 使用 PSS，并完成证书生成；各设备的 DIGEST_NONE、PSS 参数、硬件能力与调用线程仍需 POC。此路线可做到“不捆绑 C 密码库”，却使用系统密码 API，不能称“所有密码运算都由 Rust 执行”。[Keystore](https://developer.android.com/privacy-and-security/keystore)、[Android RSA Signature SPI](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android17-release/keystore/java/android/security/keystore2/AndroidKeyStoreRSASignatureSpi.java)、[rustls SigningKey](https://docs.rs/rustls/0.23.46/rustls/sign/trait.SigningKey.html)

## 5. 已证事实：USB 与 JNI 可以不捆绑 libusb，但仍需要平台权限

nusb **0.2.8** 固定源码 `c80218d342740321190436bc45304ebbbf16bef0` 提供 Linux/Android `Device::from_fd(OwnedFd)`；libadb 当前使用的 nusb **0.1.14** 同样有该能力，不能把升级到 0.2 误写为 Android 支持的必要条件。nusb 的 Android/Linux 后端使用 Rust usbfs/ioctl 封装，Windows 用 WinUSB，macOS 用 IOKit；不是 libusb 的 Rust 包装。[0.2.8 Device](https://github.com/kevinmehall/nusb/blob/c80218d342740321190436bc45304ebbbf16bef0/src/device.rs)、[0.1.14 Device](https://github.com/kevinmehall/nusb/blob/c4415cb2684ae98e7a2c432b00f2482dc6dae5c8/src/device.rs)、[平台与依赖](https://github.com/kevinmehall/nusb/blob/c80218d342740321190436bc45304ebbbf16bef0/Cargo.toml)

Android 普通 App 仍须经 UsbManager 请求用户授权；UsbDeviceConnection 公开 FD 供 native 代码访问。Java 端返回的 FD 不是自动转让所有权，不能未经设计就用 `OwnedFd::from_raw_fd` 接管：需要复制 FD 或明确单一持有者，并验证连接关闭、接口 claim、取消及拔线时序。Rust direct usbfs 不绕过 Android 权限。[USB host 流程](https://developer.android.com/develop/connectivity/usb/host)、[getFileDescriptor](https://developer.android.com/reference/android/hardware/usb/UsbDeviceConnection#getFileDescriptor())

JNI 0.22.4 默认不启用 JVM invocation；Rust 通过已有 JNIEnv 函数表调用 ART，不需要额外 C shim。所检包无 cc 构建路径；它不消除 Java/Kotlin 侧权限 UI、生命周期与 Context 管理。[jni Cargo](https://github.com/jni-rs/jni-rs/blob/5ae9458a4ec44c5318f37ddc7569c1d4ae8a69e7/crates/jni/Cargo.toml)、[jni build.rs](https://github.com/jni-rs/jni-rs/blob/5ae9458a4ec44c5318f37ddc7569c1d4ae8a69e7/crates/jni/build.rs)

平台差异需保留：Windows WinUSB 涉及被控设备接口驱动匹配；macOS 用系统 IOKit 接口；nusb 当前没有 iOS 后端。Apple 的 USBDriverKit 文档适用特定 iPad/M 系列环境，不能据此承诺 iPhone 普通 App 的通用 USB ADB 主控路径。未来 iOS TCP 路线与 USB 路线应分开验收。[nusb 平台支持](https://github.com/kevinmehall/nusb/tree/c80218d342740321190436bc45304ebbbf16bef0/src/platform)、[Apple iPadOS DriverKit](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)

还需核对手写汇编口径：rustix 在 Android 走 libc 后端，在部分 Linux 目标可走含 inline asm 的 raw syscall 后端；RustCrypto SHA 的 `asm` feature 也应与默认/force-soft 路径区分。无需 C 编译不等于整个跨平台 feature 闭包没有 `asm!`。[rustix](https://github.com/bytecodealliance/rustix#implementation)、[sha1 features](https://docs.rs/crate/sha1/0.10.6/features)、[sha2 features](https://docs.rs/crate/sha2/0.10.9/features)

## 6. 已证事实：mDNS 的 Rust 实现不能替代系统网络授权

mdns-sd **0.21.5**，固定源码 `a25148c4d7adea836316dac2eca6c5bbdd79aa15`，通过 Rust UDP socket 实现 DNS-SD，不要求外置 Bonjour daemon。清单使用 socket2、mio、if-addrs、socket-pktinfo 等平台接口；所检正常依赖没有 C 实现构建项，仍须对最终目标闭包复核。[源码与清单](https://github.com/keepsimple1/mdns-sd/tree/a25148c4d7adea836316dac2eca6c5bbdd79aa15)

Android Wi-Fi 默认组播过滤可能影响原始 UDP 接收，须管理 MulticastLock 与 CHANGE_WIFI_MULTICAST_STATE；Android 17 target 37 的本地网络权限也覆盖本地 socket 活动。NsdManager 的系统服务行为不能直接当作 mdns-sd 原始 socket 已获相同待遇的证据。发现失败需要区分权限、网络接口和无设备。[MulticastLock](https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock)、[本地网络权限](https://developer.android.com/privacy-and-security/local-network-permission)、[NsdManager](https://developer.android.com/reference/android/net/nsd/NsdManager)

未来 iOS 原始 multicast 有 entitlement/本地网络隐私约束；系统 Bonjour 是另一可替换发现后端。发现层不应阻断手动 IP、IPv6 带 scope 地址与可达跨网连接，也不能把已配对设备等同当前在线。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## 7. 已证事实：三种 sync 压缩均有 Rust 编解码候选，Zstd 接入仍有工程缺口

| 算法／固定版本 | 编码 | 解码 | 当前需要验证的差距与来源 |
| --- | --- | --- | --- |
| brotli 9.0.0，`a51b65e` | 有 | 有，依赖 brotli-decompressor | std 流封装、增量 flush/finish 与 AOSP 互操作；`ffi-api` 是导出 ABI 选项，不等于 C 实现。[源码](https://github.com/dropbox/rust-brotli/tree/a51b65e75f68e3485be12bc816118e523e95647d) |
| lz4_flex 0.14.0，`1bffdcbb` | 有 FrameEncoder | 有 FrameDecoder | 保留 `frame`；ADB 需要 frame 协议，不能只用 block 压缩。[源码](https://github.com/pseitz/lz4_flex/tree/1bffdcbbf906a234b913937cb2f57c0245915038) |
| ruzstd 0.9.1，`aa145e87` | **有** FrameCompressor | 有 StreamingDecoder | 0.8 起已有编码，不应继续称“仅解码”。编码器逐块读写，但 `compress()` 内对 Read/Write 使用 unwrap，返回值不能表达 I/O 失败；网络断线/取消不能直接传播成 panic。[编码源](https://github.com/KillingSpark/zstd-rs/blob/aa145e8757c6982aab6a8336d3bba43d1a4c6fae/ruzstd/src/encoding/frame_compressor.rs)、[发布历史](https://github.com/KillingSpark/zstd-rs/releases) |
| Avarok zstd-rs 0.1.0，`bac4c37` | 有 | 有 | 纯 Rust、无正常依赖；目前一次性整帧 API，尚无流式 Read/Write。大文件不能简单整文件缓冲后声称满足多任务目标。[源码](https://github.com/Avarok-Cybersecurity/zstd-rs/tree/bac4c37d86e5307537c145823a106f7ed8f386d7) |

注意名称混淆：KillingSpark 的仓库名也叫 zstd-rs，发布 crate 是 **ruzstd**；Avarok 发布 crate 是 **zstd-rs**；gyscos 的仓库同名，发布 crate **zstd** 则是 C binding。DroidMux 当前依赖最后一种，替代必须覆盖编码和解码。[gyscos zstd](https://github.com/gyscos/zstd-rs)

工程推论：Brotli/LZ4 的源码路径较直接；Zstd 可以优先验证已有流式结构的 ruzstd，并评估修复错误/取消 API及上游维护，而不是新写压缩算法。压缩率和速度不同不自动代表线协议能力减少；但必须验证参考 ADB 输出的 frame、输入限制、损坏数据、内存上界、空文件、结束帧和多任务公平性。停止宣告某算法或退回无压缩不能算本项目“完整纯 Rust 压缩已完成”。

## 8. 工程推论：目前可验证的组合

| 组合 | 组成 | 满足的纯度口径 | 尚未闭合的条件 |
| --- | --- | --- | --- |
| A：尽量全部软件 Rust | 改造 libadb 或 DroidMux + rustls 自定义 RustCrypto provider + 已有 SPAKE2 Rust 变体 + nusb + mdns-sd + Brotli/LZ4/ruzstd | 可能实现不捆绑 C/C++/手写汇编；仍调用系统 I/O | provider 生产成熟度、软件 RSA 私钥路径审查、AOSP 互操作、Zstd 错误 API、目标 feature 图；不能现在宣告可发布 |
| B：Rust 依赖与系统密钥组合 | A 的协议/传输/压缩，AUTH/TLS 私钥改走 Keystore 外部 signer | 可不捆绑 C 密码库；密码运算并非全由 Rust 执行 | 硬件 signer 参数、证书生成、异步调度、同一主控身份覆盖 AUTH/TLS；provider 其他密码路径仍需验收 |
| C：保留经批准的有限例外 | 其余保持 Rust，若特定密码层阻塞再讨论 ring/AWS-LC 等受控例外 | 项目源码 Rust；不满足严格依赖纯度 | **当前未获用户接受**；需要先给出 A/B 的失败证据、例外范围与后续替换边界，不能默认采用 |

A/B 均未要求削减 USB、配对、发现或压缩能力。B 也没有由“身份不自动迁移”自动推导获得授权；Q26 只确定产品行为。当前证据支持“技术路线值得做完整 POC”，不足以支持“纯 Rust 全链已经生产就绪”，也不足以支持“原生密码库必不可少”。

## 9. 尚需 POC 与依赖验收

| 验证 | 能证伪什么／通过条件 |
| --- | --- |
| 目标 feature 闭包 | 在有工具链的后续阶段，对 Android 各 ABI 解析普通/构建依赖，区分 dev/optional；记录 Cargo.lock、`cargo tree -e features --target …` 与实际构建日志。确认谁激活 ring/aws-lc/libusb/zstd-sys、是否含 C/ASM；本次没有执行 |
| TLS/SPAKE2 互操作 | Android 11–17 所选矩阵与官方 ADB 对照；覆盖配对 TLS exporter、角色/NUL、错误码、STLS、TLS1.3 RSA-PSS、重连、取消；双方自测通过不能替代对 AOSP 验证 |
| 密码学发布门槛 | 固定 provider/原语版本和实际调用图；分别审查软件私钥与仅公钥验证路径。记录上游生产警告及 advisory 处置依据，不能用“能连上”替代安全评估 |
| Keystore 完整身份 | 同一不可导出 RSA 身份完成 legacy AUTH、配对及 TLS；校验 DigestInfo、PSS salt/参数、自签证书、TEE/StrongBox 不支持时原因；证明无软件私钥旁路 |
| Android USB | UsbManager 授权 FD 到 nusb；所有权/dup/close、ZLP、读写队列、取消、拔插、权限撤销、后台恢复；不要求 root 或原始 /dev 权限 |
| 压缩与并行传输 | 三算法双向对照 AOSP；大文件/空文件/截断/坏帧/取消与限内存。尤其 ruzstd I/O 错误不 panic、按块输出可承受背压，多任务不整文件占内存 |
| 发现与平台约束 | Android multicast lock、本地网络权限、接口切换、IPv6 link-local scope；mDNS 不通仍可手动连接；未来平台先保留后端接口，不声称现在已验证 |

## 10. 当前研究决策顺序（不是重复问卷）

1. **按纯度层次列实际闭包。**用户Q32未选严格定义但要求四端可编译；当前研究优先尽量不捆绑C/C++/手写汇编，系统socket、UsbManager/JNI、WinUSB/IOKit和signer单列。这是研究优先级，不冒充用户已经接受严格禁令或原生后端例外。先给证据，不再要求用户选算法。
2. **选择密码学方案的发布门槛。**建议先验证 A/B；保留上游“不用于生产”的 provider 时，不仅做连通性测试，还需解决版本维护和安全审查依据。若不达标，再带具体失败证据讨论有限例外或继续投入，不现在默认接受原生依赖。依赖：第 1 项。
3. **确定主控授权身份是否优先交给 Keystore。**建议比较 B 与软件 Rust 身份的兼容矩阵后决定；其收益是私钥不可导出与调用路径隔离，代价是系统密码 API 和硬件参数差异。依赖：第 1、2 项及已确认 Q26；无需重新询问是否默认迁移。
4. **确定现有实现的复用与维护责任。**建议允许组合上游 crate 或维护有边界的 fork，补齐 provider、USB、Zstd 接口与完整度验收；“Rust 重写”不应未经确认解释为全部从零。依赖：第 1、2 项；决定是否承诺长期跟进上游协议、依赖安全和跨平台构建。

当前执行入口为[任务02](../../.scratch/interop/issues/02-pure-rust-crypto-dependencies.md)、[身份任务15](../../.scratch/interop/issues/15-identity-trust-and-transports.md)和[四端构建任务03](../../.scratch/interop/issues/03-workspace-bridge-platform-builds.md)。上述比较由代理开展，不把常规库复用或signer候选反复交用户投票；只有具体例外超出既有授权才带证据沟通。
