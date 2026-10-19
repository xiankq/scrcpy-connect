# 邻接 · Interconnect

面向 Android 被控设备的跨设备互联应用，优先服务手机主控。设备列表是首页；远控全屏呈现真实任务，文件、相册和通信分别提供任务入口。主控不要求开启调试；被控设备使用系统 USB／无线调试授权，不安装配套 APK。

功能规则、代码实现和运行验收分别记录。Android 模拟器已验证的具体链路见[产品验收](docs/implementation/product-refinement.md)与[专项记录](docs/implementation/validation.md)；低版本条件和实测范围见[被控兼容边界](docs/implementation/android-target-compatibility.md)；物理 USB、OEM 后台、其他宿主和生产密码安全需要各自证据。

## 工作区

| 目录 | 内容 |
| --- | --- |
| 仓库根目录 | Dart workspace、统一依赖解析与仓库工具配置 |
| `app` | Flutter 主控源码、测试与 Android、iOS、macOS、Windows、Linux runner |
| `packages/design_system` | 中性主题、玻璃材质与共享界面组件 |
| `packages/interop_bridge` | Dart／Rust 边界、媒体与系统能力适配 |
| `crates/adb` | 独立 Rust ADB 主机协议、配对、TLS、USB、shell、sync 等服务 |
| `crates/interop_core` | 设备、会话、传输及免安装协同活动 |
| `crates/interop_bridge` | Rust FRB 入口、共享命令校验与有界事件观察者 |
| `crates/android_helper` | 独立构建的 Android 原生元数据、目录与原子文件操作源码 |
| `protocol` | Dart／Rust 命令、字段形状与状态核验策略的单一来源 |
| `servers` | 固定版本 scrcpy JAR、临时协同 JAR 与原生文件服务 |
| `designs` | DESIGN.md、产品说明和 Pencil 页面／组件源文件 |
| `app/test`、`app/integration_test` | Flutter 单元／组件测试与设备端集成测试 |
| `tool` | Dart 生成／构建／校验入口、主机驱动、性能基准及测试夹具 |

```text
app/
  pubspec.yaml
  lib/
  test/
  integration_test/
  android/  ios/  macos/  windows/  linux/
packages/
crates/
servers/
tool/
pubspec.yaml
pubspec.lock
```

根 `pubspec.yaml` 只声明 workspace 与工具依赖；`app/pubspec.yaml` 声明主应用。整个 Dart workspace 共用根 `pubspec.lock` 和 `.dart_tool`。

## 本地开发

固定工具链：Rust 1.99.1、Flutter 3.47.6／Dart 3.13.5、JDK 21；当前 Android 验证使用 SDK 36、NDK 28.2.13676358。Flutter、Android SDK 与 NDK 需提前安装；`ANDROID_HOME` 指向 SDK，Flutter、Rust 在 PATH 中。

自有构建与诊断脚本使用 Dart；Node 用于官方 DESIGN.md 工具。日常工程检查不要求安装 Python。

```sh
flutter pub get
npm ci --ignore-scripts --prefix tool/design_tokens
cargo test --workspace
./tool/check.sh
cd app
flutter test
flutter run -d <android-device>
```

Android 运行时通过 Flutter native assets 自动构建 Rust 库，不调用或分发外部 `adb` 可执行文件。实际设备测试中的官方 adb 仅用于部署、独立读取系统结果和对照。

在 `app/` 执行：

```sh
flutter build apk --debug --target-platform android-x64
```

生成绑定使用固定 `flutter_rust_bridge_codegen 2.13.0`。修改共享命令契约后运行 `dart tool/protocol_codegen.dart`，生成设计 token、FRB／Dart 代码运行 `dart tool/generate.dart`；两者的 `--check` 均检查生成结果且不改工作区。设计 token 经固定官方 `@google/design.md 0.4.0` 解析，自动输出到 `packages/design_system/lib/src/design_tokens.g.dart`，不手工维护 Dart 数值；单独生成可运行 `node tool/design_tokens/generate.mjs`。临时 JAR／助手的构建、源码与产物哈希见各自 `servers/*/README.md`。当前模块职责与资源归属见[架构说明](docs/implementation/architecture.md)。

### Android 安装包

`flutter build apk` 默认构建 release。首次在仓库根目录执行以下命令，生成本机持久的侧载签名，再为常见 arm64 手机构建并验证安装包：

```sh
dart tool/android.dart init-signing
dart tool/android.dart build
```

已配置的签名不会被替换；私钥与 `key.properties` 不进入 Git，请自行私密备份这两份文件，后续更新需要同一身份。正式分发时可按 [配置示例](app/android/key.properties.example) 换成自己的发布密钥。缺少签名会在编译前明确失败，不再生成未签名的“成功”包，也不会悄悄用 debug 密钥签 release。

打包入口默认只编译 arm64；模拟器使用 `--abi x64`，32 位主控设备使用 `--abi arm`，全架构包使用 `--abi universal`。直接在 `app/` 执行 `flutter build apk` 仍会生成三架构通用签名包。单架构模式也会过滤插件的其他架构库，避免只有插件、没有 Flutter／Rust 的不完整 ABI。

最终 APK 在 `app/build/app/outputs/flutter-apk/app-release.apk`。可独立复核：

```sh
dart tool/android.dart verify app/build/app/outputs/flutter-apk/app-release.apk
```

验证包括 ZIP 完整性、签名、16KB ZIP 对齐、包名／启动入口和实际 Flutter／Rust ELF 架构。`build` 自动执行上述检查，并打印包摘要与耗时。首次／换架构编译与重复编译分别记录；不要在每次构建前 `flutter clean` 或删除 `.dart_tool/hooks_runner`。调试结束清理过期 `app/build` 产物，保留正在复用的 native hooks／Gradle 缓存；Gradle 已开启本机任务缓存。[实测与限制](docs/implementation/android-packaging.md)。

## 设计与验收

| 文档 | 责任 |
| --- | --- |
| [词表](GLOSSARY.md)与 [ADR](docs/adr/) | 对象含义与已接受的架构边界 |
| [产品规格](designs/prod/README.md) | 功能范围、入口、默认交互和失败恢复 |
| [视觉规范](designs/design.md)与 [Pencil 源稿](designs/mobile.pen) | 视觉 token、组件语义和代表状态 |
| [架构](docs/implementation/architecture.md)与[工具链](docs/implementation/repository-tooling.md) | 实现职责、资源所有权和生成契约 |
| [研究索引](docs/research/README.md) | 固定来源下的事实、比较与推论 |
| [产品验收](docs/implementation/product-refinement.md)、[视觉审计](docs/implementation/ios-visual-audit.md)、[专项记录](docs/implementation/validation.md) | 指定版本、环境、状态和证据范围 |

规则在责任文档中维护，研究建议和历史验收不替代当前规范。源稿 Frame 可表达同一产品页面的多个状态，不与路由数量一一对应。预览与 E2E 资产放系统临时目录；临时日志的生命周期不等于永久归档。

播放器精确使用社区发布的 [fvp 0.39.1](https://pub.dev/packages/fvp/versions/0.39.1)，不保留本地源码副本、补丁或 path override。MDK 下载与平台版本规则继承该发布包；原版 snapshot 空结果未判空的已知限制、原生依赖和历史验证边界见[工具链契约](docs/implementation/repository-tooling.md#社区原版-fvp-0391)。

`tool/check.sh` 执行 Rust 格式／Clippy／默认测试、Flutter 分析／组件测试和固定官方 DESIGN.md NPM 校验。真实 AVD、无线配对、媒体、文件及故障测试需要对应环境和显式测试参数，方法与证据见验收记录。跨 target 的 Rust 检查与各宿主整包链接分别记录。
