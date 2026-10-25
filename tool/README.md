# 开发工具入口

这些文件在开发机器运行，不进入正式 APK。应用运行测试在 `app/test/`，需要设备的完整流程在 `app/integration_test/`。构建责任与缓存规则以[工具链契约](../docs/implementation/repository-tooling.md)为准。

| 要做什么 | 入口 | 产生什么 |
| --- | --- | --- |
| 发布 Android | `android.dart` | 按主控 ABI 分开的签名 APK；`--abi universal` 才合并 |
| 发布桌面 / Apple | `build_host.dart` | 核验后的宿主归档 |
| 更新生成代码 | `generate.dart` | 视觉 token、共享被控 assets、FRB 和 Dart builders；`--check` 检查漂移 |
| 更新应用命令契约 | `protocol_codegen.dart` | 从 `protocol/commands.json` 生成 Dart 命令声明 |
| 完整仓库门禁 | `check.sh` | 生成、来源、格式、分析和各层测试；不作为每次调试前置 |
| Android 原生契约 | `native_contracts.dart` | 临时 JVM 编译；结束后回收 |
| 纯宿主工具测试 | `host/` | 独立 Dart 测试缓存，不构建 Flutter / Rust hooks |

普通工具通过 VM 直接运行，避免先编译宿主原生库：

```sh
dart --disable-dart-dev tool/android.dart build --abi arm64
dart --disable-dart-dev tool/generate.dart --check
cd tool/host
dart pub get --enforce-lockfile
dart test test/android_test.dart
```

应用改动在 `app/` 运行相关 `flutter test`；ADB、scrcpy、媒体改动在对应包运行。`check.sh --android` 默认只构建 arm64 调试包，通过 `ANDROID_TARGET_PLATFORM=android-x64` 等选择本次调试目标。

其余目录按验证方式区分：

| 目录 | 用途 |
| --- | --- |
| `src/` | 被入口复用的 ZIP、依赖图、进程和生成检查实现 |
| `driver/` | 在宿主侧操作真实应用、系统界面和外部设备；不是单元测试 |
| `e2e/` | 设备测试使用的 Android 小程序、USB/IP 与视频分析夹具；不进入正式产品 |
| `benchmark/` | 按需运行的弱网代理；视频真实像素性能测量使用对应设备 driver |
| `visual_parity/` | 按需进行页面成像对比 |
| `design_tokens/` | 固定上游解析器和 Dart token 生成器 |

`glass_emulator.dart` 是当前 Linux 玻璃成像回归的特定模拟器入口；`apple_bundle_resources.sh` 由 Apple runner 调用，处理受控资源与签名。`check_*` 和 `packaged_servers.dart` 供完整检查与交付核验复用。设备实验需要显式指定隔离设备，日志和截图放系统临时目录。

构建入口直接转发 Flutter、FRB、Gradle 和 Cargo 日志；只有结构化回执才使用带字节预算和超时的捕获。工具进程失败后先确认退出，再清理本次资源。独立 APK 夹具共用 `e2e/build_fixture.dart`，按输入及签名身份复用验证过的产物，不在每次调试前重建所有夹具。
