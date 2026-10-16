# 邻接 · Interconnect

用手边的 Android 手机查看、操作和取用另一台 Android 手机。设备列表是首页；远控全屏显示，应用任务保留在原手机，文件与相册可手动取回，通知跳转手机原应用。主控不要求开启调试；被控端使用系统 USB／无线调试授权，不安装配套 APK。

这是持续实施中的项目。已在三台独立 Android 16 无头模拟器完成真实连接、投控、五种视频格式渲染、文件与目录传输、系统文件选择器、跨设备剪贴板、音频播放及后台策略验证；完整状态与限制见 [验收记录](docs/implementation/validation.md)。模拟器成功不代表物理 USB、旧系统、OEM 后台或生产密码安全已经通过。

## 工作区

| 目录 | 内容 |
| --- | --- |
| `apps/connect` | Flutter 主控与 Android 平台适配；保留 iOS、macOS、Windows runner |
| `packages/design_system` | 中性主题、玻璃材质与共享界面组件 |
| `packages/interop_bridge` | Dart／Rust 边界、媒体与系统能力适配 |
| `crates/adb` | 独立 Rust ADB 主机协议、配对、TLS、USB、shell、sync 等服务 |
| `crates/interop_core` | 设备、会话、传输及免安装协同活动 |
| `servers` | 固定版本 scrcpy JAR、临时协同 JAR 与文件原子操作助手 |
| `designs` | DESIGN.md、产品说明和 Pencil 页面／组件源文件 |

## 本地开发

固定工具链：Rust 1.99.1、Flutter 3.47.6／Dart 3.13.5、JDK 21；当前 Android 验证使用 SDK 36、NDK 28.2.13676358。Flutter、Android SDK 与 NDK 需提前安装；`ANDROID_HOME` 指向 SDK，Flutter、Rust 在 PATH 中。

```sh
flutter pub get
cargo test --workspace
./tool/check.sh
cd apps/connect
flutter run -d <android-device>
```

Android 运行时通过 Flutter native assets 自动构建 Rust 库，不调用或分发外部 `adb` 可执行文件。实际设备测试中的官方 adb 仅用于部署、独立读取系统结果和对照。

```sh
cd apps/connect
flutter build apk --debug --target-platform android-x64
```

生成绑定使用固定 `flutter_rust_bridge_codegen 2.13.0`，在根目录运行 `flutter_rust_bridge_codegen generate`。临时 JAR／助手的构建、源码与产物哈希见各自 `servers/*/README.md`。Android release 不自动使用 debug 签名；自行提供被 Git 忽略的 `apps/connect/android/key.properties`（storeFile、storePassword、keyAlias、keyPassword）后才配置 release 签名。

## 设计与验收

[持续目标](.scratch/interop/goal.md)逐项追踪 57 项需求；[产品说明](designs/prod/README.md)说明功能取舍；[视觉规范](designs/design.md)与 `designs/mobile.pen` 保存设计源。预览图和 E2E 资产放系统临时目录，不收进 Git。

`tool/check.sh` 执行 Rust 格式／Clippy／默认测试、Flutter 分析／组件测试和固定官方 DESIGN.md NPM 校验。真实 AVD、无线配对、媒体、文件及故障测试需要对应环境和显式测试参数，方法与证据见验收记录。跨 target 的 Rust 检查与各宿主整包链接分别记录。
