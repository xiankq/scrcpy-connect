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

生成绑定使用固定 `flutter_rust_bridge_codegen 2.13.0`，在根目录运行 `flutter_rust_bridge_codegen generate`。临时 JAR／助手的构建、源码与产物哈希见各自 `servers/*/README.md`。

### Android 安装包

`flutter build apk` 默认构建 release。首次在仓库根目录执行以下命令，生成本机持久的侧载签名，再为常见 arm64 手机构建并验证安装包：

```sh
python3 tool/android.py init-signing
python3 tool/android.py build
```

已配置的签名不会被替换；私钥与 `key.properties` 不进入 Git，请自行私密备份这两份文件，后续更新需要同一身份。正式分发时可按 [配置示例](apps/connect/android/key.properties.example) 换成自己的发布密钥。缺少签名会在编译前明确失败，不再生成未签名的“成功”包，也不会悄悄用 debug 密钥签 release。

打包入口默认只编译 arm64；模拟器使用 `--abi x64`，旧手机使用 `--abi arm`，全架构包使用 `--abi universal`。直接在 `apps/connect` 执行 `flutter build apk` 仍会生成三架构通用签名包。单架构模式也会过滤插件的其他架构库，避免只有插件、没有 Flutter／Rust 的不完整 ABI。

最终 APK 在 `apps/connect/build/app/outputs/flutter-apk/app-release.apk`。可独立复核：

```sh
python3 tool/android.py verify apps/connect/build/app/outputs/flutter-apk/app-release.apk
```

验证包括 ZIP 完整性、签名、16KB ZIP 对齐、包名／启动入口和实际 Flutter／Rust ELF 架构。`build` 自动执行上述检查，并打印包摘要与耗时。首次／换架构编译与重复编译分别记录；不要在每次构建前 `flutter clean` 或删除 `.dart_tool/hooks_runner`。调试结束清理过期 `build` 产物，保留正在复用的 native hooks／Gradle 缓存；Gradle 已开启本机任务缓存。[实测与限制](docs/implementation/android-packaging.md)。

## 设计与验收

[持续目标](.scratch/interop/goal.md)逐项追踪会话要求；[当前完整差距](.scratch/interop/completion-reassessment.md#12-再次逐指令复核当前交付远未完成)区分实现、证据和剩余工作；[产品说明](designs/prod/README.md)说明功能取舍；[视觉规范](designs/design.md)与 `designs/mobile.pen` 保存设计源。预览图和 E2E 资产放系统临时目录，不收进 Git。

`tool/check.sh` 执行 Rust 格式／Clippy／默认测试、Flutter 分析／组件测试和固定官方 DESIGN.md NPM 校验。真实 AVD、无线配对、媒体、文件及故障测试需要对应环境和显式测试参数，方法与证据见验收记录。跨 target 的 Rust 检查与各宿主整包链接分别记录。
