# fvp 与 media_kit 替换评估

核查日期：2026-10-23。范围是 Flutter 主控的实时音视频播放；本次核查公开文档、发布包源码和原生下载脚本，没有安装替代依赖或完成设备 A/B。文中的“可支持”是上游接口或构建能力，“更低延迟／更省资源”须另有本项目运行证据。

## 上游调查结论

media_kit 的主要候选优势是：播放器核心 libmpv 及 Flutter 适配源码公开，可自行修改解码、缓冲、渲染和诊断路径；具有统一的 Player、视频组件、属性观察及截图接口。它适合做独立替代后端实验。**公开证据不足以认定它比现有 fvp/MDK 更低延迟、更稳定或包体更小，也不足以支持直接全量替换。** fvp 同样提供硬解、低延迟参数、Texture、截图和 native handle；MDK 官方还明确 Flutter 用户可免费用于商业软件，因此不能把“免播放器授权费”列为已证实的迁移收益。[media_kit 实现说明](https://github.com/media-kit/media-kit#implementation)、[fvp API 与功能](https://pub.dev/packages/fvp/versions/0.39.1)、[MDK 许可说明](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/README.md#license)。

## 版本快照

以下日期取 pub.dev API 的绝对发布时间，不能用页面“几个月前”作为版本证据。

| 对象 | 核查时最新 pub 稳定版 | 发布时间（UTC） | 说明 |
| --- | --- | --- | --- |
| fvp | 0.39.1 | 2026-10-15 | BSD-3-Clause Flutter 层；原生 MDK 另行下载 |
| media_kit | 1.2.6 | 2025-12-13 | 播放控制、FFI、事件、截图 |
| media_kit_video | 2.0.1 | 2025-12-02 | Flutter 视频控制器和平台纹理适配 |
| media_kit_libs_video | 1.0.7 | 2025-10-05 | 原生依赖聚合包；页面标注 unlisted |
| media_kit_libs_android_video | 1.3.8 | 2025-10-05 | 下载 Android libmpv v1.1.7 default 构建 |
| media_kit_libs_windows_video | 1.0.11 | 2025-03-24 | 下载 2023-09-24 原生构建，另带 ANGLE |
| video_player_media_kit | 2.0.0 | 2025-11-14 | 可选 video_player 适配层 |

来源：[fvp API](https://pub.dev/api/packages/fvp)、[media_kit API](https://pub.dev/api/packages/media_kit)、[video API](https://pub.dev/api/packages/media_kit_video)、[libs API](https://pub.dev/api/packages/media_kit_libs_video)、[Android API](https://pub.dev/api/packages/media_kit_libs_android_video)、[Windows API](https://pub.dev/api/packages/media_kit_libs_windows_video)、[video_player 适配 API](https://pub.dev/api/packages/video_player_media_kit)。

发布包源码核查通过 pub.dev archive 在内存中读取，未修改依赖。media_kit 1.2.6 archive SHA-256 为 `ae9e79597500c7ad6083a3c7b7b7544ddabfceacce7ae5c9709b0ec16a5d6643`；media_kit_video 2.0.1 为 `afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d`。下文源码路径均指对应发布包；GitHub main 仅作为方便阅读的交叉链接，不能将尚未发包的修改归给稳定版。[1.2.6 archive](https://pub.dev/api/archives/media_kit-1.2.6.tar.gz)、[2.0.1 archive](https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz)。

## 架构、平台与渲染

fvp 通过 Dart FFI 调用 libmdk，提供 video_player 适配和直接 `mdk.Player` API；平台插件管理渲染目标。media_kit 原生端通过 Dart FFI 调用 libmpv，由 media_kit_video 管理 Flutter Texture 与原生视频输出。两者都不等于直接接收 scrcpy packet 的解码器；把 HTTP URL 换给 media_kit 仍保留现有封装、传输和 demux 工作。[fvp 设计](https://pub.dev/packages/fvp/versions/0.39.1#design)、[media_kit 实现](https://github.com/media-kit/media-kit#implementation)。

| 维度 | fvp / MDK | media_kit / libmpv | 对本项目的含义 |
| --- | --- | --- | --- |
| 主控平台 | Android、iOS、Windows、macOS、Linux；上游另列 HarmonyOS | Android、iOS、Windows、macOS、Linux、Web | 常规五端覆盖重叠，不是新增当前原生主控能力 |
| Web | fvp 未列 Web | HTML video 元素，不使用 libmpv；codec 由浏览器决定 | Web 声明不等于现有 Matroska、ADB/native 桥接可迁移 |
| 硬件解码 | 默认启用，允许指定 decoder 顺序 | 视频控制器可配置 hwdec，平台默认不同 | 应记录实际 decoder，不能只比较两个包的默认值 |
| 渲染 | fvp 声明 Windows D3D11、Apple Metal、Linux/Android OpenGL | 发布实现以 libmpv 渲染 API／平台视频输出接 Flutter Texture；Windows 依赖另带 ANGLE | 跨平台不等于同一 GPU 路径，零复制和 GPU 成本均需测 |

来源：[fvp 平台及渲染声明](https://pub.dev/packages/fvp/versions/0.39.1#features)、[media_kit 平台与 Web](https://github.com/media-kit/media-kit#platforms)、[media_kit 渲染实现说明](https://github.com/media-kit/media-kit#implementation)。这些是上游能力说明，未作为本项目平台验收。fvp README 的“比 libmpv 更低 CPU/GPU/内存”也是作者声明，不能作为同输入实测结果。

media_kit_video 2.0.1 的 `lib/src/video_controller/native_video_controller/real.dart` 默认 `vo=libmpv`、`hwdec=auto`，通过 MethodChannel 创建并销毁平台输出。Android 有独立控制器，应单独核查。Texture id／Rect 可观察和首帧 Future 提供了 Flutter 接入接口；它们不是 Android Surface 或 MDK renderer handle 的通用替代，现有 native handle 调用不能直接沿用。[发布源码包](https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz)、[native 控制器阅读入口](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit_video/lib/src/video_controller/native_video_controller/real.dart)。

同一发布包的 Android 控制器默认 `vo=gpu`，真机默认 `hwdec=auto-safe`，检测到模拟器时默认使用 `hwdec=no`；显式传入 hwdec 可覆盖该选择。Surface 变更处理还会调用 `seek(currentPosition)`，这对不可 seek 直播输入是应验证的路径，不代表本次已经观察到失败。Android 的首帧 Future 存在收到有效 videoParams 尺寸即完成的路径，因此名称中的 rendered 不能直接解释为 GPU／物理显示证据。[2.0.1 发布源码](https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz)、[Android 控制器阅读入口](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit_video/lib/src/video_controller/android_video_controller/real.dart)。

## 实时 HTTP Matroska 与低延迟

media_kit 1.2.6 的 `lib/src/player/native/player/real.dart` 初始化明确设置 `cache=yes`、`cache-on-disk=yes`，并将 `demuxer-max-bytes`、`demuxer-max-back-bytes` 都设为 `PlayerConfiguration.bufferSize`。**不能据此说它必须积攒完整缓冲才播放**：字节上限不是固定启动等待或固定延迟；但这些默认值显然不能直接当作实时遥控的已调优配置。需要在 `open` 前通过 NativePlayer 属性接口配置并回读实际值。[1.2.6 发布源码](https://pub.dev/api/archives/media_kit-1.2.6.tar.gz)、[对应源码阅读入口](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit/lib/src/player/native/player/real.dart)。

发布包 `platform_player.dart` 的 bufferSize 默认值为32MiB；这是配置上限，不能当作每个 Player 一定立即分配的 RSS，也不能折算为已测的固定延迟。[1.2.6 发布源码](https://pub.dev/api/archives/media_kit-1.2.6.tar.gz)。

mpv 官方说明其通常会为普通播放缓冲，低延迟需显式关闭增加等待的功能；`low-latency` profile 的内容随 mpv 版本可能变化。`untimed` 仅适用于无音频且输入按固定速率供数等受限条件，不应统一套给带音画同步的会话。可研究的变量包括 cache、cache-pause、demuxer readahead、decoder threading、hwdec、同步和 framedrop，但必须针对**包内实际 mpv 版本**逐项验证可用性与含义，不能把当前 stable 手册直接当作旧 Windows binary 的运行保证。[mpv 低延迟说明](https://mpv.io/manual/stable/#low-latency-playback)、[mpv 选项](https://mpv.io/manual/stable/#options-cache)。

libmpv/FFmpeg 的容器、协议支持与播放器的实时调度是不同层级。官方称支持宽泛格式并允许 URL 输入，但本次未用本项目 unknown-length Matroska、逐 Cluster 供数、独立 PCM 端点验证首帧、长静止、旋转、新 generation、EOF／断线恢复，因此 HTTP Matroska 可作为最小迁移实验输入，不能宣称兼容与低延迟已经通过。[media_kit URL 接口](https://pub.dev/documentation/media_kit/1.2.6/media_kit/Media-class.html)。

## 截图、首帧与销毁证据

media_kit 1.2.6 的 `Player.screenshot` 返回 JPEG、PNG 或原始 BGRA；native 实现调用 mpv `screenshot-raw` 后编码。它可以提供“播放器已有可截图帧”的证据，但不证明 Flutter 合成器提交、GPU 成像或物理屏幕显示；不能把该结果直接标成 `mdk.snapshot`。属性观察、log stream 和 native handle 可帮助诊断，但已检查的公开 Player／VideoController 接口没有等价于本项目 MDK decoder 输入／onVideo／renderer 各边界的逐帧 trace；属性变化次数也不是实际帧数。[截图 API](https://pub.dev/documentation/media_kit/1.2.6/media_kit/Player/screenshot.html)、[mpv screenshot-raw](https://mpv.io/manual/stable/#command-interface-screenshot-raw)、[发布源码](https://pub.dev/api/archives/media_kit-1.2.6.tar.gz)。

**`await player.dispose()` 不等于 native 已销毁。** 1.2.6 的 `NativePlayer.dispose` 先等待 Dart／事件侧清理，然后启动一个未 await 的 `Future.delayed(Duration(seconds: 5), () => mpv_terminate_destroy(ctx))`。因此 dispose Future 提前完成；不能据此宣称切库修复了 native 资源释放回执、关闭后立即复用或快速重连时的资源重叠。是否需要上游改动或自管等待，应先定义本项目要求的回执层级。[发布源码 `real.dart` 87–108 行](https://pub.dev/api/archives/media_kit-1.2.6.tar.gz)、[对应源码阅读入口](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit/lib/src/player/native/player/real.dart#L87)。

同一发布源码 `open` 会在设置 pause=false 后主动发出 playing=true，不能用 playing 事件作为首帧证明。首帧 Future 也需追踪各平台的完成位置；没有后续成像证据时，不应扩大为“已显示给用户”。

## 许可与可修改性

| 层级 | 已核查事实 | 决策边界 |
| --- | --- | --- |
| Flutter 包装层 | fvp BSD-3-Clause；media_kit 系列仓库 MIT | 两者均较宽松，但不能替代 native 许可 |
| MDK 核心 | 官方分列部分开源模块，并提供 SDK 授权；Flutter 用户包含 key，可商业使用 | 换库的确定收益是核心源码可见／可自行修复的空间，不是已知许可费减少 |
| libmpv 核心 | 默认总体 GPL；排除 GPL-only 文件可构建 LGPL，`-Dgpl=false` 是便利开关；链接依赖仍影响最终许可 | 不可仅凭“mpv 是 GPL”断定 media_kit 全部原生包 GPL，也不可凭包装层 MIT 断定全部 MIT |
| 实际 binary | Android v1.1.7 mpv 构建脚本有 `-Dgpl=false`，还需核对 FFmpeg 与其他静态输入；Apple 当前构建仓库区分 default/full 与 encoders-gpl | 应按发布包实际引用的构建、flavor、依赖和链接方式留存对应源码／notice；main 文档不能证明旧产物组成 |
| 编解码专利 | FFmpeg 官方将软件版权许可与专利问题分列 | 切为 MIT 包装层或 LGPL libmpv 不等于获得 H264/H265 等专利授权 |

来源：[fvp license](https://pub.dev/packages/fvp/versions/0.39.1/license)、[media_kit MIT](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/LICENSE)、[MDK README](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/README.md#license)、[mpv Copyright](https://github.com/mpv-player/mpv/blob/master/Copyright)、[Android v1.1.7 mpv 构建](https://github.com/media-kit/libmpv-android-video-build/blob/v1.1.7/buildscripts/scripts/mpv.sh)、[Apple build 许可说明](https://github.com/media-kit/libmpv-darwin-build#commercial-use)、[FFmpeg 许可与专利说明](https://ffmpeg.org/legal.html)。本研究不将开源／闭源、商业／非商业、GPL／LGPL、codec 专利混作一个判断。

## 原生分发、包体与维护

media_kit 的分包可以选 audio-only 或 video+audio，后者已含音频，两者不应混用。原生分发并未因为 pub lock 自动变成跨平台单一、完整可复现来源：

- Android libs 1.3.8 下载 `libmpv-android-video-build/releases/download/v1.1.7/default-{ABI}.jar`，脚本校验 MD5；它不是当前构建仓库最新 main。需再建立交付包自己的 SHA-256、构建输入与 source 对应关系。[发布 archive](https://pub.dev/api/archives/media_kit_libs_android_video-1.3.8.tar.gz)、[build.gradle](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/libs/android/media_kit_libs_android_video/android/build.gradle)。
- Windows libs 1.0.11 固定下载 `mpv-dev-x86_64-20230924-git-652a1dd.7z`，MD5 为 `a832ef24b3a6ff97cd2560b5b9d04cd8`，另下载 ANGLE v1.0.1；发布包不能解释成 mpv 最新引擎。[Windows 发布 archive](https://pub.dev/api/archives/media_kit_libs_windows_video-1.0.11.tar.gz)、[CMake](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/libs/windows/media_kit_libs_windows_video/windows/CMakeLists.txt)。
- iOS/macOS libs 1.1.4 的发布 Makefile 锁定 libmpv-darwin v0.6.0 的 video-default 产物并校验 SHA-256；与 Android/Windows 下载器的摘要机制不同，需按平台追溯。[iOS 发布 archive](https://pub.dev/api/archives/media_kit_libs_ios_video-1.1.4.tar.gz)、[macOS 发布 archive](https://pub.dev/api/archives/media_kit_libs_macos_video-1.1.4.tar.gz)。
- Linux 默认用发行版安装的 libmpv，应用自行打包时另有分发责任；pub 版本不能锁定用户机器的 mpv/FFmpeg 组合。[Linux 官方说明](https://github.com/media-kit/media-kit#gnulinux)。
- fvp 0.39.1 已有 `FVP_DEPS_URL`／`FVP_DEPS_SHA256` 固定原生来源与 SHA-256 的机制，因此“切 media_kit 才能固定 native 来源”不成立。[fvp 下载参数](https://pub.dev/packages/fvp/versions/0.39.1#upgrade-dependencies-manually)。

fvp 作者称每架构约增加 10 MB；media_kit 可裁剪 FFmpeg、按 ABI 拆 APK，但本次没有同 Flutter release、ABI、codec 集合、符号剥离和分发形式的产物对比。下载压缩包大小、多 ABI APK、安装体积和运行 RSS 不能互相代替，故无包体优势结论。[fvp footprint 声明](https://pub.dev/packages/fvp/versions/0.39.1#features)、[media_kit 安装说明](https://github.com/media-kit/media-kit#installation)。

维护证据应分 Dart 包、Flutter 渲染适配和 native binary。核查时 media_kit main 为 `c533e446755f51cf53c7e57aea873f2aa5355f81`（2026-08-30，修内存泄漏），但最近稳定 Player 包仍是 2025-12；fvp main 为 `741d454076d619618fefb92d9b8eea891e0cc02b`（2026-10-22），稳定包为 2026-10-15。上述只能说明时间与修订差距，不能凭 stars、issue 数或最后提交日期推出维护质量；尤其不能把未发布的修复当作安装当前稳定包后的收益。[media_kit 提交](https://github.com/media-kit/media-kit/commit/c533e446755f51cf53c7e57aea873f2aa5355f81)、[fvp 提交](https://github.com/wang-bin/fvp/commit/741d454076d619618fefb92d9b8eea891e0cc02b)。

## 本仓库的使用方式与迁移范围

本节检查对应仓库提交 `1bbcbcd8eba368e3c361f3e05aaff780733f039e`，没有修改运行代码或依赖。项目交付主控对象为 Android、iOS、macOS、Windows；Linux 当前有开发与播放器接入，不能将库的 Linux/Web 支持扩大为本产品已交付平台。[平台责任规格](../../designs/prod/compatibility.md#主控与被控的边界)、[ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md)。

### 现有接入已经使用 MDK 底层能力

- 根 workspace、应用、Bridge 均声明 `fvp: 0.39.1`，生产视频不是仅通过 `video_player` 播放。它直接建立 `mdk.Player`，设置 Matroska、最小探测、即时输出 `fps=-1`、进程级 renderer 待呈现帧数1、平台 decoder 优先级与软件 slice 后备，并自行管理 Texture、快照和状态确认。[视频适配器](../../packages/interop_bridge/lib/src/media/fvp_video_player.dart)、[根依赖](../../pubspec.yaml)、[锁文件](../../pubspec.lock)。
- 设备音源使用独立的 MDK audio-only Player，读取 48kHz 双声道 PCM，默认 packet buffer 为150ms；音频焦点、后台服务与多设备归属由项目既有协调器管理。更换库需要保留这些责任，不能用播放器默认焦点策略覆盖它们。[声音适配器](../../packages/interop_bridge/lib/src/media/fvp_audio_player.dart)、[声音输出所有者](../../packages/interop_bridge/lib/src/media/portable_audio.dart)。
- 相册视频使用 `video_player`；应用入口仅为 Windows/Linux 注册 fvp 后端。Android/iOS/macOS 的这条预览路径目前仍由对应平台实现提供。若只换远控而保留桌面预览 fvp，会同时分发两套 native 媒体栈，必须测量净包体，不能把新旧库视为已经互相替代。[启动入口](../../app/lib/main.dart)、[相册视频预览](../../app/lib/pages/devices/workspace/gallery/preview/widgets/video_preview.dart)。

### 已有性能证据不支持直接把换库当作延迟修复

2026-10-19 的受控实验在 Android 16 x86_64 AVD、相同 H.264 576×1280 录像与供数节拍下，对比 HTTP 和 MDK append 输入。相同 AMediaCodec 后端时，两者输入到 onVideo P50 都约94ms；同一 HTTP 换为 FFmpeg slice，P50 约1.6ms。后续软件组 HTTP/append 的 P95 中位数分别约1.757/1.683ms。这使该环境的主要等待范围缩小到 AMediaCodec 解码/输出边界，不能归因于 HTTP 容器层，也不能外推为所有物理设备或所有帧率的成本。[实验环境、指标与反证](mdk-memory-input-experiment.md)。

这些指标是输入进入到 MDK 回调的延迟，不是端到端显示、触控往返或 Flutter/GPU 提交时间。本次没有运行 media_kit，因此没有可用于断言“更快”“更省电”或“更稳定”的同口径实测。尤其 Android media_kit 默认在模拟器选择软件解码：直接拿默认结果比较可能主要反映软件解码与当前 AVD codec 的差异，而非两库在相同后端下的差异；还应分别核对软件线程模式，不能假定两者均为 slice。

### 接口可复用，但迁移需要超过两个适配器的修改

| 接缝 | 可以保留的部分 | 需重新实现或核对的部分 |
| --- | --- | --- |
| 媒体输入 | Rust Matroska、localhost HTTP、凭据与 generation 边界 | 新后端持续无 EOF、稀疏帧、非 seek 输入的 probe/cache/暂停恢复语义；库更换本身不移除 mux/HTTP |
| 视频输出 | `VideoPlayerPort` 的 open、pause、snapshot、release 操作；现有 Flutter `Texture` 页面 | 将 media_kit VideoController 的异步 id/尺寸变化接到现有输出契约，验证旋转、重新建 Surface 与不可 seek 流 |
| 首帧与截图 | 按真实可读像素确认首帧、失效 generation 隔离 | 当前32×32核验及有界截图需重新映射；`NativeVideoReadback` 借用 MDK C 表和 Android `MdkGetPlayerVid`，不能复用到 mpv handle |
| 逐帧测量 | Rust 同一单调时钟、按源 PTS 匹配的测量原则 | `NativeFrameTrace`、Rust `media_trace.rs` 是 MDK ABI 实现，需新观测点；mpv 公共属性或尺寸事件不能自动替代逐帧回调 |
| 生命周期 | 输出串行操作、取消、清理准入上限和声音焦点/后台协调 | 新库 stop/pause/销毁真实回执；未结算截图和纹理操作必须先排空，Future 返回不直接等于 native 已删除 |
| 协议与 UI | 会话、源、窗口租约与控制输入归属 | Bridge/Rust 的 `backend=fvp` 与 UI 的 `evidence=mdk.snapshot` 检查需要一致更新；不能仅修改名字来伪造证据 |
| 原生分发 | 现有按宿主构建与产物核验方法 | 三处 Dart 依赖、平台注册、Android fvp 专用链接裁剪、native 来源/摘要/许可证、对应源码与验收基线 |

接缝依据：[VideoPlayerPort](../../packages/interop_bridge/lib/src/media/video_player_port.dart)、[AudioPlayerPort](../../packages/interop_bridge/lib/src/media/audio_player_port.dart)、[视频输出协调和像素核验](../../packages/interop_bridge/lib/src/media/portable_video.dart)、[回读](../../packages/interop_bridge/lib/src/media/native_video_readback.dart)、[trace](../../packages/interop_bridge/lib/src/media/native_frame_trace.dart)、[Rust MDK ABI](../../crates/interop_bridge/src/media_trace.rs)、[Rust 声音回执](../../crates/interop_core/src/audio.rs)、[UI 首帧判断](../../app/lib/pages/devices/workspace/remote/remote_presentation.dart)。

历史 Android release 基线中 ARM64 的 FFmpeg/MDK 合计约10.18MiB；三 ABI 的 FFmpeg/MDK 合计约30.25MiB，另有 fvp/JNI 等开销和当时的 libass。这些是固定历史产物的组成，不是 media_kit 的可节省量，当前工具链已排除未使用的 libass。不同模式、ABI、压缩方式和新旧产物不可混算。[历史体积测量](android-media-package-size.md)、[当前 fvp 分发契约](../implementation/repository-tooling.md#社区原版-fvp-0391)。

## 项目建议与最小验证范围

**现阶段保留 fvp；把 media_kit 作为解决特定 MDK 问题或要求完整开源核心时的候选。** 开源可维护性是直接成立的优势；远控时延、功耗、包体和释放确定性的收益均需实测。更多点播/字幕功能对本项目实时画面与 PCM 主路径的价值有限。

如果开展下一步实验，先做隔离的 `VideoPlayerPort` 对照入口，复用相同 Matroska HTTP 夹具与供数节拍，不同时改传输结构。至少比较 fvp 现配置、media_kit 默认配置、media_kit 明确低延迟配置；报告实际 codec/硬解路径，在软件和硬件组内分别对照。使用 Android 物理主控补足 AVD 证据，并检查 iOS/macOS/Windows 的真实渲染路径。

比较首个编码包到实际可读首帧、相同 PTS 的 P50/P95、静止前最后一帧是否及时出现、连续运行 CPU/RSS；要回答交互体验仍需独立测量显示或触控往返。性能窗口内不运行截图轮询，避免测量本身改变负载。对五种现有视频编码及 PCM、快开快关、多窗、暂停恢复、旋转、断线/换代、后台与焦点恢复、截图和释放后资源增长分别验收。包体比较使用同 Flutter 版本、release 模式、同 ABI 集合的完整包，并确保最终移除了旧后端后再计净收益。

这是候选验证范围，不是当前已完成测试或新产品规则。若没有测得用户关心指标的改善，也没有被 MDK 核心不可修改阻塞的具体问题，不建议承担全面迁移成本。
