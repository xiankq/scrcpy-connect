# 共享 Rust 媒体封装与跨端播放器

核查日期：2026-10-17。对应实现：`crates/interop_core/src/media/`。本记录区分已验证的容器输出、播放器接口事实和仍需平台验收的生命周期，不能用 FFmpeg 解码成功代替手机首帧、音频焦点或后台行为验收。

本文的 MDK 二进制固定建议与完成度属于该研究阶段。当前播放器直接使用社区原版 fvp 0.39.1，MDK 下载和平台约束继承发布包，不维护本地 fork 或额外固定回归；现行规则与 snapshot 限制见[工具链契约](../implementation/repository-tooling.md#社区原版-fvp-0391)。历史实测不自动成为当前依赖切换后的运行证据。

## 决策与边界

Rust 继续负责 ADB、scrcpy 帧边界、配置包、PTS 和有界输出；将压缩视频或 PCM 封装为标准 Matroska，通过带随机凭据的 localhost HTTP 流交给 `package:fvp/mdk.dart` 的公开 `Player.media`。Flutter 负责展示 Texture 和输入坐标映射；系统权限、音频焦点、前台服务、SAF 等仍保留薄平台适配。首轮使用每端点一个 Track，视频属于控制会话，音频属于设备共享音源；两个独立 Player 不等于已实现音画同步。

这条路线可替代自维护解码/PCM 写入循环，但不意味着可以立即删除所有 Android 原生代码。此前后台音源由原生 owner 保持；当前改为applicationContext创建并保留Flutter engine，Dart Player/channel不随Activity销毁，Activity只弱引用提供UI适配。真实HOME两轮与Activity身份改变/同PID恢复已通过；真实外部App焦点临时/永久loss与双设备并行已通过；拔耳机、长后台、重连和系统回收仍分项验收，不能据此声称进程死亡后继续运行。

## 固定依赖与接口事实

`fvp` 固定 0.39.1；pub 归档 SHA-256 为 `2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`。核查本机 pub cache 与归档中的公开 Player、生成绑定、callback 和依赖 CMake 一致。公开入口导出 Player，可设置 `media`、播放状态、音量/静音、buffer range 和 texture；`nativeHandle` 是 getter。**公开 Dart Player 没有 appendBuffer 方法**，包内存在的是内部生成的 C API 表槽。可利用 `nativeHandle` 编写本仓库自己的 native adapter 接入 MDK，**无需 fork fvp**；但需维护 SDK ABI size 守卫与 native 生命周期，不能视为现成的公开 Dart 流输入。[固定版本](https://pub.dev/packages/fvp/versions/0.39.1)、[Player 源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/player.dart)、[生成绑定](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/generated_bindings.dart)。

MDK 的 `stream:`/appendBuffer 接收字节，不接独立的 scrcpy packet PTS；官方流示例输入为封装后的 FLV。它不能把原始 scrcpy 12 字节私有帧头解释成媒体时间轴，因此使用标准容器仍有必要。公开 C++ enqueue 是已解码 VideoFrame 路径，不能据此推断存在压缩包或 PCM AudioFrame 播放入口。[官方输入示例](https://github.com/wang-bin/mdk-examples/blob/316e06d31d2556892f5eaa93464fd1a3a4993c9f/Native/stream.cpp)、[Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。

fvp 的 pub lock 不同时锁定各平台 MDK 二进制。0.39.1 依赖下载逻辑允许指定 `FVP_DEPS_URL`/`FVP_DEPS_SHA256`，默认来源包含可变 SDK 下载地址；当时据此建议为正式四平台发布固定平台归档及摘要，现行选择为直接继承原版平台规则。核查时 Android cache SDK stamp 为 `70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012`，这只是本机本次证据，不代表其它平台已验证。[依赖下载源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/cmake/deps.cmake)。

低延迟不能依赖默认 buffer。MDK 的 buffer 最大值 0 表示不设上限，而不是零延迟；当前使用min=0/max=150/drop。min=0允许尽快解码；max/drop受关键帧间隔限制，不能把150写成严格队列时长上限。应结合实测选择demux选项。硬件解码器存在不代表成功配置/首帧，仍需按设备检查。fvp 当前 texture 尺寸缓存也要求应用显式处理变化，不能将固定尺寸 POC 写成已支持旋转热切换。[Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)、[解码器文档](https://github.com/wang-bin/mdk-sdk/wiki/Decoders)。

## 2026-10-19 输入链路复核

结论：当前实现确实增加了本机 I/O、封装与解封装，但**尚无当前原版 fvp 下的对照测量证明它显著增加端到端延迟**。最值得对照验证的是 `Matroska → MDK stream: / appendBuffer` 的 native 内存直送；改动较小的候选是合并 Rust 内部 raw TCP 中转、保留现有 HTTP 播放入口。以下为源码/API 核查和研究推论，本次未修改生产链路、未运行设备实验。

### 当前开销的边界

现行链路是 `ADB/scrcpy → Rust raw 本机 TCP → Rust Matroska → 本机 HTTP → MDK demux/decode → Texture`。HTTP 成功接入后持续发送 chunk，通常每个媒体 generation 一次连接，并非每帧重新 HTTP 请求；chunk 由长度、payload、结尾三次 `write_all` 输出，两侧 Rust socket 均设置 `TCP_NODELAY`。mux 每个有效 packet 立即生成独立 Cluster，没有等待多帧或固定时长凑包的逻辑。因此代码能证明存在额外复制、系统调用和任务调度，不能仅凭层数推出固定增加一帧或数百毫秒。[HTTP 实现](../../crates/interop_core/src/media/http.rs)、[mux 实现](../../crates/interop_core/src/media/matroska.rs)。

旧[性能记录](../implementation/video-performance.md)中的约 `0.051ms` 是特定历史运行的写入段测量，不含后续 MDK 读取、探测、解封装、解码与显示等待，也不能继承为当前社区原版整条链路的成本。播放器 packet buffer、codec 重排、render 和显示调度仍存在；更换传输入口不会自动消除这些等待。当前 `min=0` 避免主动等待最小 packet 时长，`max=150/drop` 不是严格的150ms延迟保证。[固定 Player API 修订](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978)。

### MDK 内存直送与 fvp 的接口差距

本次通过 Dart 包读取工具复核 `fvp 0.39.1`：公开 `mdk.dart` 导出 `Player`；`nativeHandle` 返回 `_player.address`，即 **`mdkPlayerAPI*`，不是 `mdkPlayer*`、C++ Player 地址或 Flutter texture id**。内部 generated bindings 有 `appendBuffer` 函数指针槽，但公开 Player 没有同名方法；不能直接写 `player.appendBuffer(...)`。[公开入口](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/mdk.dart)、[Player](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/player.dart)、[生成绑定](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/generated_bindings.dart)。

本机 SDK `include/mdk/c/Player.h` 的真实槽签名是：

```c
bool (*appendBuffer)(struct mdkPlayer*, const uint8_t* data,
                     size_t size, int options);
```

调用对象应是 `api->object`；先设置媒体为 `stream:`，随后提供可被 demux 的媒体字节。签名没有 codec、每包 PTS、关键帧或 track 参数，故仍建议送现有 Matroska header/Cluster，保留 scrcpy 时间轴。它省去传输层，不等于省去 mux/demux，更不等于零复制。C++ `enqueue(const VideoFrame&, void*)` 则向 renderer 送**已解码视频帧**，随后还需渲染线程调用 `renderVideo()`；它不是压缩 H264/H265/AV1 packet 输入或 PCM AudioFrame 播放入口。[官方流输入示例，固定提交](https://github.com/wang-bin/mdk-examples/blob/316e06d31d2556892f5eaa93464fd1a3a4993c9f/Native/stream.cpp)、[固定 Player API 修订](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978)。

可行设计推论是：Dart 仅在会话绑定/释放时传递 handle 和 generation；本仓库自己的 native adapter 借用该表，让 Rust 将封装字节直接送入 MDK，继续复用原版 fvp 的 Player/Texture，**无需维护 fvp fork，也不推荐 Dart 逐帧中转**。新增责任包括：

- 按平台实际 SDK 头文件编译，检查运行时表 `size`、成员范围及非空函数指针。`size==0` 的旧 runtime 不允许访问扩展槽；应使用实际运行时 guard，不能只依赖 release 模式可能关闭的 C++ `assert`。平台 MDK 来源仍遵循工具链契约，不能用 Dart 版本号代替 native ABI 核验。
- handle 仅借用，fvp 仍拥有 Player；不得由 adapter 调用 delete/reset，不得另建会清理原 Player callbacks 的临时 C++ 包装对象。先停止接收并撤销 generation，等待在途 native 调用退出，再允许 fvp dispose；裸地址本身不提供所有权或跨线程销毁保护。
- 官方示例只演示普通 payload 的 append；本次检查的 header/wiki **没有明确规定** `options` 的含义、数据是否同步复制、返回 `false` 的重试语义、零长度/空指针 EOF 协议，以及内部 byte queue 的上限/阻塞行为。不能把 `nullptr,0` 当作已确认 EOF，也不能把 `bool` 当作已确认背压。实施前需向上游确认或对实际 SDK 验证这些契约，并设计有界输入、取消唤醒、超时和慢消费者恢复；不在 UI 线程或异步 runtime 关键执行线程承受未知阻塞。`setBufferRange` 控制 demux 后的 packet 队列，不证明 append 前的字节队列有界。

本次 SDK 证据为本机 pub cache 的 `fvp-0.39.1/android/mdk-sdk/include/`：`mdk/c/global.h` 声明0.39.0；`mdk/c/Player.h` SHA-256 为 `3f12300f1c71fda173f50423c5befacc6f0b36e3b6c996a5d3188b7a7e362ef8`，`mdk/Player.h` 为 `80b4aabf8bd52674d2661866ff84e979438f8a77862ecdebd9dd642b84b04c0e`。C 表包含运行时 `size` 说明；C++ `MDK_CALL2` 检查扩展槽，借用构造的析构仍调用 `mdkPlayerAPI_reset(..., false)`。这些是本次本机头文件快照，不代表所有平台 SDK 已固定或运行验收通过；发布包依赖规则见[工具链契约](../implementation/repository-tooling.md#社区原版-fvp-0391)。

### 候选输入的实际边界

| 候选 | 能减少的工作 | 边界与研究判断 |
| --- | --- | --- |
| 合并 Rust raw TCP 中转，保留 Matroska HTTP | 少一对本机 socket、一次中转任务及相关读写 | 不改 MDK 接入，改动较小；必须保留 ADB/会话所有权、取消、generation 和有界背压。收益未测。 |
| Matroska 经 native adapter 送 `stream:` | 可同时移除 raw 中转和本机 HTTP/socket | 最值得验证的路线；保留 mux/demux，新增前述 ABI、内存与生命周期责任。收益未测。 |
| `tcp://127.0.0.1:port` 直接送 Matroska | 省 HTTP 请求头和 chunk framing | 公开 `media` 可传 URL，MDK 声明支持 FFmpeg protocols；仍有 socket、mux/demux、buffer，不保证明显改善，且需重做单消费者准入/凭据边界。不能直接把 scrcpy 私有帧头交给标准 demux。 |
| `fd:23` | 可用同进程 fd/pipe 替代网络监听 | MDK 官方明确支持该语法；不是所有平台 HANDLE 的通用替代。须验证实际 MDK build 对非 seek 流的支持、fd 复制/关闭责任与取消；仍要提供容器或明确的媒体格式。 |
| `mem:addr+size` | 固定内存内容可无 socket 读取 | 官方给出的是地址和有限长度，未承诺可扩容直播 ring buffer 或持续 append；无法据此替代无限实时输入。内存须保持有效、禁止重分配/提前释放，具体保留期限仍需确认。 |

协议能力依据[固定 MDK Player API 修订](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978)；TCP 字节流实现可参考[FFmpeg n8.0 的 tcp.c](https://github.com/FFmpeg/FFmpeg/blob/n8.0/libavformat/tcp.c)，但它不证明本项目每个平台的 MDK 运行包都已包含并验收同一实现。

后续对照应保持 codec、分辨率、码率、关键帧间隔、MDK build、buffer 与 renderer 一致，分别测首帧和稳态，覆盖静止屏、音频、暂停/恢复、generation 切换、慢消费者及停止。至少分开记录 scrcpy packet 进入 Rust、封装完成、播放器入口、解码/渲染事件与实际显示；比较 p50/p95、CPU、复制量和队列深度，才能判断少一层传输带来的收益。比较实验可以使用临时替代输入，生产仍只保留一条选定链路，本研究不引入并行播放模式。

## 纯 Rust 容器实现

选择 `webm-iterable =0.7.1`（MIT）及其 `ebml-iterable =0.7.1` writer：接收 `std::io::Write`，不要求 Seek，支持 unknown-sized master。它负责 EBML 元素序列化；不把它误称为已经处理所有 codec 语义的完整 muxer。上层仅添加 Track、配置转换和 packet 映射。未选择需要 libwebm C++ 的封装，也未选择要求 Write+Seek 的文件 muxer。[库源码](https://github.com/austinleroy/webm-iterable)、[固定 writer API](https://docs.rs/ebml-iterable/0.7.1/ebml_iterable/struct.TagWriter.html)。

配置解析/序列化使用固定纯 Rust `scuffle-h264 =0.2.2`、`scuffle-h265 =0.2.2`、`scuffle-av1 =0.1.4`（MIT OR Apache-2.0），避免另写 SPS/AV1 sequence bit parser；边界适配仅负责 Annex B 起始码、NAL 长度和 WebM TLV。其依赖链没有 C/C++/FFmpeg/libwebm；发布的 scuffle-workspace-hack 0.1.0 本身无依赖。版本固定不代表经过本项目安全审计。[H264 API](https://docs.rs/scuffle-h264/0.2.2/scuffle_h264/)、[H265 API](https://docs.rs/scuffle-h265/0.2.2/scuffle_h265/)、[AV1 API](https://docs.rs/scuffle-av1/0.1.4/scuffle_av1/)。

| 输入 | Matroska CodecID | 配置与块格式 |
| --- | --- | --- |
| H264 | V_MPEG4/ISO/AVC | SPS/PPS → AVCDecoderConfigurationRecord；每 NAL 四字节大端长度 |
| H265 | V_MPEGH/ISO/HEVC | VPS/SPS/PPS → HEVCDecoderConfigurationRecord；每 NAL 四字节大端长度 |
| AV1 | V_AV1 | 接受低开销 sequence OBU 或 Android av1C；块保留 Temporal Unit OBU 边界 |
| VP8 | V_VP8 | 无 CodecPrivate；块保留原 access unit |
| VP9 | V_VP9 | 验证 WebM feature TLV；允许无配置，不误用 ISO vpcC |
| PCM | A_PCM/INT/LIT | 采样率/声道数/16bit 声明；little-endian 交错样本 |

依据 [Matroska codec mapping](https://www.matroska.org/technical/codec_specs.html) 和 [WebM VP9 feature metadata](https://www.webmproject.org/docs/container/#vp9-codec-feature-metadata-codecprivate)。AV1 SimpleBlock 标 keyframe 必须带 sequence；实现会补入已验证配置中的 sequence，配置本身只有四字节 av1C 时则要求 keyframe 自带。AV1 sequence 改变、AVC/HEVC in-band 参数集改变要求新 generation，不悄悄修改同 Track。

每个输出以 unknown-length Segment 开始，有限 Info/Tracks 后逐包输出 Cluster。TimestampScale=1000ns，保留整数微秒；首个有效包 PTS 为时间原点，保存可查询的原始 origin。每包 Cluster 的相对 Block timestamp=0，不受有符号 16bit 相对偏移或静止屏长间隔影响；不伪造恒定帧率、不生成无界 Cues。无 seek 的直播 Segment 是标准允许的表示。[直播容器规范](https://www.matroska.org/technical/streaming.html)。

限制：单包最多16MiB、配置最多256KiB、每访问单元最多1024个 NAL/OBU、尺寸1..16384、PCM 包必须完整 sample frame。AVC/HEVC 目前接受一个 active SPS，多个 SPS 不猜选；AV1 keyframe 使用 Frame OBU，只有分离 FrameHeader/TileGroup 的编码输出需另行实现正确 BlockGroup 表达。输出在调用后 drain，无会话 packet 队列。unknown Segment 下不能每包调用 writer.flush，因为该 API 会关闭所有 open master；只关闭本包 Cluster。

公开接口：

```rust
let track = VideoTrack::from_scrcpy(codec, width, height, &configuration)?;
let mut mux = MatroskaMuxer::new(generation, Track::Video(track))?;
let header = mux.take_header();
let chunk = mux.push_packet(pts_us, keyframe, &access_unit)?;
// 或 Track::PcmS16le { sample_rate: 48000, channels: 2 }
```

HTTP/消费者必须加有界 backpressure、鉴权、断线取消和 generation 检查；不能让消费者慢速读取变成无界 packet 排队。当前一端点一 Track 不合并不同源 origin；将来需要共同音画时钟时，必须另建明确的双 Track 时间轴。

## 实际验证

测试工具为临时 FFmpeg 7.0.2-static（imageio-ffmpeg0.6.0 提供），不是产品依赖。二进制 SHA-256：`e7e7fb30477f717e6f55f9180a70386c62677ef8a4d4d1a5d948f4098aa3eb99`。

默认 `media_mux`：六项覆盖空/坏/超大包、采样边界、错误不推进时间原点、微秒非整数帧间隔与大于16bit的间隔、10000包持续 drain、配置拒绝、Android AV1/VP9 配置及未知 level、首帧和参数集变更保护。独立 FFmpeg 验证 H264 三帧真实 RGB 内容，并由 showinfo 确认 PTS 为0、123457、1234567us；PCM 4800个立体声采样帧解码后逐字节相同。

真实目标 `127.0.0.1:15556` 使用 Rust ADB + 固定官方 scrcpy5.0.1，未操作主控5554、未改目标 UI：H264/H265/AV1/VP8/VP9 五种编码均经本实现输出 Matroska，再由 FFmpeg 解码为实际288×640 PNG。H264 config31/private34字节；H26580/106；AV1 csd为 `[81,04,0c,00]`（四字节 av1C，sequence 在帧内）；VP8无配置；VP9 csd9字节含未知 level0，按规范省略这个可选 feature 后保留6字节 profile/bitdepth。该证据证明目标编码+容器兼容，不能代替四平台 fvp 实际首帧。

复现命令：

```sh
cargo +stable test -p interop-core --test media_mux
env INTEROP_ADBD_PORT=15556 INTEROP_FFMPEG=/absolute/ffmpeg cargo +stable test -p interop-core --test media_mux_ffmpeg -- --ignored --nocapture
# 可按测试名 real_avcc / pcm_samples 只跑host两项，不需要设备。
```

共享HTTP视频已在Android双AVD经公开fvp Player通过五种codec的首帧、实际暂停、捕获暂停/恢复、再次snapshot、非单色PNG与停止释放；没有调用自维护Kotlin视频方法。初始同步waitFor0阻塞和AV1默认decoder缺失已定位并修正，详见[首帧与状态等待](scrcpy-first-frame-and-latency.md)。

真实产品 HOME/返回以及同一会话旋转 generation 交接、新代像素、触控尺寸已通过。删除旧 Native 视频实现后，产品页面五种编码再测全部通过；视频不再维护 Android 自写解码循环。待完成门槛仍含 PCM真实播放、长后台/系统回收、物理路由变化与长期音频生命周期、长期时钟漂移、慢消费者/断线全链路、四平台二进制锁定。共享PCM公开fvp生命周期已4秒通过，实际产品HOME和Activity重建14秒通过；旧313行Native音频播放循环已删除。暂停时钟先推进约80ms后稳定，恢复后继续前进；这不是扬声器采样证明。OS权限和后台适配按系统要求保留。
