# scrcpy 客户端低延迟路径与 MDK 的额外等待边界

2026-10-19。范围是客户端收到压缩包后的处理，不评价被控编码器、网络往返或物理屏幕扫描。本文只做源码与公开契约研究；设备对照及性能验收由对应实施记录承担。

**可确认的差异是官方客户端直接消费已有边界的压缩包，并显式开启低延迟解码；本项目将同样的包交给通用容器播放器。现有证据不能把约一帧等待直接归因于 HTTP、未知长度 Cluster、H264 parser 或 B 帧。** 官方路径确实省去容器探测与解封装，但省掉几个函数本身不能解释 94ms；应检查哪个边界等待了下一次供数。

## 固定版本与证据层级

- 本仓库 [vendor manifest](../../servers/vendor/manifest.json) 固定 scrcpy 5.0.1 源码提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`。上游 annotated tag v5.0.1 的目标经 GitHub API 复核与该提交相同。内置 JAR 是原 Java 源码经标准 desugaring 构建的产物，SHA-256 `201fa96f6643e08fce7fb750e6bec30dc7aa6862b369c88ca82b4d1c65b0903a`，不与官方 release 原始 JAR 字节混同；当前来源链见 [vendor 说明](../../servers/vendor/README.md)。[上游固定源码](https://github.com/Genymobile/scrcpy/tree/a60891aea193d92e7e5c3942700eca63f9d19a5f)
- 客户端比较使用同一 scrcpy 提交，不能沿用旧版本 `video_buffer.c` 或“官方只支持软件解码”的描述。该版本默认 `hwdec_mode=AUTO`，具体硬件路径仍依赖宿主、渲染后端与运行选择。[options.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c#L20-L30)
- FFmpeg 行为参考 n7.1，固定提交 `b08d7969c550a804a59511c7b83f2dd8cc0499b8`。**这不是 MDK 0.39.0 内置 FFmpeg 版本或其补丁的确认**，仅用于验证开源路径是否必然等待下一帧。
- 本项目样本使用原版 fvp 0.39.1 / MDK 0.39.0；HTTP 与 append 的同录像六轮、109 共同 PTS 结果见 [内存输入实验](mdk-memory-input-experiment.md)。其 94ms / 163ms 是输入调用进入至原生 `onVideo`，不含此前 ADB 与编码链路，也不代表面板延迟。下一帧供数后约 0.5～0.7ms 才回调是相关性线索；本研究没有重跑该实验。

## 官方 socket → packet → decode → render

| 边界 | 固定源码事实 | 对比意义 |
| --- | --- | --- |
| socket → AVPacket | `demuxer.c` 读取协议 codec/session 元数据、12 字节包头，再精确读取声明长度的 payload；PTS、CONFIG、KEY 标志来自协议。不是通过原始 Annex B 字节流寻找下一张图的起点。 | 已有完整包边界，不需要先转成 Matroska 再恢复它。 |
| CONFIG → 媒体包 | H264/H265 的 CONFIG 暂存并前置到下一个媒体包；CONFIG 本身没有普通媒体 PTS，不送作视频帧解码。 | 这是等待第一张媒体包所必需的初始化，不是每张媒体包都延迟一帧。 |
| packet → decoder | `sc_decoder_push` 引用包、入队并 signal；专用解码线程队列非空便取包。 | 官方也有线程和队列，不能描述成“零队列”；入队逻辑没有固定攒两帧或等待下一 PTS 的门槛。 |
| decode | `avcodec_parameters_to_context` → `AV_CODEC_FLAG_LOW_DELAY` → `avcodec_open2`；处理包时 `avcodec_send_packet`，随后循环 `avcodec_receive_frame` 直到 EAGAIN/EOF，并立即推送可用帧。 | 无 `avformat_open_input` / `avformat_find_stream_info` / `av_read_frame` / `av_parser_parse2` 这条容器输入路径。 |
| decoded → screen | 默认 `video_buffer=0`，`scrcpy.c` 仅在用户指定非零 buffer 时插入 `video_regulator`。screen 的单个 pending frame 会被较新帧替换，已发出的 NEW_FRAME 事件消费最新帧。 | 默认不按视频 PTS 建立额外的播放延迟；UI 忙时丢旧待显示帧。 |
| screen → present | UI 事件取帧、更新纹理，再调用屏幕渲染；首次窗口显示与首帧事件有关。 | 解码可用、UI 渲染调用、GPU 完成和屏幕扫描仍是不同时间点。 |

来源分别为 [demuxer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c#L67-L177)、[CONFIG 合并](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/packet_merger.c#L19-L51)、[decoder 初始化与取帧](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L14-L58)、[decoder 包处理与线程队列](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L192-L418)、[默认 buffer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c#L66-L72)、[regulator 条件](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/scrcpy.c#L900-L925)、[最新待显示帧](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L41-L72)和 [screen 帧事件/渲染](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L480-L506)。

## 三种“多等一帧”必须区分

### 1. 找 access unit 边界的 parser

原始 Annex B 输入的 parser 可能需要后继起始边界，但不能直接套到本项目完整 AVCC Matroska 包上。固定 FFmpeg 源码给出了反证链：

1. Matroska 视频设置 `AVSTREAM_PARSE_HEADERS`（HEVC 例外）；H264 在此范围内。[matroskadec.c](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/matroskadec.c#L2999-L3002)
2. 通用 demux 将 HEADERS 映射为 `PARSER_FLAG_COMPLETE_FRAMES`，既在普通读包，也在 find-stream-info 初始化时设置。[demux.c](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/demux.c#L1411-L1424)、[探测初始化](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/demux.c#L2564-L2571)
3. H264 parser 看到 COMPLETE_FRAMES 时直接 `next=buf_size`，跳过 `h264_find_frame_end` / `ff_combine_frame` 的找边界分支；仍解析包内 header。[h264_parser.c](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavcodec/h264_parser.c#L594-L620)

因此不能以“FFmpeg parser 默认等下一帧”作为本项目根因。MDK 是否保留该 flag、是否有额外 parser 或 packet 调度，公开 API 没有说明，仍待实际事件观测。

### 2. frame threading 与编码重排

FFmpeg 的帧线程会引入额外解码延迟；`AV_CODEC_FLAG_LOW_DELAY` 使 frame-threading 分支不可选，仍允许可用的 slice threading。官方 scrcpy 没有显式设置 `threads=1`，不能把二者混同。[pthread.c](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavcodec/pthread.c#L42-L64)

编码所要求的显示顺序重排是另一层。H264 解码器依据 SPS `num_reorder_frames`、POC 顺序调整 `has_b_frames` 和 delayed pictures，再决定何时输出；关闭帧线程不等于移除码流本身的重排。[h264_slice.c](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavcodec/h264_slice.c#L1282-L1358)

本项目 [共享播放器](../../packages/interop_bridge/lib/src/media/fvp_video_player.dart) 软件候选已指定 `FFmpeg:thread_type=slice`；Android 优先候选是 `AMediaCodec:async=1`。若运行实际打开 AMediaCodec，FFmpeg 软件解码线程选项不能作为该硬件/系统后端的运行证据。MDK 官方文档明确 AMediaCodec 是自己的实现，其 `async` 选项与 AImageReader acquire 选项也相互独立。[MDK Decoders 固定修订](https://github.com/wang-bin/mdk-sdk/wiki/Decoders/cffa9514397313c46d60b98ea9def02d60e87afa#amediacodec)

### 3. 容器读取、packet 分发与解码输出调度

本项目 [muxer](../../crates/interop_core/src/media/matroska.rs) 每个完整包输出一个未知长度 Cluster，内部一个已知长度 SimpleBlock；H264 CONFIG 放入 CodecPrivate、NAL 转四字节长度前缀。[codec 适配](../../crates/interop_core/src/media/codec.rs)

未知长度 Cluster 结束判定确实依赖上层元素或 EOF；**但这不意味着 FFmpeg 必须等 Cluster 结束后才释放内部 SimpleBlock**。固定实现 `matroska_parse_cluster` 单独读取元素，完整 SimpleBlock 后立即 `matroska_parse_block`，`matroska_read_packet` 在队列出现包后返回。`ebml_read_binary` 按 SimpleBlock 声明长度读取，不要求读入下一个 Cluster。[Cluster/读包实现](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/matroskadec.c#L4242-L4314)、[二进制元素读取](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/matroskadec.c#L1085-L1107)

所以把 Cluster 改为已知长度是有价值的单变量排除实验，但源码不支持提前宣布它会修复。即使实验有效，也需区分 MDK 实际容器实现、其 IO 适配、预读与输出调度；不能直接归为 Matroska 规范强制等待。

## MDK 公开属性：可以试什么、不能声称什么

| 属性/接口 | 文档语义与适用边界 | 诊断含义 |
| --- | --- | --- |
| `setBufferRange(0,150,true)` | min=0 是尽快解码；max 是未解码包的最大缓冲时长，不是固定增加150ms。drop 还受关键帧间隔制约。 | 当前已经 min=0；把150ms直接当本样本等待原因不成立。 |
| `fps=-1` | render ASAP。 | 当前已有，不能保证 IO/parser/codec 每层都不等待。 |
| `avformat.input=matroska`、`fpsprobesize=0`、`probesize=32` | 强制输入格式、限制探测；作用于加载/探测。 | 当前已有；不能从持续流下一包相关性推导首帧冷启动完全由 probe 引起。 |
| `avformat.fflags=+noparse+nofillin` | MDK 允许传 AVFormat AVOption；FFmpeg 明确 NOPARSE 必须同时 NOFILLIN。NOFILLIN 禁止从其他字段推导缺失字段。 | 仅作有完整配置/PTS/完整包的单变量诊断；不是“所有直播都应开启”的建议。参考 parser 已是 COMPLETE_FRAMES，预期不等价于消除一帧。 |
| `avformat.fflags=+nobuffer` | 官方低延迟示例列出。参考 FFmpeg 在 find-stream-info 路径可不保留所读包。 | 会改变探测包保留，须验证首个 IDR 与静态流首帧；不能把命名理解为清除全部队列。 |
| `avformat.avioflags=direct` | 官方示例给出但注释；FFmpeg AVFormat 选项定义为 reduce buffering。 | 可测试 IO 边界；不承诺零复制或对 MDK 自有 IO 必然生效。 |
| `AMediaCodec:async=1:low_latency=1` | MDK Changelog 正式记载 AMediaCodec 的 `low_latency` 默认0，要求 Android API30+；Decoders wiki 的该节未列出它。 | 可以单独对比；这是 MDK 系统解码后端选项，不能用 FFmpeg `flags=+low_delay` 代替，也不能只因设置成功便宣称系统 codec 已执行。 |
| `AMediaCodec:async=1:surface=0` | 输出到主机 ByteBuffer；默认 surface=1 经 SurfaceTexture/AImage 等输出。 | 可分离 Surface/图像获取路径，但同时改变输出形式与复制成本，不能当成同路径的纯队列参数。 |
| 全局 `demuxer.io` | 0=demuxer internal IO，1=prefer own IO（默认），2=always own IO。 | 可单独对比0/1定位 IO 实现差异；它是全局项，不是普通 Player 同名属性。 |
| `avio.$opt_name` | MDK 文档用于 AVIOContext/URLProtocol；`avformat.*` 对 IO 的适用性另受 `demuxer.io=0` 条件影响。 | 不应盲猜通用 `avio.buffer_size` 或 HTTP `block_size`；参考 HTTP AVOption 中未找到这两个通用读缓冲契约。 |
| 全局 `videoout.buffer_frames` | renderer 最大缓冲帧数。 | 属 renderer，不是公开的“onVideo前解码包队列深度”；修改后仍须用相同指标验证。 |
| `prepare(0)` / boost | 0起点回调在 mediaInfo ready 时可触发；boost 默认 true 用于首帧渲染。 | prepare 回执不等于第一帧呈现，boost 不解释持续流每帧等待。 |

MDK 依据：[Player APIs 固定修订](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978)、[低延迟示例固定修订](https://github.com/wang-bin/mdk-sdk/wiki/Typical-Usages/bfafa5782d8187abc89d9bdcbe8ef7d0efd406ba#low-latency-live-stream)、[Global Options 固定修订](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options/82b2c09b7892711a9f1e319424e258d3fb5d9978)。FFmpeg 依据：[flags 契约](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/avformat.h#L1441-L1448)、[选项注册](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/options_table.h#L36-L52)、[probe包保留](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/demux.c#L2714-L2723)、[HTTP选项列表](https://github.com/FFmpeg/FFmpeg/blob/b08d7969c550a804a59511c7b83f2dd8cc0499b8/libavformat/http.c#L147-L191)。

AMediaCodec 专项依据：[Changelog 的 low_latency 与默认 image=1 记录](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/Changelog.md#L797-L801)、[surface/ByteBuffer 契约](https://github.com/wang-bin/mdk-sdk/wiki/Decoders/cffa9514397313c46d60b98ea9def02d60e87afa#amediacodec)。Changelog 表明项目提供过这些选项，不能替代固定0.39.0在指定codec上的实际能力与运行日志。

上述是接口允许表达的意图，不是固定 SDK 二进制已执行该路径的证据。不能同时改多个选项后为单项归因。MDK 文档还说明未知 property 可存用户数据；成功调用 `setProperty` 本身不能证明内部消费者存在。[setProperty 契约](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978#void-setpropertyconst-stdstring-key-const-stdstring-value)

## onVideo、首帧与可验证的下一步

固定 SDK 本地 `include/mdk/c/Player.h` 对 `onVideo` 的说明为帧交给 renderer 之前的过滤回调；公开 C++ `onFrame<VideoFrame>` 文档同样位于解码及可选过滤之后、renderer 之前。因此本项目在原生回调直接记录共享 Rust 单调时钟，确实排除了 Dart 事件递送等待；**但 codec 完成 → SDK 输出获取/图像交付 → onVideo 之间仍可能等待**，回调不是系统 codec 的 workDone，更不是 GPU 或扫描完成。[官方 onFrame 契约](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978#templateclass-frame-player-onframestdfunctionintframe-inttrack-cb)、[本地观测边界](../../crates/interop_bridge/src/media_trace.rs)

优先使用同一录制的包、PTS、供数时钟和持续供数窗口做以下分离；任一项变更都须检查解码 PTS覆盖、无错误、真实像素及停止释放：

1. 只改 Cluster 长度，判断容器边界是否影响固定 MDK；再分别试公开的 direct、NOPARSE+NOFILLIN 或 IO 选择，保留原基线。没有差异也是有效排除结果。
2. 观测同一 PTS 的“demux已返回/codec输入提交/系统codec输出可用/onVideo”。若系统输入提交已晚一包，检查 demux/分发；若输出已可用而回调晚一包，检查输出获取/SDK交付；若codec直到下一次输入才输出，再查codec重排与驱动。公开 MDK API 未给出内部 demux-return/submit 回调，不能拿相邻日志假造这两个边界。
3. 若要用 FFmpeg 参照链定位，使用同样配置和完整 AVPacket 做 send/receive，在每包后即时 drain；这回答码流及参考解码器能否立即输出，不等同于复现 MDK AMediaCodec。
4. 官方首帧对比必须固定宿主、被控设备、启动起点、分辨率、码率、编码器及实际decoder。官方包到解码与本项目“用户启动→Core准备→播放器加载→纹理→实际呈现”不是同一计时范围。优先比较相同输入边界，再单独解释冷启动阶段。

仍未知的关键契约包括固定 MDK 的实际 FFmpeg 版本/补丁、容器与 IO 内部读取策略、包分发线程是否在阻塞读取后才处理旧输出、AMediaCodec 输出轮询/图像交付的具体实现，以及 append 的复制时机/回收期限。本文没有找到足以回答这些问题的公开实现，不能由约一帧相关性反推出唯一内部函数。

## 可选 ABI SDK 的直接解码边界

官方 [v0.39.0 ABI 归档](https://github.com/wang-bin/mdk-sdk/releases/download/v0.39.0/mdk-abi-sdk.zip)包含 `VideoDecoder::create/set/open/decode(Packet)/take(VideoFrame*)`；Packet携带完整buffer、PTS/DTS及关键帧标记。归档53,043字节，SHA-256 `7cfad8f4d64db926176becfab4918df65e90647aae5348e67e6fbd73dd13364d`。这些是可选C++ ABI头中的接口，不是fvp公开Dart接口或当前稳定C表；本机fvp缓存没有安装它们。使用要求匹配SDK的编译器和C++运行库，不能把它直接声明为现有Rust C FFI的函数。[官方ABI限制](https://github.com/wang-bin/mdk-sdk/wiki/Typical-Usages/bfafa5782d8187abc89d9bdcbe8ef7d0efd406ba#custom-io)

该归档 `VideoDecoder.h:63–72`说明同步API配合同步AMediaCodec后端时，输入前必要时取输出、输入后只处理一次输出；`112–114`说明可能仍有帧在后端缓存，调用者需经take获取。这提供了“下一次decode调用带出旧输出”的可检验机制，**并未证明Player当前async路径采用该流程**。同一版本的 [DecodeFps示例](https://github.com/wang-bin/mdk-examples/blob/316e06d31d2556892f5eaa93464fd1a3a4993c9f/Native/DecodeFps.cpp#L38-L74)仍用Player/onFrame，不能替代独立codec提交/取出探针。后续如验证直接Packet路径，须单独解决ABI、解码输出排空、取消和帧所有权；本轮未引入该实现。
