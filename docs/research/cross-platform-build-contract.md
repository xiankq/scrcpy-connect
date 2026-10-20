# Android、iOS、Windows、macOS 编译交付约束

研究日期：2026-10-16。核对 Flutter、FRB 和固定 ADB 候选源码的目标平台约束。当前交付矩阵见[ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md)，实际构建入口与结果见[工具链契约](../implementation/repository-tooling.md)。本研究未执行平台构建。

## 1. 目标矩阵：三层分别通过，运行能力另记

| 目标平台 | Rust ADB 核心 | FRB 绑定原生库 | Flutter 整包 | 编译通过不能推出的能力 |
| --- | --- | --- | --- | --- |
| Android | rlib；协议/认证/配对/复用/服务；Android transport 与平台桥按目标启用 | 生成绑定并编译链接到 Android native 库 | APK/AAB 实际构建成功，包含正确 ABI 的 Rust 与插件产物 | USB 授权、无线发现、Keystore、后台保持、控制会话/媒体真机表现 |
| iOS | 同一核心；保留 TCP/TLS/配对；通用 USB 后端不能进入依赖闭包 | Apple 目标原生库实际链接，避免 Android JNI/USB 符号泄漏 | 实际 iOS app 链接成功；签名与发行另分级 | iPhone 通用 USB ADB、本地网络授权、后台持续连接、媒体解码 |
| Windows | 同一核心；WinUSB/发现等独立适配 | 对选定 MSVC 目标构建并链接 | Flutter Windows 应用与所需 DLL 构建/打包成功 | 驱动匹配、USB热插拔、通知或媒体能力已验证 |
| macOS | 同一核心；IOKit/发现等独立适配 | 对选定 Apple CPU 目标构建并链接 | Flutter macOS 应用及 native 依赖构建成功 | 沙箱/entitlement、网络/USB访问、媒体能力已验证 |

Flutter 官方支持四种目标，但 iOS/macOS 的完整 Flutter 构建在 macOS 上，Windows 在 Windows 上；“Rust 可交叉编译”不能替代这些宿主要求。[Flutter 平台与构建宿主](https://docs.flutter.dev/platform-integration)

## 2. 已证事实：iOS USB 不能拖垮核心与绑定

| 候选/固定源码 | 已证接口与问题 | 可绕开边界；尚未验证什么 |
| --- | --- | --- |
| libadb 0.5.0，`bc681df985967e083cdd7c02df45f942495393a5` | USB 后端是可选 feature；`Transport` 与 `UsbBackend` 抽象提供 `NoUsb`。`usb` 别名启用 nusb；仅依赖 feature 判断，库不会自动按 iOS 关闭它 | iOS 使用无 USB 的 feature 集与 `NoUsb`，共用 TCP/认证/服务。Android/Windows/macOS 另选 USB 后端。没有本项目 iOS 编译记录，不能宣布 TCP 核心已通过。[清单](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/Cargo.toml)、[transport](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/transport.rs) |
| nusb 0.2.8，`c80218d342740321190436bc45304ebbbf16bef0`；该版 libadb 的 nusb 0.1.14，`c4415cb2684ae98e7a2c432b00f2482dc6dae5c8` | 两版都没有 iOS backend；0.1 选择 Linux/Android、Windows、macOS，0.2 另有 wasm。上层使用 `platform::Device` 等类型，不能指望在 iOS 启用 nusb 后自动退化为无 USB | iOS 目标闭包排除 nusb；不能只在 Dart 隐藏 USB 入口。这是源码层面的阻塞证据，本次没有执行编译器复现。[0.1 平台选择](https://github.com/kevinmehall/nusb/blob/c4415cb2684ae98e7a2c432b00f2482dc6dae5c8/src/platform/mod.rs)、[0.2 平台选择](https://github.com/kevinmehall/nusb/blob/c80218d342740321190436bc45304ebbbf16bef0/src/platform/mod.rs)、[Device](https://github.com/kevinmehall/nusb/blob/c80218d342740321190436bc45304ebbbf16bef0/src/device.rs) |
| DroidMux 0.1.0 工作区，`9adeb6258166e9b88808bc6e67845c73763f070c` | `droidmux-transport` 的 AdbTransport trait 独立；USB 在单独 `droidmux-transport-usb` crate，依赖 vendored rusb；顶层 `usb` 可选，`full` 会启用它及 control/media | iOS 可不选 USB，或直接组合底层 crates；不能在所有平台统一开 `full`。现有证据证明可隔离，不证明其完整依赖闭包已在 iOS 编译；也没有证据断言 TCP 核心必然失败。[顶层 features](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux/Cargo.toml)、[独立 trait](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-transport/src/lib.rs)、[USB crate](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-transport-usb/Cargo.toml) |

工程推论：需要“共同协议核心 + 目标平台适配”的边界。iOS 缺少通用 USB 不应让包失败，也不应伪装 USB 成功；公开接口保留同一连接/能力模型，平台返回明确功能支持状态。USB 库、JNI 类型、IOKit handle 不暴露到 FRB 共用 DTO。这样保留完整产品能力清单，同时按平台诚实报告实际能力。

## 3. target cfg/features 与依赖闭包的约束

以下是工程建议，尚未写入 Cargo 或应用：

1. **依赖声明与引用代码都要隔离。**在 Cargo 的 target-specific dependencies 中限制 nusb/JNI/平台 signer 等出现的目标；Rust 用 `#[cfg(...)]` 限制模块、导入和实现。只用 `if cfg!(...)`、运行时平台判断或 Dart 条件隐藏，仍会编译不支持的依赖/分支。[Cargo 平台依赖](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#platform-specific-dependencies)、[Rust conditional compilation](https://doc.rust-lang.org/reference/conditional-compilation.html)
2. **feature 表示可组合能力，目标 cfg 表示平台。**不要在 `[target.'cfg(feature = "usb")'.dependencies]` 中模拟 feature，Cargo 不支持这种用法；使用 optional dependency + feature，并与目标条件配合。平台不支持某 backend 时，同名能力查询可返回不支持，不能让 `full` 无条件拉入该 backend。[Cargo 规则](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#platform-specific-dependencies)
3. **控制 feature 叠加。**workspace resolver 2 或更新版本能隔离部分目标/构建依赖的 feature，但不会把 feature 变成可相减。另一个路径启用 ring/USB 就仍可能污染闭包；调用方关闭 defaults 不能撤销上游显式特性。iOS 编译验收应针对正式 feature 集，不要求无意义地统一 `--all-features`。[resolver 2](https://doc.rust-lang.org/cargo/reference/resolver.html#feature-resolver-version-2)、[feature unification](https://doc.rust-lang.org/cargo/reference/features.html#feature-unification)
4. **平台判断针对 target，不是构建电脑。**build.rs 在宿主执行，交叉构建时读取 Cargo 的 TARGET/CARGO_CFG_TARGET_OS 等信息；不能靠构建脚本自身的 `cfg!(target_os=...)` 推断要链接的目标平台。[Cargo build scripts](https://doc.rust-lang.org/cargo/reference/build-scripts.html)、[Cargo 环境变量](https://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-build-scripts)
5. **闭包含 native 产物与插件，不只 Cargo.lock。**rustls provider、RSA/随机数、sync 压缩、mDNS、JNI、USB、FRB runtime，以及 Flutter 媒体/玻璃/系统插件全部需要目标审计。纯 Rust 源码也可能缺目标 cfg 或 linker 支持；C 依赖也不能仅因不是 Rust 就判定无法四端构建。[此前依赖矩阵](pure-rust-adb-dependencies.md)

## 4. FRB 不替依赖补齐平台支持

FRB 官方当前支持 Cargokit（默认）或 Native Assets 集成；两者都需要底层 Rust crate 真正能为目标编译和链接。Native Assets 文档要求 staticlib/cdylib 产物和固定具体 Rust toolchain；不应照搬旧文档中“构建前改 Cargo.toml”的示例当作当前工程规范。[集成后端](https://cjycode.com/flutter_rust_bridge/manual/integrate/builtin)、[Native Assets 条件](https://cjycode.com/flutter_rust_bridge/manual/integrate/native-assets)

工程推论：ADB 核心保持可独立消费的 rlib；FRB adapter 负责导出平台可链接产物，共用 Dart API 和错误/功能支持状态。绑定生成成功、Dart analyze 成功、Rust check 成功、Rust native 库链接成功、Flutter app 链接成功是不同证据。FRB 版本/codegen/runtime、SDK 与生成后端要一起固定；生成代码引用的函数在每个平台都应存在，或由一致的显式平台绑定方案处理，不能仅删除 Rust 实现留下导出符号悬空。

## 5. 主机 SDK 与持续集成验收

| CI 作业 | 宿主与必要工具 | 必须保留的结果 |
| --- | --- | --- |
| Android | Linux/macOS/Windows 中选定宿主；Flutter/Dart、JDK/Android SDK、固定 NDK 与 Rust target/linker | 目标 feature 依赖图、核心/绑定编译链接、实际 APK/AAB 构建与 ABI 核对；具体 ABI 待定。[Android setup](https://docs.flutter.dev/platform-integration/android/setup) |
| iOS | macOS + 固定 Xcode/iOS SDK + Rust Apple targets；插件需要时配置 CocoaPods/SPM | 选定真机/模拟器目标各自的 native 链接与 app 构建；若仅构建 unsigned device app，明确记录“未签名、未部署”，不能算发布验收。[iOS setup](https://docs.flutter.dev/platform-integration/ios/setup) |
| Windows | Windows + Visual Studio Desktop development with C++、Windows SDK、Rust MSVC 工具链 | 选定 CPU 的核心/绑定/整包构建及 DLL 打包；即使 ADB 尽量纯 Rust，Flutter runner 仍需要平台 C++ 工具。[Windows setup](https://docs.flutter.dev/platform-integration/windows/setup) |
| macOS | macOS + Xcode/macOS SDK + Rust Apple targets；插件工具按锁定集成方式配置 | 选定 CPU 的核心/绑定/整包构建；是否 universal、签名/notarization 另定。[macOS setup](https://docs.flutter.dev/platform-integration/macos/setup) |

建议把四端正式构建作为变更门禁：锁定版本、正式 feature profile、生成代码一致性、干净构建、产物留存。`cargo check --target` 不执行最终 native 链接，不能单独满足整包可编译；开发宿主上 `cargo test` 也不能替代移动目标。发生平台能力缺失时应调整适配或依赖边界，不能把某平台作业永久跳过后仍声称四端通过。

编译 CI 不需要普通用户主控开启调试。开发者给测试设备部署 debug app 所用 ADB/Xcode，与发布后主控使用 TCP/UsbManager 连接被控设备是两件事；产品流程只要求被控设备完成相应授权。运行/商店发布/权限与 entitlement/后台策略需要各自验证，不能由“无签名编译成功”代替。
