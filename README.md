# 邻接 · Interconnect

通过主控设备访问另一台已授权的 Android 设备。设备列表是首页；远控呈现真实应用任务，文件、相册和通信提供专用入口。主控不要求开启调试；被控使用系统 USB/无线调试授权，不安装配套 APK。

支持条件与实测范围见[被控兼容边界](docs/implementation/android-target-compatibility.md)，当前证据见[验收记录](docs/implementation/validation.md)。模拟器通过不代表物理 USB、OEM 后台或其他宿主已经验收。

## 工作区

| 目录 | 内容 |
| --- | --- |
| `app` | Flutter 主控源码、测试及平台 runner；正式交付平台为 Android、iOS、macOS、Windows，Linux runner 仅用于本地开发与成像验证 |
| `packages/design_system` | 主题、材料和共享界面组件 |
| `packages/interop_bridge` | Dart 产品编排、Rust 边界、媒体与系统适配 |
| `crates/adb` | 独立 Rust ADB 主机协议与服务 |
| `crates/interop_core` | 设备、会话、传输与被控协同活动 |
| `crates/interop_bridge` | FRB 入口、命令校验与事件观察 |
| `crates/android_helper` | 被控原生元数据、目录与原子文件操作 |
| `protocol` | Dart/Rust 命令与字段形状的单一来源 |
| `servers` | 固定 scrcpy、协同 JAR、原生文件服务及构建输入 |
| `designs` | 视觉规范、产品规格和 Pencil 源稿 |
| `tool` | 生成、构建、检查、宿主驱动、性能与夹具 |

根 `pubspec.yaml` 只声明 Dart workspace 和工具依赖，应用依赖在 `app/pubspec.yaml`。整个 workspace 共用根 `pubspec.lock` 与 `.dart_tool`。

## 本地开发

准备 Flutter、Rust、JDK 21 和 Android SDK。Rust 版本由 `rust-toolchain.toml` 固定；SDK/NDK、原生依赖与生成职责见[工具链契约](docs/implementation/repository-tooling.md)。

```sh
flutter pub get
npm ci --ignore-scripts --prefix tool/design_tokens
./tool/check.sh
cd app
flutter run -d <device>
```

Flutter native assets 自动构建 Rust 库，产品不调用或分发外部 `adb`。修改共享命令契约运行 `dart tool/protocol_codegen.dart`；其他生成物运行 `dart tool/generate.dart`，验证时加 `--check`。视觉值先改 `designs/design.md` 再生成，不手改 Dart token。

Android 侧载包使用：

```sh
dart tool/android.dart init-signing
dart tool/android.dart build
```

已有签名不会被替换；私钥与 `key.properties` 不进入 Git，更新安装需要同一签名身份。输出为 `app/build/app/outputs/flutter-apk/app-release.apk`，构建与分发边界见[Android 打包](docs/implementation/android-packaging.md)。

## 文档与验收

| 文档 | 责任 |
| --- | --- |
| [词表](GLOSSARY.md)与 [ADR](docs/adr/) | 对象含义与已接受的架构边界 |
| [产品规格](designs/prod/README.md) | 范围、入口、默认行为、失败与恢复 |
| [视觉规范](designs/design.md)与 [Pencil 源稿](designs/mobile.pen) | token、组件语义和代表状态 |
| [架构](docs/implementation/architecture.md) | 依赖方向、资源所有权和恢复边界 |
| [工具链](docs/implementation/repository-tooling.md) | 生成、构建、产物与清理契约 |
| [研究索引](docs/research/README.md) | 固定来源下的事实、比较和推论 |
| [验收记录](docs/implementation/validation.md) | 指定版本、环境与证据范围 |

规则在责任文档维护，研究建议和历史验收不替代当前规范。`tool/check.sh` 执行 Rust、Flutter、生成一致性和 DESIGN.md 检查；真实 AVD、无线配对、媒体、文件及故障测试按测试声明提供隔离环境后显式运行，不能把 ignored 计作通过。截图和调试导出使用系统临时目录，清理规则见[构建与产物边界](docs/implementation/repository-tooling.md#构建与产物边界)。
