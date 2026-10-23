# 邻接 · Interconnect

通过主控访问已授权的 Android 设备，提供远控、文件、相册和通信入口。主控不要求开启调试；被控使用系统 USB/无线调试授权，不安装配套 APK。支持条件见[被控兼容边界](docs/implementation/android-target-compatibility.md)，实测环境见[验收记录](docs/implementation/validation.md)。

## 工作区

| 目录 | 职责 |
| --- | --- |
| `app/` | Flutter 主控、测试与各平台 runner |
| `packages/` | 运行时组装、ADB、连接、偏好、文件、媒体、协议、诊断与设计系统；各包 README 说明接口 |
| `crates/` | Rust ADB、设备执行核心、FRB 桥接和 Android 文件助手 |
| `protocol/` | Dart/Rust 命令与字段形状的单一来源 |
| `servers/` | 固定 scrcpy、协同 JAR、文件助手及其构建输入 |
| `designs/` | 产品规格、视觉规范和 Pencil 源稿 |
| `tool/` | 生成、构建、检查、宿主驱动与测试夹具 |

根 `pubspec.yaml` 声明 Dart workspace 和工具依赖；应用依赖在 `app/pubspec.yaml`，共用根 lockfile。

## 开发与构建

准备 Flutter、`rust-toolchain.toml` 固定的 Rust、JDK 21 和 Android SDK。平台依赖、生成入口及产物边界见[工具链契约](docs/implementation/repository-tooling.md)。

```sh
flutter pub get
npm ci --ignore-scripts --prefix tool/design_tokens
./tool/check.sh
cd app
flutter run -d <device>
```

Android 侧载包在仓库根执行 `dart tool/android.dart init-signing`、`dart tool/android.dart build`。已有签名不会被替换；私钥不入 Git，更新安装须使用同一身份。输出为 `app/build/app/outputs/flutter-apk/app-release.apk`，详见[Android 打包](docs/implementation/android-packaging.md)。

## 文档

- [词表](GLOSSARY.md)与 [ADR](docs/adr/)：术语和架构决定。
- [产品规格](designs/prod/README.md)、[视觉规范](designs/design.md)与 [Pencil](designs/mobile.pen)：行为、token 和代表状态。
- [架构](docs/implementation/architecture.md)与[工具链](docs/implementation/repository-tooling.md)：依赖、所有权、生成和构建规则。
- [研究](docs/research/README.md)与[验收](docs/implementation/validation.md)：来源分析及指定环境下的结果；不替代当前规范。

`tool/check.sh` 执行主机检查。真实设备、配对、媒体和故障测试须按各入口显式提供隔离环境；跳过不算通过。
