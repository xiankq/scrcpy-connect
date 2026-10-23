# scrcpy 固定源码审计：Android、macOS、iOS 媒体路径

日期：2026-10-23。本文是当前工作区的源码研究快照，不修改业务代码，不把源码推论当作设备验收。

对照 scrcpy 5.0.1 / `a60891aea193d92e7e5c3942700eca63f9d19a5f`；源码归档 SHA-256 `a0d699fc7388b8252416c49e6293639de39ab76a03e7302ddced56c284d45200`。本项目使用新 `media_codec`，fvp/MDK 已移除。上游没有 Android/iOS 主控宿主，因此移动端比较的是等价链路职责，不是声称存在一套官方移动端插件。

Flutter 引擎补充审计使用本机 SDK `/home/xiankq/flutter` HEAD `abaf9c523780a608bd46686fd5e53740a07077f8`。远端构建 SDK 是否完全相同需要核实，涉及 Flutter 引擎行为的结论带此版本条件。

判定：**确认缺陷**表示控制流/契约问题可由源码闭合证明；不表示已经在真实设备复现。**明确差异/开销**不自动等于需要修改。**条件风险**需要特定输入、驱动或时序才能触发。

## 实际路径与已有改进

| 宿主 | 当前视频热路径 | CPU 像素整帧复制 |
| --- | --- | --- |
| Android MediaCodec | Rust 压缩包 → FFmpeg NDK MediaCodec → releaseOutputBuffer(render) → SurfaceProducer → Flutter 合成 | 正常 Surface 路径没有本项目主动的 CPU 像素读回；仍有平台缓冲、GPU 合成和同步 |
| Android 软件回退 | Rust FFmpeg 软件帧 → swscale RGBA 新缓冲 → ANativeWindow_lock → 逐行 memcpy → SurfaceProducer → Flutter | 至少 RGBA 生成、RGBA 到 window 的复制 |
| Apple VideoToolbox / 支持的 NV12、BGRA | FFmpeg opaque frame → retain CVPixelBuffer → Flutter copyPixelBuffer retain → Metal import → Flutter 合成 | 正常匹配格式没有主动 CPU 像素复制 |
| Apple 软件帧或其他硬件格式 | FFmpeg 帧 → 必要时硬件读回 → swscale RGBA 新缓冲 → 新建 BGRA IOSurface CVPixelBuffer → CPU 逐像素交换 R/B → Flutter | 有整帧转换、整帧交换复制；硬件不匹配格式还多硬件读回 |

依据：[Rust 解码与发布](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:395)、[Android 平台输出](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:55)、[Apple 平台输出](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:105)。macOS、iOS 平台入口都 include 同一份 Darwin 实现。

上游 macOS 并非“把软件 YUV 一律复制到 CPU RGBA”：匹配 VideoToolbox NV12 时，`interop_videotoolbox.c` 用 SDL 的 Metal pixel-buffer 属性直接包装 IOSurface；软件路径用持久 YV12 texture + `SDL_UpdateYUVTexture`，由 SDL/GPU 做 YUV 显示。不能将 SDL 或 FFmpeg 本身等同于多一次 CPU 整帧复制。[上游 VT 导入](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_videotoolbox.c#L32)、[上游软件导入](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_software.c#L114)。

## A1. Apple NV12 直接纹理路径丢失颜色矩阵选择

**确认的条件性正确性缺陷，优先级高。** 本项目在 `darwin/Classes/MediaCodecPlugin.mm:113–118` 对 NV12 video/full range 直接 retain；没有根据 `AVFrame.colorspace` 转换或选择纹理颜色矩阵。所审计 Flutter 引擎 iOS/Darwin `FlutterDarwinExternalTextureMetal.mm:202–214` 把 NV12 固定解释为 BT.601 limited/full；macOS `FlutterExternalTexture.mm:104–107` 同样固定 BT.601。两个实现只区分 range，不读取输入的 BT.709 / BT.2020 矩阵。

因此，当输入为 BT.709 / BT.2020 NV12，传递 CVPixelBuffer 附件并不足以解决此引擎中的矩阵选择，硬解播放可能出现色偏。截图若走另一条 CPU 颜色转换路径，截图与屏幕颜色还可能不一致。正常色块计数/首帧验收不能证明颜色正确。未进行标准色卡实测；也不能断言所有目标编码器当前都输出 BT.709。

上游 `interop_videotoolbox.c:100–104` 每次包装时将 `frame->colorspace` / `color_range` 转成 SDL colorspace，并设置 `SDL_PROP_TEXTURE_CREATE_COLORSPACE_NUMBER`；不会因使用 VideoToolbox 而主动丢掉矩阵。[本项目透传](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:113)、[Flutter iOS/Darwin 源码](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/darwin/graphics/FlutterDarwinExternalTextureMetal.mm#L201)、[Flutter macOS 源码](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterExternalTexture.mm#L104)、[scrcpy 颜色设置](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_videotoolbox.c#L100)。

## A2. 共有硬件读回路径没有复制 AVFrame 颜色属性

**确认缺陷，影响所有调用此函数的硬件读回路径。** `rust/src/lib.rs:934–950` 新建空 software frame 后只 `av_hwframe_transfer_data()`，没有 `av_frame_copy_props()`；但 `986–996` 后续从这个空属性帧选择 colorspace / color_range。固定 FFmpeg `libavutil/hwcontext.c:448–491` 分配临时帧、传数据、复制宽高、move ref，不复制源颜色属性。

结果：源 full-range 会按非 JPEG range 转换；源 BT.601 / BT.2020 可能被高度启发式 BT.709 / BT.601 取代。影响 Apple 非直接支持格式回退和硬件截图；其他宿主共用 CPU readback 也适用。软件解码直接转换路径没有这一次属性丢失。未做色卡复现。

[本项目读回](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:934)、[本项目矩阵选择](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:986)、[固定 FFmpeg 实现](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavutil/hwcontext.c#L448)。

## A3. Android Surface 销毁通知异步排队，不能保证先停止解码再销毁

**确认生命周期契约缺陷；异常表现需时序复现。** Java `onSurfaceCleanup():225–226` 只向公共单线程 worker 排入 `nativeSetSurface(null)` 就返回。Flutter `FlutterRenderer.java:749–754` 同步调用此通知，返回后立即 `cleanup()` 关闭 ImageReader。Rust decode worker 在排队任务真正执行前仍能 `av_mediacodec_release_buffer(render=1)`，因此仍可能向旧 Surface 渲染。

NDK 持有 ANativeWindow 引用只能维护 native window 引用寿命，不能使已释放的 ImageReader consumer 保持可渲染。可能出现弃用 Surface、输出失败及额外软件回退。此路径与 Activity 普通前后台切换不同，尤其要覆盖后台内存压力 trim。

[本项目回调](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:224)、[Flutter Surface 生命周期契约](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/android/io/flutter/view/TextureRegistry.java#L215)、[Flutter 实际清理顺序](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/android/io/flutter/embedding/engine/renderer/FlutterRenderer.java#L737)。

## A4. Android 未处理 SurfaceProducer 不支持 crop/rotation 的路径

**条件性兼容缺口。** 本项目没有查询 `producer.handlesCropAndRotation()`，也没有从 Surface crop/rotation 元数据构造纹理变换，只把 FFmpeg 解析后的可见宽高用于 `setSize()`。

Flutter 当前契约明确：API 29+ 常见 ImageReader 路径不自动处理 crop/rotation，插件需自行处理。固定 FFmpeg MediaCodec `mediacodecdec_common.c:612–623` 会解析 crop 并缩小可见 width/height，但对于 Surface 输出，缩小 AVFrame 的数字不等于消费者已裁切实际图像。带编码 padding / 非零 crop 的设备可能露出边缘、缩放失真。

不应据此声称普通转屏已坏：scrcpy server 通常已经在编码前处理旋转，纯宽高切换可以正确。需要单独验证非对齐尺寸、带非零 crop 输出的真实编码器。

[本项目 Surface 建立与大小变更](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:219)、[Flutter 契约](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/android/io/flutter/view/TextureRegistry.java#L252)、[固定 FFmpeg crop 解析](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/mediacodecdec_common.c#L612)。

## A5. Android 每次 Surface 设置都关闭解码器并重放整个 GOP

**明确额外工作，含条件性显示风险。** `mc_set_native_window():875–882` 没有判断 window 是否相同，始终提交新 sequence 并同步等待。decode worker `596–619` 关闭上下文、重新打开、从最近关键帧重解整个 GOP，且 replay 每帧调用 `publish()`。Java 尺寸改变 `255–264` 必经一次此调用；Surface available/cleanup 也如此。

代价包括 codec 销毁/重建、设备上下文重新初始化、重复解码、逐个回放到 Surface、live packet 等待。重放是获得当前完整画面的合理恢复手段，但若只需绑定新 Surface，成本比原位重绑高；且没有只展示 replay 最后一帧的控制，存在短暂历史画面/BufferQueue 压力风险。不能把重复帧数当成实时有效帧数。

若 `setSize` 返回同一 ANativeWindow，当前也无法跳过重建。上游普通 macOS/Linux/Windows纹理尺寸变化不会统一无条件关闭硬解上下文；不过它对 AV1 的新 stream session 有特定重建 workaround，不能概括为“上游永不重建”。

[重绑入口](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:870)、[整个 GOP 重播](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:596)、[Java 重绑](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:255)、[上游 AV1 特例](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L308)。

## A6. Android Surface 不可用时会主动打开软件解码并重放

**条件性 CPU/耗电开销。** 仍附着的输出收到 `nativeSetSurface(null)` 时，worker 一样执行 `backend.open(false)`；Android `open()` 只有 `native_window != 0` 才选择 `_mediacodec`，因此此时改为软件解码并可重播历史 GOP。它没有等待 Surface 返回再恢复，也没有在无 Surface 时停止视频解码。`paused` 只阻止呈现，不阻止解码。

当业务保持后台 capture/output，内存压力释放 Surface 后可能从低 CPU 硬解变成持续软解，再在 Surface 恢复时重建硬解、再重播一次 GOP。若上层已经 dispose 输出则不适用。此项不能由“后台仍能保持远端会话”自动推断成已测电耗。

[硬解选择条件](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:242)、[窗口事件处理](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:596)、[暂停仍解码](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:440)。

## A7. Android MediaCodec 没有打开系统 low-latency 模式

**明确配置缺口，收益未实测。** 共有代码设置 `AV_CODEC_FLAG_LOW_DELAY`，Android 仅为私有选项设置 `ndk_codec=1`。固定 FFmpeg `mediacodecdec.c:434–444` 设置 mime / 宽高 / operating-rate，并没有把 LOW_DELAY 映射成 MediaFormat `low-latency`；本项目也没有其他配置入口。

因此不能说“用了 AMediaCodec 就已开启 Android 解码器的极低延迟模式”。系统 low-latency 特性支持、codec 实现和流格式都需要实机验证。此项是移动端特有配置缺口，上游没有 Android 主控可供直接对比。

[本项目 LOW_DELAY 与 ndk 配置](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:282)、[固定 FFmpeg MediaFormat 设置](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/mediacodecdec.c#L434)。

## A8. “hardwareAccelerated=true”目前只能证明 opaque 硬件接口格式

**确认诊断语义不足。** Rust `416–438` 以 `AV_PIX_FMT_FLAG_HWACCEL` 判定，`decoderName` 是 FFmpeg AVCodec 名称加 hardware device 名。Android `h264_mediacodec/mediacodec` 不包含具体 `c2.qti.*` / `c2.android.*` / `OMX.*` component。

固定 FFmpeg MediaCodec `common.c:790–813` 先按 mime/profile 查 component；NDK 找不到 JVM codec 列表时允许按 MIME 创建，再 `getName()`。具体 component 信息存在底层，但没有进入本项目状态。使用 `c2.android.*` 软件 component 时仍可得到 MediaCodec opaque Surface 帧。

Apple 也应谨慎：固定 FFmpeg `videotoolbox.c:847–854` 对 H.264 要求硬件，对 HEVC 使用 EnableHardware 而非 RequireHardware，允许 VideoToolbox 内部软件实现。仅看 CVPixelBuffer / VT 格式不能证明 HEVC 的物理硬解，需实际 session property 或系统证据。已验收的 H.264 Mac 硬解不能外推所有 codec。

[本项目判定](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:416)、[FFmpeg component 选择](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/mediacodecdec_common.c#L790)、[FFmpeg VT 硬件要求](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/videotoolbox.c#L847)。

## A9. Apple 软件回退每帧新分配 IOSurface，并进行 RGBA→BGRA CPU 交换

**确认额外开销。** `publishFrame():120–140` 每次调用完整 `mc_copy_rgba()`，其中 `av_malloc` 一张 RGBA 图；然后 `CVPixelBufferCreate` 新 IOSurface，逐像素循环交换 R/B，而非直接输出 BGRA 或复用 pool。没有因为 Flutter 主线程已积压而跳过本次软件转换。

1080p60 一张 4 B/px 图的单向吞吐就是 497,664,000 B/s（约 475 MiB/s）；这只是按尺寸计算的字节量，不是测得带宽/耗时。当前路径先写 RGBA、再读 RGBA 写 BGRA，且要维护新 PixelBuffer 分配，4K 时字节量再乘四。iOS Simulator 当前是软件回退，因此此问题不是纯理论分支；但不能用 Simulator 排名真实 iPhone 性能。

上游软件路径保持 YUV420 平面，以 `SDL_UpdateYUVTexture` 更新持久 texture；不会在本项目这一层逐帧生成两份 4 B/px 输出。上游 SDL 的具体后端仍可能有自身分配/上传成本。

[本项目 CPU 交换](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:120)、[RGBA 分配](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:965)、[上游纹理复用和 YUV 更新](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_software.c#L121)。

## A10. 平台呈现转换在解码线程执行，丢弃过时帧前已付出转换成本

**明确链路差异。** Rust 每 `receive_frame` 后同步调用 `publish → frame_ready`；Apple 软件转换、Android 软件 swscale / ANativeWindow lock / memcpy 都阻塞同一 decode worker。Apple `_notificationPending` 只合并主线程通知，不能撤销已经完成的逐帧 CPU 转换。

上游 decoder 把 AVFrame 引用交给单槽 `frame_buffer`；新帧覆盖未显示旧帧，UI 消费最新帧时才做 texture import/upload。渲染跟不上时，它可以跳过旧帧的 texture update。我们虽然同样保留 latest 和合并通知，但重活发生得更早，慢的软件输出会反过来阻塞压缩包消费。硬解 Apple retain 路径很轻，不能和软件分支等价估算。

[同步回调](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:440)、[Android 软件呈现](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:61)、[上游单槽 frame_buffer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L47)、[上游跳过重复 UI 事件](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L480)。

## A11. PCM 暂停走 FFI，绕过平台音频暂停/清空实现

**确认控制链路缺陷。** `MediaCodecController.setPaused():229–232` 直接调用 `NativeControls → mc_set_paused`。因此正常 controller 不会进入 Android MethodChannel `setPaused` 的 `AudioTrack.pause/flush`，也不会进入 Apple `setPaused:` 的 `AudioQueuePause/Reset`。Rust 只清除尚未输出的 PCM packet，并拒绝继续输出；OS 已接收的音频继续播放至队列排空。

Android buffer 至少 7,680 B ≈40 ms（系统 minimum 可能更大）；Apple 三个 3,840 B buffer，容量总计60 ms。这里只是队列容量，不是固定实际尾音长度，更不是整体音频延迟。暂停时可能留尾音；平台 `_audioPaused` / Java `paused` 不随 FFI 变化，已经进入 PCM callback 的本次写入也不能凭 core 状态及时终止。

[正常控制入口](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/controller.dart:229)、[FFI 控制](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/native_controls.dart:71)、[Android 被绕过的平台分支](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:108)、[Apple 被绕过的平台分支](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:187)、[Rust 只清 PCM 入队](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:850)。

## A12. Android PCM 每包经过 JNI byte[] 分配复制与线程 attach/detach

**确认额外开销。** 每次 `pcm_ready()` 构造 `Environment`，Rust worker 尚未附着 JVM 时 AttachCurrentThread，结束 DetachCurrentThread；每包 `NewByteArray + SetByteArrayRegion` 复制原生 PCM，再 Java `AudioTrack.write(byte[])`。这是音频字节，视频硬解帧没有这次 Java 数组流转。

可以研究 AAudio/Oboe 或稳定附着线程 + direct ByteBuffer，但需权衡 API、设备路由、低延迟模式是否实际启用，不能单以“Rust/JNI 多一层”虚构毫秒数。当前 48kHz stereo s16le 原始音频吞吐为 192,000 B/s，单纯这次复制通常远小于整帧视频转换，但高 packet rate 下分配/线程附着仍值得测量。

[JNI 输出](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:22)、[每包数组](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:88)。

## A13. 平台音频是阻塞式“交给设备”，缺硬件播放位置反馈

**明确差异，公共音频报告另行展开。** Android 最长80 ms非阻塞write重试循环，每次不足 sleep1；Apple callback 最长80 ms等空闲 AudioQueue buffer。超过deadline只返回已经写入长度，Rust把其余字节丢弃；没有重排剩余尾部。若partial length非4字节对齐，后续立体声采样边界也需谨慎（正常AudioTrack PCM16 stereo通常返回frame对齐量）。

本项目 `position_us = packet.pts + written/192000` 是已提交位置，非 DAC 已播放位置，也没有从 AudioTrack timestamp / AudioQueue current time 推回消费速率。不要据此声称已经具有设备时钟校正或准确 A/V 同步。

[Android 写入](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:266)、[Apple 写入](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:157)、[共有提交位置](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:656)。

## A14. 解码成功计数先于平台导入/显示成功，持续播放失败不可观测

**确认错误传播缺口。** Rust `publish()` 在调用平台 callback 前已增加 frame_count、native_ready 并 clear_error。Apple 若 pixel-buffer 分配/转换失败，`publishFrame:144` 直接返回；Android若 nativeWindow lock/convert 失败也没有回报通道。FFI仍能看到“已解码/ready”，不能区分有纹理像素和实际被屏幕扫描显示。

上层启动确实有 `_verifyFrame()` 快照检查，因此不能说启动完全没有像素证据；但后续持续导入失败没有状态反馈，已有一次snapshot验收也不代表后续每帧纹理成功。上游 interop返回false会经screen/decoder sink/error路径传播，并非一律吞掉。

[提前更新状态](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:405)、[Apple 静默返回](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:143)、[Android 无错误回报](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:61)、[上层像素验证](/home/xiankq/git/scrcpy-connect/packages/scrcpy_client/lib/src/portable_video.dart:425)、[上游错误返回](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L985)。

## A15. 运行时尺寸和错误状态按50 ms轮询，不直接跟每帧走

**明确控制面开销/时效差异。** Controller20 Hz通过FFI读状态、创建map/解码字符串/比较，再发必要metadata。此设计避免Dart视频字节和每帧JSON，属于明显进步；但颜色/错误/转屏尺寸变更的控制面感知最多增加一个轮询周期加isolate调度，启动waitForFrame另用10 ms轮询。

实际像素纹理由native驱动，不必等50 ms才能绘制下一帧；不能把50 ms直接算入所有视频帧延迟。转屏布局会短时间使用旧aspect ratio，直到metadata到达。上游在消费帧的同一UI路径更新尺寸并导入纹理。

[轮询](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/controller.dart:130)、[尺寸事件](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/controller.dart:178)、[上游尺寸和纹理同次处理](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L970)。

## A16. 硬解兼容 workaround、线程策略与恢复策略不同

- **H.264 profile 兼容缺口**：上游 `hwdec.c:205–210` 设置 `AV_HWACCEL_FLAG_ALLOW_PROFILE_MISMATCH`，说明部分只暴露 constrained baseline 的硬件其实能解 baseline；本项目没有这个flag。固定FFmpeg Android component筛选也只在该flag开启后才按unknown profile重试。可能造成不必要的软件回退，需特定GPU/codec验证。[上游](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L205)、[FFmpeg Android重试](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/mediacodecdec_common.c#L790)。
- **软件解码并行度边界**：本项目除dav1d外强制 `thread_count=1 + FF_THREAD_SLICE`；上游只设置LOW_DELAY，其他线程参数保留FFmpeg默认。固定FFmpeg的默认threads也为1，因此不能将单线程直接计作相对上游的性能退步。软件回退时是否值得启用slice并行，应按codec、slice结构、CPU及分辨率测量；线程更多也不保证延迟更低。[本项目](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:282)、[上游context](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L15)。
- **中途硬解出错恢复成本**：我们的任意decode负返回第一次都会 `open(true)` +当前GOP重播，甚至实际早已内部软件回退也会尝试再开软件。上游只在硬件context且尚未成功解帧时进行send阶段自动软件fallback，后续错误终止。我们的恢复能力更强，但有GOP缓存内存、重复解码、重复帧统计和瞬间CPU峰值；应分别评价恢复能力和极致稳态开销。[本项目](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:528)、[上游](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L198)。
- **AV1新session workaround缺口**：上游明确每个新SESSION为AV1硬解重建，因为FFmpeg不会自行重新初始化；本项目config事件若kind/w/h/extradata完全相同直接return，没有独立stream session identity。RESET_VIDEO等同尺寸重启存在风险，未设备复现，主报告共有核心项应去重。[本项目](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:498)、[上游注释和重建](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L308)。

## A17. 小分配、锁与线程边界

当前每packet `av_packet_alloc`、`av_buffer_create`，每次decode分配AVFrame，每次publish释放再clone最新AVFrame，Apple再acquire clone并retain CVPixelBuffer。clone/ref不是复制整帧像素，但分配、引用计数、mutex和跨线程wake确实存在。上游 decoder预分配一个frame、frame_buffer预分配两个frame，交接时ref/move_ref复用结构。需要按packet rate测量allocator成本，不能将所有clone误算成像素复制。[本项目](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:446)、[上游预分配](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L143)、[上游frame buffer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L8)。

Apple每个native decoded frame先替换最新pixel buffer，再通过main dispatch合并通知；Flutter随后经过自身raster/compositor调度。Android SurfaceProducer ImageReader在main handler处理image available，再调度Flutterengine frame；当前本机引擎还保留最多两个image pending队列。这些是Flutter集成成本，不能简单量化为固定1/2帧；上游同样有UI事件、GPU呈现和vsync，公平比较应追踪实际时间戳和调度。[Apple通知](/home/xiankq/git/scrcpy-connect/packages/media_codec/darwin/Classes/MediaCodecPlugin.mm:150)、[Flutter ImageReader队列](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/android/io/flutter/embedding/engine/renderer/FlutterRenderer.java#L527)。

## A18. 首次打开即闪退：普通Release的JNI/R8故障已复现

主代理在API36 x86_64 AVD上使用普通Release两次复现首次打开投屏SIGABRT。R8移除了JNI查找的Session `onFrame/onPcm`，两次GetMethodID在pending exception下导致ART abort。发生在实际解码前，详见[独立崩溃报告](android-release-media-crash.md)。用户arm64真机是否同栈仍需真机日志。

用户真机截图只有 `device.screen.state / device_error`，没有该设备logcat/tombstone，真机根因尚未确认。A3 Surface销毁竞态一般要求trim/重绑时序，不能用它解释本次AVD的JNI abort，亦不能直接用来解释所有首次open崩溃。

首次路径是 Java Session创建SurfaceProducer → worker `Session.open()` → JNI `nativeCreate()` → `mc_create()`/`mc_attach()` →首个key包FFmpeg解码 → release到Surface → Flutter ImageReader/纹理导入。Java `74–90` 只捕获RuntimeException；native SIGSEGV/SIGABRT、Rust release `panic=abort`、驱动进程故障不会被转换成该错误结果。需要区分Java FATAL EXCEPTION、应用native tombstone、codec2/vendor服务死亡、Flutter GPU/driver错误，先按崩溃栈定位阶段，再与本报告缺口关联。

另一个可证差异是 JNI_OnLoad只保存本插件的JavaVM，未调用FFmpeg `av_jni_set_java_vm()`；FFmpeg NDK路径明确允许缺JVM并按MIME创建codec，因此这本身不能判成崩溃。其影响是失去Java codec列表/profile筛选信息，底层所选component更不透明。此前AVD通过不能排除真实厂商codec、特定GPU、SurfaceProducer后端的差异。

[Java打开与异常边界](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:74)、[JNI首次创建](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:103)、[Rust panic策略](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/Cargo.toml:16)、[FFmpeg缺JVM的NDK兼容分支](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/mediacodecdec_common.c#L795)。

## 结论与验证顺序

先修A18已经复现的Release阻断，再修正确性和可观测性：A1/A2色彩、A3 Surface销毁屏障、A4 crop夹具、A11音频暂停链路、A14平台错误传播；性能重点A5/A6窗口重绑及后台软解、A9/A10软件帧呈现、A7真正low-latency模式、A12音频JNI。不要用CPU架构、API名字、一次正常首帧或Simulator结果替代真实硬件证据。

本轮运行了A18的Android16 x86_64 AVD普通Release崩溃实验，没有修改或生成业务代码。未覆盖真实Android多厂商codec / crop、真实iPhone硬解、Apple颜色准确性、内存压力Surface重建、HEVC内部硬件使用属性。这些是待验证项，不应写成已验收。
