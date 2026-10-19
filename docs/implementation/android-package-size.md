# 三架构 Android APK 缩包验收

日期：2026-10-19。基于检出 `8853d975b00abb157b55d05bf3f4a794fef84416` 的本次工作区改动；Flutter 3.47.6、Dart 3.13.5、Rust 1.99.1、Android SDK 36、NDK 28.2.13676358。当前打包职责见[工具链契约](repository-tooling.md#被控执行产物的共享打包)，本记录只证明下述产物和环境。

## 最终通用安装包

普通 `app/lib/main.dart` release 入口，包含 ARM32 `armeabi-v7a`、ARM64 `arm64-v8a`、`x86_64`。最终路径为 `app/build/app/outputs/flutter-apk/app-release.apk`，**58,021,419 字节（58.0 MB / 55.33 MiB）**，SHA-256：

```text
cd151f295d2816fa8d9f3b23c459b8005c58093a477b5dac294506bb4425566d
```

| 同一功能范围、同三架构 release | APK 字节 | 十进制 MB |
| --- | ---: | ---: |
| 原始基线 | 142,854,555 | 142.9 |
| 共享压缩执行产物、去掉无字幕用途的 libass，原生库仍直接加载 | 120,699,763 | 120.7 |
| 再将原生库压缩进 APK，安装时解压 | 58,021,419 | 58.0 |

最终相对基线减少 **84,833,136 字节，59.38%**。后一步改变的是下载包压缩方式，不表示解压后的库代码又减少同等大小；安装后还会保存匹配架构的解压库。用户明确选择下载体积优先，构建工具与 Gradle 默认已同步。`dart tool/android.dart build` 默认通用 release；`--no-compress-native` 可构建直接加载的对照包。

未改动上游 JAR、DEX、原生助手或其原始摘要，保留四种被控 ABI；未裁减 FFmpeg codec。未修改 fvp / MDK 源码、SDK 缓存或其下载来源。六套额外 Lucide 字重本轮保留；当前 hosted 包没有干净的选择性字体注册入口。

## 静态与主机检查

- `cargo test --workspace`：350 passed、0 failed、72 ignored；忽略项仍需要其声明的设备或环境。
- `cargo clippy -p interop-core --all-targets -- -D warnings`、`cargo fmt --all --check` 通过。另单独通过 aarch64 Android core 检查。
- Flutter 的资源还原和 RuntimeInitialization 19 项、应用启动 / bootstrap 20 项、APK / manifest 9 项回归通过。
- `flutter analyze --no-pub --fatal-infos` 无问题，最终工具改动的定向分析无问题；Dart 格式检查通过。
- `dart tool/generate.dart --check` 通过 token、共享压缩资源、FRB 2.13.0 与 Dart builder 一致性。vendor/helper 原始来源与产物检查、共享打包生成器回归通过。
- 最终 APK 签名、ZIP CRC、三 ABI Flutter/Rust/AOT ELF 身份、16 KiB ZIP 对齐、共享资源摘要与唯一性检查通过。所有 16 份 64 位 ELF 的 PT_LOAD 对齐至少 16 KiB。
- 全部 ELF 无 `libass.so` 必需依赖，最终 APK 不含该库；三种 ABI 的 FFmpeg 均保留。Android Rust 库均不包含六产物的原始或压缩副本。六份共享 zlib 共 1,655,247 字节，manifest 1,070 字节。

## 实际 Android 运行

本轮新建两个只读隔离 AVD 实例：主控 `emulator-5558`、被控 `emulator-5560`，均为 API36 x86_64 Google APIs / SwiftShader；仅使用本轮转发 `15560`。既有 `emulator-5554` 保留，不覆盖其应用或停止其进程。

最终 **release APK** 安装并冷启动成功。私有 `bundled_servers/` 的六文件大小与 SHA-256 均匹配原始输入；停止本轮主控应用、故意破坏其 scrcpy 缓存，再冷启动后，原字节自动修复并通过摘要比较。

随后通过独立 debug 集成入口验证同一资源读取、压缩原生库与链接配置：

- H.264、H.265、AV1、VP8、VP9 均取得真实首帧，逐项完成一次暂停恢复、截图与停止。截图颜色数分别为 4917、5023、5087、4524、4631；使用 15 秒首帧功能超时，不把它当性能验收。
- 音频生命周期通过 ready、paused、resumed、stopped；确认收到 PCM、播放器进入 playing、播放时钟前进。`audibleContentVerified` 和 `speakerSamplesVerified` 仍为 false，不声称物理扬声器听音验收。
- 普通 main debug 入口启动后，MCP 热重启成功，运行时错误查询为空。

最初一次 `flutter drive --no-pub` 沿用了 release 构建过滤后的插件注册，因缺少 integration_test screenshot 方法失败；去掉 `--no-pub` 重新生成正常 debug 注册后完整五编码通过。该测试入口问题未通过跳过截图或放宽断言规避。

未验证 ARM32 / ARM64 真机安装和媒体运行，也没有在其他主控宿主重新整包编译。其他宿主的压缩内置资源通过本机 Rust / Flutter 原生初始化测试，不能外推为四宿主整包验收。

## 证据与清理

临时证据包括 `/tmp/connect-package-size-{universal,compressed}-build.log`、`/tmp/connect-package-size-{rust-tests,tool-tests-final,bootstrap-tests,analyze,generation}.log`、`/tmp/connect-package-size-elf-alignment.json`，以及 `/tmp/connect-package-size-{video,audio}/result.json`。

本轮只读 AVD、转发、测试应用和临时包按本轮身份清理；保留最终通用 release、来源压缩资产、当前验证日志及可复用编译缓存。APK 下载大小不等于安装后总占用。
