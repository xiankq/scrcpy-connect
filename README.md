# 邻接 · Interconnect

面向 Android 被控设备的跨设备互联应用，优先服务手机主控。设备列表是首页；远控全屏呈现真实任务，文件、相册和通信分别提供任务入口。主控不要求开启调试；被控设备使用系统 USB／无线调试授权，不安装配套 APK。

支持条件与实测范围见[被控兼容边界](docs/implementation/android-target-compatibility.md)和[验收记录](docs/implementation/validation.md)。已验证的模拟器链路不代表物理 USB、OEM 后台或其他宿主已经验收。

## 工作区

| 目录 | 内容 |
| --- | --- |
| 仓库根目录 | Dart workspace、统一依赖解析与仓库工具配置 |
| `app` | Flutter 主控源码、测试与 Android、iOS、macOS、Windows、Linux runner |
| `packages/design_system` | 中性主题、玻璃材质与共享界面组件 |
| `packages/interop_bridge` | Dart 产品编排与配置、Rust 边界、媒体与系统能力适配 |
| `crates/adb` | 独立 Rust ADB 主机协议、配对、TLS、USB、shell、sync 等服务 |
| `crates/interop_core` | 设备、会话、传输及免安装协同活动 |
| `crates/interop_bridge` | Rust FRB 入口、共享命令校验与有界事件观察者 |
| `crates/android_helper` | 独立构建的 Android 原生元数据、目录与原子文件操作源码 |
| `protocol` | Dart／Rust 命令、字段形状与状态核验策略的单一来源 |
| `servers` | 固定版本 scrcpy JAR、临时协同 JAR 与原生文件服务 |
| `designs` | DESIGN.md、产品说明和 Pencil 页面／组件源文件 |
| `app/test`、`app/integration_test` | Flutter 单元／组件测试与设备端集成测试 |
| `tool` | Dart 生成／构建／校验入口、主机驱动、性能基准及测试夹具 |

根 `pubspec.yaml` 只声明 workspace 与工具依赖；`app/pubspec.yaml` 声明主应用。整个 Dart workspace 共用根 `pubspec.lock` 和 `.dart_tool`。

## 本地开发

准备 Flutter、Rust、JDK 21 和 Android SDK；`ANDROID_HOME` 指向 SDK，Flutter 与 Rust 位于 PATH。Rust 版本由 `rust-toolchain.toml` 固定，Dart/Flutter 依赖由 workspace 清单和锁文件约束。SDK/NDK、原生依赖与生成职责见[工具链契约](docs/implementation/repository-tooling.md)。

构建与诊断的主要入口使用 Dart；Node 用于官方 DESIGN.md 工具。日常工程检查不要求安装 Python。

```sh
flutter pub get
npm ci --ignore-scripts --prefix tool/design_tokens
cargo test --workspace
./tool/check.sh
cd app
flutter test
flutter run -d <android-device>
```

Flutter native assets 自动构建 Rust 库；产品不调用或分发外部 `adb`。测试中的官方 adb 仅用于部署和独立核验。修改共享命令契约运行 `dart tool/protocol_codegen.dart`；其余生成运行 `dart tool/generate.dart`，验证时添加 `--check`。视觉值修改 `designs/design.md` 后生成，不手改 Dart 常量。JAR／助手构建见各自 `servers/*/README.md`。

### Android 安装包

在仓库根生成本机持久的侧载签名，再构建通用 release 包：

```sh
dart tool/android.dart init-signing
dart tool/android.dart build
```

已有签名不会被替换；私钥与 `key.properties` 不进入 Git，更新安装需要同一身份，请私密备份。发布签名见[配置示例](app/android/key.properties.example)。`build` 自动验证包并打印摘要，输出 `app/build/app/outputs/flutter-apk/app-release.apk`。架构、独立验证和分发规则见[Android 打包](docs/implementation/android-packaging.md)；缓存与清理规则见[工具链契约](docs/implementation/repository-tooling.md#构建与产物边界)。

## 设计与验收

| 文档 | 责任 |
| --- | --- |
| [词表](GLOSSARY.md)与 [ADR](docs/adr/) | 对象含义与已接受的架构边界 |
| [产品规格](designs/prod/README.md) | 功能范围、入口、默认交互和失败恢复 |
| [视觉规范](designs/design.md)与 [Pencil 源稿](designs/mobile.pen) | 视觉 token、组件语义和代表状态 |
| [架构](docs/implementation/architecture.md)与[工具链](docs/implementation/repository-tooling.md) | 实现职责、资源所有权和生成契约 |
| [研究索引](docs/research/README.md) | 固定来源下的事实、比较与推论 |
| [验收记录](docs/implementation/validation.md)与[设计还原](docs/implementation/design-fidelity.md) | 指定版本、环境、状态和证据范围 |

规则在责任文档中维护，研究建议和历史验收不替代当前规范。源稿 Frame 可表达同一产品页面的多个状态，不与路由数量一一对应。预览与 E2E 资产放系统临时目录；临时日志的生命周期不等于永久归档。

`tool/check.sh` 执行 Rust 格式／Clippy／默认测试、Flutter 分析／组件测试和固定官方 DESIGN.md NPM 校验。真实 AVD、无线配对、媒体、文件及故障测试需要对应环境和显式测试参数，方法与证据见验收记录。跨 target 的 Rust 检查与各宿主整包链接分别记录。
