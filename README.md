# 邻接 · Interconnect

通过主控访问已授权的 Android 设备，提供远控、文件、相册和通信入口。主控不要求开启调试；被控使用系统 USB/无线调试授权，不安装配套 APK。支持条件见[被控兼容边界](docs/implementation/android-target-compatibility.md)，实测环境见[验收记录](docs/implementation/validation.md)。

## 工作区

以下职责按实际代码维护；当前结构、包体积和调试改造验证见[重构记录](docs/implementation/code-and-build-refactor-validation.md)。历史运行结果不代表当前版本已交付。

| 目录 | 职责 |
| --- | --- |
| `app/` | Flutter 主控、应用业务、测试和各平台 runner；只调用能力包的公开 Dart 接口 |
| `packages/` | 通用 `design_system`、`adb`、`scrcpy`、`media_codec`；隐藏原生绑定与生成物 |
| `rust/` | 与能力包同名的 Rust 实现；只提供需要原生执行的通用机制 |
| `protocol/` | 应用命令与字段形状的单一来源；不作为通用包的聚合命令接口 |
| [`servers/`](servers/README.md) | scrcpy 与协同 JAR 的源码、构建输入和产物；文件助手的构建器、manifest 与 ABI 产物，助手 Rust 源码归 `rust/adb/device_fs_helper/` |
| `designs/` | 产品规格、视觉规范和 Pencil 源稿 |
| [`tool/`](tool/README.md) | 生成、构建、检查、宿主驱动与测试夹具；入口说明见目录文档 |

根 `pubspec.yaml` 声明 Flutter/Dart workspace；应用依赖在 `app/pubspec.yaml`，共用根 lockfile。纯宿主测试在独立 `tool/host/` Dart 环境运行，避免触发应用原生构建。

应用内按 `application`、`connection`、`preferences`、`files`、`media`、`platform` 与 `presentation` 表达职责；页面与 typed route 的位置保持业务归属。通用包、原生捕获及媒体的模块位置和依赖规则见[架构](docs/implementation/architecture.md#模块位置与接口)。

## 开发与构建

准备 Flutter、`rust-toolchain.toml` 固定的 Rust、JDK 21 和 Android SDK。平台依赖、生成入口及产物边界见[工具链契约](docs/implementation/repository-tooling.md)。

```sh
flutter pub get
npm ci --ignore-scripts --prefix tool/design_tokens
./tool/check.sh
cd app
flutter run -d <device>
```

Android 侧载包在仓库根执行 `dart --disable-dart-dev tool/android.dart init-signing`、`dart --disable-dart-dev tool/android.dart build`。默认输出三个 ABI 各自的 `app/build/app/outputs/flutter-apk/app-<ABI>-release.apk`；显式 `--abi universal` 才生成通用包。已有签名不会被替换；私钥不入 Git，更新安装须使用同一身份。详见[Android 打包](docs/implementation/android-packaging.md)。

## 文档

- [词表](GLOSSARY.md)与 [ADR](docs/adr/)：术语和架构决定。
- [产品规格](designs/prod/README.md)、[视觉规范](designs/design.md)与 [Pencil](designs/mobile.pen)：行为、token 和代表状态。
- [架构](docs/implementation/architecture.md)与[工具链](docs/implementation/repository-tooling.md)：依赖、所有权、生成和构建规则。
- [研究](docs/research/README.md)与[验收](docs/implementation/validation.md)：来源分析及指定环境下的结果；不替代当前规范。

`tool/check.sh` 执行主机检查。真实设备、配对、媒体和故障测试须按各入口显式提供隔离环境；跳过不算通过。
