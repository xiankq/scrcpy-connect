# Android MDK / FFmpeg 缩包可行性

基线测量对应提交 `8853d975b00abb157b55d05bf3f4a794fef84416`。共享资源、字幕库链接与压缩候选的构建约束见[Android 打包](../implementation/android-packaging.md#构建与核验)。

核查日期：2026-10-19。本文包含既有 debug 产物检查、上游资料研究、ARM64 release 辅助分析及三 ABI release 交付基线构建，没有构建裁剪版、安装应用或完成设备验收。用户要求通用 APK，单 ABI 数据仅用于拆解来源，不能替代交付包体积。当前依赖规则仍以[工具链契约](../implementation/repository-tooling.md#社区原版-fvp-0391)为准；以下候选不代表已采用的新规范。

## 实测基线

检查对象为 `app/build/app/outputs/flutter-apk/app-debug.apk`，262,755,323 字节，SHA-256 `24197483b81f62914e23712491a8990d2bd7820aa37d7c5f5f65930efc4b53a4`。该包包含三个 ABI；下表只统计包内 `lib/arm64-v8a/`，这些条目以 ZIP STORE 保存，表中大小同时为 APK 内占用。

| 库 | 字节 | MiB |
| --- | ---: | ---: |
| libffmpeg.so | 8,346,872 | 7.960 |
| libmdk.so | 2,325,896 | 2.218 |
| libass.so | 1,467,232 | 1.399 |
| libfvp.so | 389,584 | 0.372 |

四项合计约 11.95 MiB，不含 C++ 运行库。此前三 ABI 的 FFmpeg / MDK / fvp 合计约 31.12 MiB，不是单个 ARM64 安装包中这三项的成本。本次没有把下载归档、缓存内 `.dsym` 或未进入 APK 的 `libdav1d.so` 算入安装包。

读取本机 fvp 0.39.1 SDK 的 ARM64 `libffmpeg.so` 内嵌配置，已包含 `--enable-small`、`--enable-lto`、`--disable-debug` 和 `--disable-doc`；ELF 无 `.debug*` / `.symtab`。其功能白名单仍覆盖大量字幕、图片、音视频 codec、封装、滤镜和网络协议，包括项目远控不使用的 HLS、FTP 等。它已经经过通用精简，不能把再次 strip 或打开 small 当成新的主要收益。官方 [avbuild](https://github.com/wang-bin/avbuild/tree/30ba3796c1c3cadad5afa9542d476945b9876c45)提供 lite 构建及 `config-lite.sh`，但仍需与本次实际配置比较，不能仅改用“lite”名称就推断会变小。

## 研究基线的使用边界

- [视频适配器](../../packages/interop_bridge/lib/src/media/fvp_video_player.dart)明确将输入设为 Matroska，经本机 HTTP 打开；Android 优先 `AMediaCodec:async=1`，保留 `FFmpeg:thread_type=slice` 软件后备。
- [视频 codec 模型](../../crates/interop_core/src/media/codec.rs)处理 H.264、H.265、AV1、VP8、VP9。仅保留 H.264 会缩减现有能力，不能作为透明的体积优化。
- [音频适配器](../../packages/interop_bridge/lib/src/media/fvp_audio_player.dart)同样使用 Matroska；[封装器](../../crates/interop_core/src/media/matroska.rs)输出 `A_PCM/INT/LIT`，当前[采集链路](../../crates/interop_core/src/audio.rs)请求 raw PCM。
- 当前远控封装没有字幕轨。Android 普通[视频预览](../../app/lib/pages/devices/workspace/gallery/preview/widgets/video_preview.dart)使用平台 `video_player`；[应用入口](../../app/lib/main.dart)只在 Windows / Linux 将其后端替换成 fvp。因此可研究 Android 专用的窄 FFmpeg 集合，但不能把它原样应用到需要通用视频预览的桌面后端。

这些使用点只能确定初始保留集合。MDK 的动态符号、像素转换、重采样、截图及媒体信息探测仍可能要求相应库和实现，不能把一组未经运行验证的 configure 参数称为可交付最小配置。

## 候选与限制

### 去掉字幕库

MDK 官方[分发说明](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/README.md#distribute)明确：不使用字幕渲染时 libass 可选。对本次 ARM64 包，成功去掉该库的文件占用收益约为 1.40 MiB；三 ABI 总计约 2.42 MiB。

但本次直接检查 **APK 内** `libfvp.so` 的 ELF 动态段，`DT_NEEDED` 同时包含 `libmdk.so`、`libffmpeg.so` 和 `libass.so`。`libmdk.so` 自身没有直接依赖 libass，不足以证明 fvp 插件可以不带它。仅配置 Gradle `jniLibs.excludes` 删除 libass，会留下缺失的必须依赖。

本机 SDK `FindMDK.cmake` 的 Android 分支在发现 libass 时，将其作为 imported target 加到 mdk 的 interface link libraries。因此可行候选是在不含 libass 的 SDK 上重新配置、编译 fvp 插件，再核对最终 APK 的 `DT_NEEDED` 和真实启动、播放。不能修改 pub 缓存或只事后删除 APK 条目。

### 定制 FFmpeg

官方 [FFmpeg Runtime](https://github.com/wang-bin/mdk-sdk/wiki/FFmpeg-Runtime)说明 MDK 使用 FFmpeg 进行解封装、封装和软件解码，支持替换运行库，并将构建入口指向 avbuild。这给出了保留 MDK、替换 FFmpeg 的接口依据。

候选是从当前匹配的 FFmpeg / avbuild 构建出发，先保留 HTTP / TCP、本项目 Matroska 解封装、现有五类视频所需解析与解码、PCM、必要的转换和重采样；逐组去掉无关协议、格式、编码器及滤镜。保留软件后备可避免因系统 decoder 缺失而直接失去原有播放路径。若要进一步移除软件后备，需要单独评估兼容范围。

必须核对动态加载符号、SONAME、ABI、NDK API 和 16 KiB 页对齐；普通 FFmpeg 构建默认产生多个 libav 库，不保证能直接替换 fvp CMake 当前期望的单个 `libffmpeg.so`。具体缩减量需要对照构建与运行测量，本次不承诺百分比或目标大小。

fvp 0.39.1 原版[下载器](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/cmake/deps.cmake)支持 `FVP_DEPS_URL` 和 `FVP_DEPS_SHA256`。这是向它提供定制 SDK 归档的现有接口，不需要修改 hosted 包源码；采用定制归档会改变项目当前直接继承上游 SDK 的策略，实施时应同步工具链责任文档。

### 调整 MDK 或替换媒体后端

本次 MDK 核心交付的是预编译库；官方[构建工作流](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/.github/workflows/build.yml#L37-L46)另行 checkout 核心仓库并使用 `CLONE_PAT`，公开 SDK 仓库的[CMake 入口](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/CMakeLists.txt#L32-L44)依赖未包含的核心源码。本次未找到可供本项目直接重编完整核心的公开路径。Dart tree shaking 和 R8 无法按 codec 裁掉这个预编译 `.so` 内部的实现。仅在运行时选择 AMediaCodec 也不会移除包内 FFmpeg；当前 Matroska 解封装和 PCM 路径仍使用它。

Android 改用系统 MediaCodec / AudioTrack 是更大的架构候选，可减少对 MDK / FFmpeg 的依赖，但需要重建媒体输入、纹理、截图、音频输出和生命周期适配，并重新证明 decoder 支持和软件后备策略。其净收益应扣除新适配器体积；不能把当前约 11.95 MiB 全部当成已实现的节省。此次未实施或验收该路线。

## 结论与后续验证

建议以用户要求的三 ABI 通用 release 建立交付基线，单 ABI 用于辅助定位。完整包测量后发现 Rust 公共产物重复比单独移除 libass 的体积更大，建议优先实验 Rust 嵌入产物消重、共享打包及无损压缩，然后检查字体、libass 和 Android 专用 FFmpeg 的逐组裁剪。候选收益仍需实际构建量化。

候选包应检查 ZIP、ELF 依赖、ABI 和页对齐，再覆盖现有五编码播放、系统 decoder 与软件后备、PCM 声音、截图、旋转、暂停恢复、后台及资源释放。构建成功只证明链接和打包，不代表物理设备或其他主控宿主已验证。此次没有修改依赖声明、构建配置或产品行为。

## ARM64 release 完整基线与其他主要占用

用户继续询问约 140 MB 的来源后，实际在 `app/` 执行 `flutter build apk --release --target-platform android-arm64 --analyze-size`，使用既有 release 签名，没有修改源码。Flutter 3.47.6 / Dart 3.13.5；构建输出约 88.6 秒。该阶段 `app-release.apk` 为 **51,294,946 字节（51.3 MB / 48.919 MiB）**，SHA-256 `189dc90f169d3b68f84320236810bc3199d42fd7c05f4476258942672daeb903`。构建通用包前将其保留为 `app/build/app/outputs/flutter-apk/app-arm64-release.apk`，

该 ARM64 包通过签名、ZIP、ELF 和16KiB对齐检查，未安装运行。

以下统计来自最终 APK 的 ZIP 条目大小，不是 SDK 缓存或中间产物体积：

| 项目 | APK 内 MiB |
| --- | ---: |
| Rust 核心 libinterop_bridge.so | 13.587 |
| Flutter release 引擎 libflutter.so | 11.204 |
| FFmpeg | 7.960 |
| Dart AOT libapp.so | 7.876 |
| MDK | 2.218 |
| 全部 assets | 1.797 |
| libass | 1.399 |
| C++ 运行库 | 1.195 |
| 全部 DEX | 1.131 |
| JNI、fvp、其余资源和 ZIP 开销 | 0.551 |

历史 `/tmp/connect-final-main-apk.json` 回执对应 147,239,422 字节（140.419 MiB）的 **x86_64 debug** 包；该文件已不在当前产物目录，不能用当前包的细项冒充它的精确分解。该三 ABI debug 包中，单套 x86_64 Flutter 引擎为 38.226 MiB，ARM64 为 37.030 MiB；共享的 Dart debug kernel 与 isolate snapshot 占 APK 40.486 MiB。release 包不含这些 debug 数据，Dart 改为 AOT。该 ARM64 debug 包还包含约 14.534 MiB 的 Vulkan validation layer，release 中不存在。因此空包比较必须注明架构和 debug / release 模式，140 MiB 历史包与 48.919 MiB 新包并非同模式、同架构的优化前后对照。

### Rust 内嵌产物占一半，且 JAR 存在重复

对新 release 包中的 Rust ELF 逐字节匹配仓库固定产物，得到：

| 产物 | 出现次数 | 合计字节 |
| --- | ---: | ---: |
| scrcpy-server-v5.0.1 | 2 | 5,910,184 |
| companion.jar | 2 | 115,382 |
| 四种被控 ABI helper | 各 1 | 1,093,196 |
| 总计 | | 7,118,762 |

嵌入产物合计 **6.789 MiB，约占 Rust ELF 的 49.97%**，位于约 7.123 MiB 的 `.rodata` 中；`.text` 为 5,278,580 字节。scrcpy 的两处偏移为 `0xbc395` / `0x3a6b84`，companion 为 `0x38dd9e` / `0x67858d`，每处均匹配完整文件，不只是命中相同字符串。

基线中 scrcpy 与 companion 各通过 `const SERVER: &[u8] = include_bytes!(...)` 引入；额外完整副本共3,012,783字节（2.873MiB）。这是当时二进制的候选收益上界，后续资源打包规则见[Android 打包](../implementation/android-packaging.md#构建与核验)。

另一个候选是无损压缩后内嵌、部署前恢复原始字节。只读内存 zlib level 9 测试中，单份 scrcpy 产物从 2,955,092 字节降到 968,185 字节，companion 从 57,691 降到 29,007，四 helper 合计从 1,093,196 降到 599,970；这尚未扣除解压代码和运行成本，也未实现产物摘要与部署校验，不能当作已实现节省。应保留原始供应链输入及精确还原字节。

[helper 选择](../../crates/interop_core/src/remote_helper.rs)按被控设备 ABI 进行，主控与被控 ABI 可以不同，不能为了缩小主控包而只保留主控同架构 helper。

### 字体仍有小规模冗余候选

release 已将 MaterialIcons 从约 1.57 MiB 裁到 1,824 字节，将主 Lucide 字体从 925,600 裁到 30,088 字节。但 `lucide_icons_flutter 4.0.0` 声明的六套 `LucideVariable-w100` 至 `w600` 字体仍以接近完整内容进入包，ZIP 占用合计约 1.324 MiB；本次未在项目源码发现显式引用这些字重族的证据。是否可改为按需资源或调整依赖仍需核对动态图标与视觉使用，未修改 pub 缓存或字体。

## 用户交付口径：三 ABI 通用 release 实测

用户明确需要多架构汇集 APK 后，执行 `dart tool/android.dart build --abi universal`。实际包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`，构建约 113.84 秒。该阶段通用包为 **142,854,555 字节（142.9 MB / 136.237 MiB）**，SHA-256 `630e77df116e0b8d63dd641e9ecef3776e87fa0a3a254087abb87ca7a2db5b32`。工具自带的签名、ZIP 完整性、三 ABI、ELF 与 16 KiB ZIP 对齐检查全部通过，没有安装运行。

这证明正式通用包本身约为 140 MB，不能将该量级仅归因于 debug，也不能将 ARM64 的 51.3 MB 报为用户要求的交付体积。

| 内容，三 ABI 合计 | APK 内 MiB |
| --- | ---: |
| Rust 核心 | 39.939 |
| Flutter 引擎 | 31.867 |
| Dart AOT，含框架、业务和依赖 | 24.659 |
| FFmpeg | 24.438 |
| MDK | 5.813 |
| C++ 运行库 | 3.179 |
| 共享 assets / DEX / 其余资源 | 3.149 |
| libass | 2.418 |
| JNI / fvp | 0.509 |
| ZIP 开销 | 0.267 |

分别检查三种 ABI 的 Rust ELF，均完整匹配两份 scrcpy、两份 companion 以及各一份四种被控 ABI helper。三套 Rust ELF 内的这些产物合计 **21,356,286 字节（20.367 MiB）**；不同原始产物各保留一份时共 **4,105,979 字节（3.916 MiB）**。同一字节内容重复保存的部分合计 **17,250,307 字节（16.451 MiB）**。

因此，在通用 APK 中将这些与主控 ABI 无关的公共执行产物改为共享资源、让三种 Rust 架构复用，是比仅消除各 ELF 内的常量副本更完整的候选。它需要调整资源加载和部署接缝；文件字节差额不是已完成优化，也未扣除适配代码成本。保持四种被控 ABI helper，不按主控 ABI 丢弃能力。共享资源再压缩的净收益同样需构建验证。

本次没有构建同 Flutter 版本、同三 ABI 模式的空应用，因此不把泛指的“空包 20 MB”作为已测对照数据。
