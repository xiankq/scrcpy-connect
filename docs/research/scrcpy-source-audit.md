# 当前原生媒体实现与 scrcpy 5.0.1 源码逐链路对照

研究日期：2026-10-23。对象为当前未提交的重构工作区，不是旧 fvp 实现，也不是某个已发布版本的保证。只修改研究文档，没有修改业务代码。

## 基线、证据与阅读入口

- scrcpy：项目 `servers/vendor/manifest.json` 固定的 `a60891aea193d92e7e5c3942700eca63f9d19a5f`（5.0.1）。本次下载完整源码并核对归档 SHA-256 `a0d699fc7388b8252416c49e6293639de39ab76a03e7302ddced56c284d45200`。
- 我们：`crates/adb`、`interop_core`、`packages/device_runtime`、`scrcpy_client`、`media_codec` 及当前实际 Flutter 引擎。FFmpeg 固定 `2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`。
- 上游源码只证明其实现；本地源码只证明分支和操作存在。没有用源码操作次数虚构延迟、功耗或故障发生概率。
- “确定缺陷”指可以从调用关系证明契约失配；“条件缺陷”指满足给定像素格式、切换序列等前提后发生失配；“风险”没有本次设备复现；“开销”不自动等于错误。
- 上游正式主控是桌面程序。Android/iOS 主控与它比较的是机制，不存在官方 Android/iOS 宿主的同条件性能基准。

详报分为三份，包含各项本地行号及固定版本上游链接：

| 专项 | 范围 |
| --- | --- |
| [桌面专项 D01–D24](scrcpy-source-audit-desktop.md) | Windows、Linux GPU 导入、同步、颜色、CPU 回退、内存与兼容 |
| [移动及 Apple 专项 A1–A18](scrcpy-source-audit-mobile-apple.md) | Android Surface、Apple CVPixelBuffer、生命周期、软解、硬解识别 |
| [传输及控制专项 T01–T29](scrcpy-source-audit-transport-control.md) | ADB、部署、启动、输入、控制读写、暂停、重建和回收 |

这些编号存在交叉证据，不应相加当作互不重复的缺陷数量。本文补充共有解码和音频，并给出整改顺序。

## 结论

当前已经移除了旧路径中的 fvp/MDK、HTTP 和 Matroska；压缩视频不经过 Dart。剩余主要差距集中在**渲染设备与解码设备的协作、平台生命周期、音频实时调节、控制协议完整性和生产观测**。把 Rust 换成 C/C++ 本身不会消除这些开销；其中一些是当前接口只能借用数据、Flutter 纹理只接收特定格式造成的。

最高优先级已经有实际故障证据：**当前 Android 普通 Release APK 打开投屏即 SIGABRT，R8 裁掉 JNI 回调 `onFrame/onPcm`；已在 Android16 x86_64 AVD 复现。** 根因与 ABI 无关，但用户 arm64 真机是否同一栈还需真机日志。详见[独立崩溃报告](android-release-media-crash.md)。

其余优先核查的正确性问题是：音频暂停绕过系统缓冲处理、部分 PCM 写入尾部丢失、硬件回读颜色属性丢失、Android Surface 清理竞态、Linux 纹理尺寸/缓存竞态，以及输入没有跨重建代际。不能把这些静态问题直接充当已复现的JNI abort根因。

## 实际数据路径与复制

### 视频压缩包

上游通常为：Android Java 编码 → scrcpy socket → adbd/官方 ADB → 客户端 socket → 直接读入 AVPacket → 引用排队 → FFmpeg → 平台纹理 → SDL 呈现。

我们桌面：相同 Java 编码 → adbd/官方私有 ADB → smart socket → Rust 视频 Vec → 同步借用的 MediaSource ABI → **复制至媒体库的 padded Vec** → Arc/AVBuffer 引用 → FFmpeg → 平台转换 → Flutter 纹理 → Flutter 合成。

我们移动：Java 编码 → adbd → Rust ADB 协议帧 payload → AdbStream 搬运 → Rust 视频 Vec → 同一份 ABI 入口复制 → FFmpeg。Android USB 还多一个 duplex 桥和搬运任务，细节见 T17/T18。

明确边界：

- C ABI 调用、Rust 函数调用、Arc clone、AVFrame/AVPacket ref 本身不等于整包或整帧像素复制。
- 当前 ABI 明确禁止持有借用字节，因此媒体库需要复制。消除这一份要改变所有权接口，不能只把函数搬到另一个语言。
- 本地 `scrcpy.rs:2704–2705` 分配并读入 payload；`media/native.rs:161–173` 借用调用；`media_codec/rust/src/lib.rs:718–733` 再分配、清零及复制；随后 `lib.rs:451–470` 用 Arc 保活同一份存储，没有再复制一次压缩包。
- 上游 [demuxer.c:136](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c#L136) 直接接收到 AVPacket，但 [packet_merger.c:20](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/packet_merger.c#L20) 在配置包合并时也会复制/移动数据。不能宣称上游所有字节始终零拷贝。

### 解码后的像素

| 宿主 | 当前较好路径 | 相对上游的额外操作/缺口 |
| --- | --- | --- |
| Android | MediaCodec Surface → SurfaceProducer → Flutter | 仍有系统 BufferQueue、纹理采样与合成；Surface 重绑会重开 decoder 并重播 GOP，cleanup 异步竞态；没有具体硬件 component 证据 |
| Windows | D3D11VA → VideoProcessor BGRA → shared handle → Flutter ANGLE | 默认 decoder device 独立于 Flutter；多 BGRA 中间面，跨显卡 CPU 回读/上传；上游使用 SDL device，但它自身也有 GPU copy |
| Linux VAAPI | VAAPI → DMA-BUF/EGL planes → RGBA FBO → Flutter | 每帧额外 RGBA pass 与 `glFinish`；没有按 Flutter GPU 选解码 render node；原版可直接以 NV12 纹理交 SDL |
| Linux NVIDIA | CUDA/NVDEC → CPU 下载 → swscale RGBA → GL 上传 | 有硬解但不是 GPU 直通，没有 CUDA/GL 互操作 |
| macOS / iOS | VideoToolbox → CVPixelBuffer → Flutter | 支持的 NV12 可不经 CPU 像素下载；但所审计 Flutter 引擎的矩阵处理有边界，软件回退逐帧分配和 CPU 色彩转换很重 |

上表是操作路径，不是实测排名。完整帧 RGBA 大小为 `width × height × 4`；以 1920×1080 举例，每帧约 7.91MiB、60fps 单向有效像素量约 474.6MiB/s。读、写、再次上传会分别消耗带宽，不能把这个算术值当作实际总线吞吐测量。

## 共有解码、队列与状态

| 编号 | 证据等级 | 发现及影响 | 本地证据与上游对照 |
| --- | --- | --- | --- |
| C01 | 确定额外复制 | 每个正常视频/PCM 包在 source→decoder 入口整包复制；入口存储先清零再覆盖 payload。压缩包不像旧 fvp 那样经过 Dart，但还未取得原版“读到解码包存储”的路径。 | `lib.rs:683–736`；上游 `demuxer.c:146–151` |
| C02 | 明确调度差异 | 队列上限 8 包/8MiB；满时 source 每 2ms 重试，最多 3s 后报 media_stall。worker 出队没有唤醒生产者的事件通知。满载时增加定时器/重复加锁/等待，可能向 ADB 和编码端传递背压。不是每帧固定增加 2ms。 | `lib.rs:27–28,631–633,715–716`；`media/native.rs:189–207` |
| C03 | 设计取舍 | 在解码之外保留完整 GOP，最多 8MiB，用于硬解故障和 Surface 恢复。payload 通过 Arc 共享，不再复制；但扩大常驻压缩数据、元数据引用和重播成本。队列、history、FFmpeg 内部及纹理内存不能只按单个 8MiB 计算。 | `lib.rs:44–75,528–546,603–613`；原版 decoder 无这份持续 GOP 历史 |
| C04 | 明确额外分配 | 我们每包 `av_frame_alloc/free`，发布时再次 clone/free latest；上游复用 decoder 的 AVFrame 和 frame buffer。增加小对象分配、引用计数与锁，量级需 profile。 | `lib.rs:404–407,480–490`；上游 [decoder.c:143](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L143)、[frame_buffer.c:8](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L8) |
| C05 | 条件风险 | 任何负 decode 结果第一次都触发软件重开和 GOP 重播，即使原本已经软件解码，或错误来自坏包/内存；未区分 EAGAIN。正常 receive 被完整 drain 后，send EAGAIN 不应常发，不能称已发生丢帧；但出现时不该判成硬件失效。 | `lib.rs:475–478,529–559`；FFmpeg [send/receive 契约](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavcodec/avcodec.h#L130)；原版 `decoder.c:198–219` 单列 EAGAIN |
| C06 | 确定兼容差异 | 配置完全相同就跳过重开，未传递独立 session 事件；缺上游针对 AV1 硬件新 session 必须重开的 workaround。相同尺寸 reset 也可能需要新的上下文，待 AV1 实机夹具验证。 | `lib.rs:499–517`、`scrcpy.rs:2616`；上游 [decoder.c:308](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L308) |
| C07 | 确定生命周期通知缺陷 | `finish()` 只投递一次 END，忽略返回结果；8 包队列已满时 native event 返回 retry，END 丢失，decoder 的 ended 永远不会因此变 true。核心自己的关闭/错误事件仍可能让上层退场，不能宣称整个应用一定永不回收。 | `media/native.rs:234–254`；`lib.rs:635–637,715–716` |
| C08 | 确定观测缺口 | native_ready/frame_count 在解码 publish 时置位，早于纹理导入、GL/D3D 转换和 Flutter 呈现。不能把它当屏幕出帧时间。持续转换错误通常不回传，详 D03/A14。 | `lib.rs:404–438`；平台失败分支详专项 |
| C09 | 明确状态延迟/开销 | 每输出 50ms FFI poll，构造 Map/解码字符串；首帧等待另有 10ms poll。主要增加就绪、诊断和转屏布局的反应时间，不是原生像素每帧被延迟 50ms。多路输出线性增加 timer/小对象工作。 | `controller.dart:130–141,144–207,209–225`、`native_controls.dart:41–68` |
| C10 | 确定启动开销 | 首次 open 与每次恢复都强制 32×32 snapshot。硬件帧先整帧下载后才缩小，有 GPU 同步、CPU 转换和 MethodChannel 返回，且仍不能证实 Flutter 实际显示成功。Android Surface 使用 PixelCopy 回读；桌面细节 D12。 | `portable_video.dart:175–179,404,425–440`、`lib.rs:934–977` |
| C11 | 条件正确性缺陷 | 硬件下载新 software frame 后未 copy props，却根据该 frame 的 colorspace/range 转色；丢失原颜色 metadata，影响截图和回退。多平台共同问题，详 D01/A2。 | `lib.rs:934–950,986–1001`；固定 FFmpeg `libavutil/hwcontext.c:448–491` |
| C12 | 性能机会，非上游独有缺陷 | 除 dav1d 以外 thread_count=1。软件回退时多核 slice 并行能力受限，但不能因此断言 scrcpy 默认更多线程：我们固定 FFmpeg 的默认 threads 也是 1。需要同版本、同编码 slice 结构 profile 后再选。 | `lib.rs:282–290`；固定 FFmpeg `options_table.h:220`、`pthread.c:49–63` |
| C13 | 确定兼容差异 | 缺原版 H.264 hardware `ALLOW_PROFILE_MISMATCH` 处理；部分主设备编码 profile 与硬件声明不匹配时可能更早退软。不是所有 profile 都应无条件绕过检查，需兼容夹具。 | 详 D14/A16；[上游 hwdec.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c) |
| C14 | 算法边界 | VideoDelayGuard 是到达时间减 PTS 的历史最低偏差，不是绝对端到端时延；阈值增长 800ms 连续 8 帧才 reset，冷却 4s。它看不到首次建立基线之前的积压，也不是 decode/GPU/compositor 延迟闭环；主从时钟慢漂移可能影响长期最低值。此项用于兜底，不能宣称极致延迟保证。 | `scrcpy.rs:33–37,2506–2548,2689–2691,2740–2777` |
| C15 | 明确缺失能力/取舍 | 我们没有可选按 PTS 平滑视频抖动的 regulator；到达即解码、最新帧覆盖是低延迟选择，弱网突发时可能不平滑。原版默认 video_buffer=0 也不启用 regulator，不能说原版默认总会缓冲或我们因此必慢。 | 上游 [scrcpy.c:900](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/scrcpy.c#L900)、[video_regulator.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/video_regulator.c) |
| C16 | 确定接口上限不一致 | Core及media source接受最大16MiB单包，decoder入口却拒绝超过8MiB的单包。8–16MiB合法输入会先被完整分配/接收，再在媒体库以media_decoder失败。大关键帧是否实际达到该范围未测；需要统一公开限制及错误语义。 | `scrcpy.rs:27,2701`、`media/mod.rs:17`、`media/native.rs:216–218`、`lib.rs:27,701` |

特别避免两个误判：原版当前也有 demux/decoder 两个线程及压缩包队列，不是每个包读到就同线程立即呈现；队列容量也不等于每次都会蓄满该容量。

## 音频：当前比视频更缺少实时系统机制

### 当前格式的利弊

当前只接受 48kHz、双声道、16bit PCM，目标 `audio_codec=raw`，不做宿主压缩音频解码。它省去目标压缩编码和宿主解码，也省相关 codec 包体；代价是持续有效音频 `48000 × 2 × 2 = 192000 B/s = 1.536Mbps`，不含 ADB/TCP/协议头。

scrcpy [客户端默认 Opus](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c#L23)，[服务器默认 128000 bit/s](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Options.java#L37)，也提供 raw。相对默认码率，PCM payload 是 12 倍；不能因少一个 decoder 就断言总延迟必低，弱网、ADB 竞争和传输重发可能更重要。

### 逐项发现

| 编号 | 证据等级 | 差异及后果 | 本地/上游依据 |
| --- | --- | --- | --- |
| S01 | 确定正确性缺陷 | 所有正常 setPaused 走 FFI `mc_set_paused`，只清 native 待写 PCM 队列；Android AudioTrack.pause/flush、Apple AudioQueuePause/Reset 在 MethodChannel 分支，正常 controller 不调用。系统已提交的声音可能继续播放；执行中的 write 也不因 Rust paused 标记立即中止。暂停时钟测试通过不能证明立即静音。 | `controller.dart:229–232`、`native_controls.dart:71–74`、`lib.rs:850–863`；Android Java:108–114/266–279；Darwin:187–195 |
| S02 | 确定数据完整性缺陷 | 平台 write 返回 0 或少于 length 时，native worker 不保存/重试尾部，直接处理下一包。四平台各有 80ms 写入限时；系统拥塞/中断可造成直接丢 PCM 与爆音。需要显式、可观测的低延迟丢样策略，而不是静默丢尾。 | `lib.rs:656–679`；Linux:192–213、Windows:104–145、Darwin:157–180、Android Java:266–279 |
| S03 | 确定机制缺口 | 没有实时 buffer 水位估计、平滑目标缓冲、长期采样钟漂移补偿、断续后恢复策略。平台 sample-rate 自动转换只能处理标称采样率/设备格式，不等于估计两台设备实际晶振漂移。长期表现需 soak 测量，不能预言几分钟必卡。 | 整个 PCM worker `lib.rs:643–679`；上游 [audio_regulator.c:15–57](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/audio_regulator.c#L15)、同文件 149–168/321–360 |
| S04 | 明确时钟语义差异 | position_us 是“该包 PTS + 本次接受字节时长”，不是 AudioTrack playback head、WASAPI IAudioClock、AudioQueue 或 ALSA 已播放帧计数。原生接收与 position 递增只证明提交推进，不能当 DAC/扬声器播放进度或 A/V 对齐证据。 | `lib.rs:671–678`；`portable_audio.dart:148–155` |
| S05 | 明确额外分配/复制 | audio reader 每包新 Vec，ABI 再复制。Android JNI 每包 Attach/GetEnv、new byte[]、SetByteArrayRegion，再 Java AudioTrack.write；缺 JVM attachment 时每包 detach。其他平台直接 native bytes→系统 buffer，少这一层 Java 数组。 | `audio.rs:559–566`、`lib.rs:718–733`、JNI:25–30/88–98 |
| S06 | 调度/缓冲取舍 | 8 包 native FIFO 对每包最大 4096B，相当于约170.7ms PCM容量；这不是固定延迟。之后 Android 最少 7680B（40ms，设备 minimum 可能更大）、Apple 3×3840B（60ms容量）、ALSA/WASAPI 请求20ms，均没有统一目标水位。不能直接把各容量全相加声称实测延迟。 | `lib.rs:27–28`、`audio.rs:530–539`；Android Java:201–213；Darwin:85–89；Linux:178；Windows:89–92 |
| S07 | 明确调度差异 | Windows/Android 空间不足按1ms sleep轮询，Linux按5ms snd_pcm_wait，Apple条件变量等待，最长80ms。worker 被卡时 native FIFO积压，source2ms重试，进而拖回 ADB；没有 SDL pull + regulator 那样的统一供样机制。 | 各平台 write；[上游 audio_player.c:12–38](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/audio_player.c#L12) |
| S08 | 明确生命周期缺口 | 输出设备在初始化选一次。Windows 无默认 endpoint 变化通知/设备失效重开；Linux ALSA default 打开失败无其他 backend 选择；Apple 未建立 audio route/interruption 恢复链路。系统库可能处理部分路由，不等于项目已实现并验证热插拔恢复。 | Windows Audio:62–109；Linux Audio:160–181；Darwin open/close |
| S09 | 明确控制差异 | 混音宿主上的 focus 是应用租约，返回 systemFocusVerified=false；不能当系统焦点或 ducking/interruption 证据。iOS AVAudioSession会激活并MixWithOthers，但未在最后输出结束时做对应 deactivate/系统中断状态上报。Android已有独立平台焦点策略，不能与桌面概括混称。 | `mixer_audio_policy.dart:21–38`、Darwin:72–77/197–205 |
| S10 | 较小 CPU 开销 | 非1.0音量逐样本 double乘法/截断；静音也会走全部样本和常规系统写入。可通过平台增益或SIMD改善，但不应把每秒96000样本的运算未经profile称成主要瓶颈。 | `lib.rs:646–654` |
| S11 | 架构额外开销 | 音频独立启动另一个scrcpy Java进程、独立JAR部署/连接/reader；上游一个server内启动video/audio/control。独立音源便于多窗口共享，不能简单合进每个窗口导致重复抓音，需保持每device音源所有权。 | `audio.rs:342–398`；详T12；上游 [Server.java](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Server.java) |

原版默认非FLAC约50ms目标 audio buffer、10ms输出buffer，是清楚的稳定性/延迟取舍，不是“它比我们固定多50ms”。见 [cli.c:3088](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/cli.c#L3088)、[options.c:72](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c#L72)。

也不能把“缺统一音视频主时钟”全算本项目相对原版的退步：所审计原版音频自调节、视频默认尽快呈现，并非播放器式严格audio-master排片。我们的明确差距是缺音频自调节与真实设备播放水位，而不是原版已经提供所有严格A/V同步。

## 启动、输入和资源：不应只盯 decoder

传输专项细节见 T01–T29，最值得带入总体设计的结论：

1. **输入应绑定 capture 代际。** 当前UI→FRB请求只有sessionId，画质重建保留逻辑ID，跨FRB迟到事件可能打到新capture。原版一个controller绑定一条具体连接，我们需要更强的多会话边界。
2. **控制读和写不能互相长期饿死。** 当前 biased actor 的连续发送与写等待会推迟ACK、设备消息和EOF处理。原版receiver独立线程。只是加大队列会把问题变成更长的尾延迟。
3. **桌面输入语义仍不完整。** scroll、hover、鼠标按钮、修饰键和repeat等不是渲染优化能补齐的；长IME文本还有全历史比较、move合并还保留每次Completer。
4. **本地暂停不等于停止目标编码。** 我们暂停时丢编码包、保留reader，恢复用RESET_VIDEO；原版继续解码保留最新帧。我们省掉暂停期间解码，但恢复多编码器重建和往返。另有上层暂停路径的refresh，具体序列详T22。
5. **启动上传/校验/探测是首帧成本。** 默认H264整屏已经避免必跑encoder枚举，但每次唯一JAR上传、进程身份验证仍在；应用窗口与显式codec/encoder更多步骤。上游也部署JAR，不能把“上传”本身说成我们独有；我们的desugar JAR更大、多角色进程让重复工作扩大。
6. **跨设备锁和退出证据仍需收紧。** 全局quality mutex扩大不同设备的等待；本地process reader结束不总是远端Java退出。重复恢复可能让资源成本累积，必须把远端身份和确认退出独立记账。

已核对、应排除的误报：repeat-previous-frame-after=100ms与上游默认相同；产品默认尝试burst，不是默认classic stop-and-wait；desktop smart socket已NODELAY；encoder catalog在同真实连接内缓存；正常Dart入口按device串行应用窗口启动。

## 优先处理与验证顺序

| 顺序 | 工作 | 验证信号 |
| --- | --- | --- |
| P0 | 修复已复现的Release JNI/R8阻断，并继续核对真机 | AVD已失败且栈明确；必须验证开R8的最终DEX及普通Release真实投屏/音频；真机栈单独核对 |
| P1 | 音频暂停与尾部数据契约、输入capture fencing、Surface清理同步 | 暂停后系统buffer停止/清空；partial write可控夹具；迟到输入不打新capture；trim/旋转/快速开关Surface压力 |
| P1 | 色彩metadata、Linux纹理缓存与尺寸原子性、平台呈现失败回报 | BT601/709/2020、full/limited色卡；GPU→CPU→GPU跨尺寸；实际Texture子树像素；失败能进入diagnostics |
| P2 | 解码设备对齐renderer、替换Linux每帧glFinish、Windows纹理同步协议 | 各GPU组合frame时间、CPU等待、导入失败；保持实际成像正确；不能只看FFmpeg hw=true |
| P2 | 去掉正常启动/恢复的全帧CPU读回依赖，建立呈现确认 | native decode/import/Flutter消费分段时间；正常首帧不强制GPU→CPU，调试截图仍按需可用 |
| P2 | 音频buffer regulator与实际播放水位、热插拔恢复 | 10–60分钟两设备时钟漂移、Wi-Fi burst/断续、耳机拔插、系统中断、目标延迟与XRUN/丢样计数 |
| P3 | source所有权可转移、内存池、减少JNI数组/反复thread attach、GOP恢复优化 | 分配数、RSS、CPU profile；稳定链路与故障链路分别对照，保持有界队列及取消可回收 |
| P3 | 桌面输入完整语义、进程共享与部署、锁粒度 | hover/scroll/buttons/meta/repeat；冷/热启动；多设备并发及远端残留进程 |

不建议先全面删除FFmpeg或抛弃Rust。当前确认的大部分问题在源所有权、平台纹理、声音时钟和生命周期；换语言会重新实现相同契约。先修正确性、建立同输入同GPU的基准，再决定是否为个别平台采用系统decoder直调。

## 本轮 Android 故障核查

用户报告：arm64、Android 16 真机，Android主控打开被控屏幕会退出。提供截图显示两次 `device.screen.state` 返回 `InteropException / device_error`，耗时320/367ms，时间09:58:24/27；截图没有Java FATAL或native signal、tombstone，不能把该查询错误当作闪退栈，也不能从ABI本身推定原因。

已使用API36 x86_64 AVD的普通Release复现点击“打开手机屏幕”后进程退出，SIGABRT栈位于JNI `nativeCreate`，明确缺失 `onFrame(II)V`、`onPcm([B)J`。R8 usage清单确认两回调被移除，mapping与栈中的混淆类对应。尚未进入解码，因此这次AVD故障不是硬解器性能/兼容问题。

已核对模拟器安装APK与交付 `build/verified/android-universal-release.apk` 的SHA-256完全相同：`eafaed0ffe680bc3c4ce1bba51bf6b52e46a01b81a5cdb46be523fe59feb6d3f`。此前普通Release仅做启动冒烟；历史Debug投屏通过不能替代普通入口Release投屏验证，当前Release媒体能力存在阻断。完整栈、最小触发与未实施的修复方案见[崩溃报告](android-release-media-crash.md)。
