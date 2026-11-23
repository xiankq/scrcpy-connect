# 邻接 · Interconnect

邻接是一款 Android 设备管理工具。用 USB 或无线调试连接设备后，可以查看和操作屏幕、管理文件、浏览相册，也可以从工作台打开常用应用。被控设备使用 Android 系统提供的调试授权，无需安装配套 APK。

各主控平台的连接方式和功能支持见[平台与能力](designs/prod/compatibility.md)。

## 下载与使用

公开版本发布后，可在 [GitHub Releases](https://github.com/xiankq/scrcpy-connect/releases) 下载。每个版本的说明会列出可用平台和对应文件。

- **Android** 按架构选择 APK。不确定时，下载 `android-universal.apk`。
- **Windows** 按 x64 或 ARM64 选择安装器 EXE，也可以下载便携 ZIP。使用便携版时完整解压，然后运行 `Interconnect.exe`。
- **Linux** 按 x64 或 ARM64 选择 AppImage、DEB、RPM 或 tar.gz。
- **macOS** 按 Apple Silicon 或 Intel 选择 DMG，将邻接拖入「应用程序」。预览版 DMG 未经 Apple 公证。
- **iOS 和 iPadOS** 可在 Apple 芯片 Mac 上用模拟器体验预览版。真机编译归档需要 Apple 签名才能安装。

桌面首次使用前需要安装 ADB。各系统的安装方法见[下载包说明](docs/releasing.md#怎么选下载包)。

首次连接时，在 Android 被控设备上打开开发者选项，按连接方式启用 USB 或无线调试，只授权自己信任的主控。连接、配对和重连的区别见[设备连接](designs/prod/README.md)。

Linux 用户如需添加应用菜单入口，可以将可执行文件目录加入桌面会话的 `PATH`，再把随包的 `share/applications/` 与 `share/icons/` 内容放到本机的 `$XDG_DATA_HOME` 对应目录。未设置时使用 `~/.local/share`。Windows 用户如果还在使用指向旧可执行文件名的快捷方式，请将它改为指向 `Interconnect.exe`。

## 从源码运行

准备 Flutter 3.50.1、`rust-toolchain.toml` 指定的 Rust、Node.js 22 和 Python 3。Android 还需要 JDK 21 和 Android SDK，桌面系统需要对应的原生编译工具。

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
flutter pub get --enforce-lockfile
cd app
flutter run -d <device>
```

安装依赖时使用锁文件中的 Pub 镜像。各系统的构建依赖和完整检查见[贡献指南](CONTRIBUTING.md)。遇到问题可以[提交 issue](https://github.com/xiankq/scrcpy-connect/issues)，安全问题按[安全报告](SECURITY.md)私下提交。

## 项目文档

| 文档 | 内容 |
| --- | --- |
| [产品规格](designs/prod/README.md) | 各页面和连接、远控、文件等功能的预期行为 |
| [视觉规范](designs/design.md) | 设计稿、组件、色彩和布局约定 |
| [构建脚本](scripts/README.md) | 本机验证、构建、产物检查和发布入口 |
| [发布说明](docs/releasing.md) | 从试打包到公开发布，以及如何处理失败 |
| [发布前补充清单](docs/release-owner-checklist.md) | 维护者需要决定、提供和配置的事项 |
| [第三方组件](THIRD_PARTY_NOTICES.md) | 随仓库或安装包提供的外部代码、素材和许可 |
| [变更记录](CHANGELOG.md) | 每个公开版本的用户可见变化 |

Flutter 应用在 `app/`，可复用的 Dart 接口在 `packages/`，对应的原生实现位于 `rust/`。被控设备运行的临时组件在 `servers/`。

项目代码采用 [MIT 许可证](LICENSE)。外部组件与设计素材沿用各自的许可，见[第三方组件](THIRD_PARTY_NOTICES.md)。
