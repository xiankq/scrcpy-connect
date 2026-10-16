# 共享 Rust 媒体封装与跨端播放器

核查日期：2026-10-17。对应实现：`crates/interop_core/src/media/`。本记录区分已验证的容器输出、播放器接口事实和仍需平台验收的生命周期，不能用 FFmpeg 解码成功代替手机首帧、音频焦点或后台行为验收。

## 决策与边界

Rust 继续负责 ADB、scrcpy 帧边界、配置包、PTS 和有界输出；将压缩视频或 PCM 封装为标准 Matroska，通过带随机凭据的 localhost HTTP 流交给 `package:fvp/mdk.dart` 的公开 `Player.media`。Flutter 负责展示 Texture 和输入坐标映射；系统权限、音频焦点、前台服务、SAF 等仍保留薄平台适配。首轮使用每端点一个 Track，视频属于控制会话，音频属于设备共享音源；两个独立 Player 不等于已实现音画同步。

这条路线可替代自维护解码/PCM 写入循环，但不意味着可以立即删除所有 Android 原生代码。此前后台音源由原生 owner 保持；当前改为applicationContext创建并保留Flutter engine，Dart Player/channel不随Activity销毁，Activity只弱引用提供UI适配。真实HOME两轮与Activity身份改变/同PID恢复已通过；真实外部App焦点临时/永久loss与双设备并行已通过；拔耳机、长后台、重连和系统回收仍分项验收，不能据此声称进程死亡后继续运行。

## 固定依赖与接口事实

`fvp` 固定 0.39.1；pub 归档 SHA-256 为 `2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`。核查本机 pub cache 与归档中的公开 Player、生成绑定、callback 和依赖 CMake 一致。公开入口导出 Player，可设置 `media`、播放状态、音量/静音、buffer range 和 texture；`nativeHandle` 是 getter。**公开 Dart Player 没有 appendBuffer 方法**，该函数只出现在内部生成的 C API 表。直接使用它还涉及 SDK ABI size 守卫和 native 生命周期，不是无维护成本的现成 Dart 流输入。[固定版本](https://pub.dev/packages/fvp/versions/0.39.1)、[Player 源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/player.dart)、[生成绑定](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/generated_bindings.dart)。

MDK 的 `stream:`/appendBuffer 接收字节，不接独立的 scrcpy packet PTS；官方流示例输入为封装后的 FLV。它不能把原始 scrcpy 12 字节私有帧头解释成媒体时间轴，因此使用标准容器仍有必要。公开 C++ enqueue 是已解码 VideoFrame 路径，不能据此推断存在压缩包或 PCM AudioFrame 播放入口。[官方输入示例](https://github.com/wang-bin/mdk-examples/blob/316e06d31d2556892f5eaa93464fd1a3a4993c9f/Native/stream.cpp)、[Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。

fvp 的 pub lock 不同时锁定各平台 MDK 二进制。0.39.1 依赖下载逻辑允许指定 `FVP_DEPS_URL`/`FVP_DEPS_SHA256`，默认来源包含可变 SDK 下载地址；正式四平台发布需固定平台归档及摘要。核查时 Android cache SDK stamp 为 `70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012`，这只是本机本次证据，不代表其它平台已验证。[依赖下载源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/cmake/deps.cmake)。

低延迟不能依赖默认 buffer。MDK 的 buffer 最大值 0 表示不设上限，而不是零延迟；当前使用min=0/max=150/drop。min=0允许尽快解码；max/drop受关键帧间隔限制，不能把150写成严格队列时长上限。应结合实测选择demux选项。硬件解码器存在不代表成功配置/首帧，仍需按设备检查。fvp 当前 texture 尺寸缓存也要求应用显式处理变化，不能将固定尺寸 POC 写成已支持旋转热切换。[Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)、[解码器文档](https://github.com/wang-bin/mdk-sdk/wiki/Decoders)。

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
rtk proxy cargo +stable test -p interop-core --test media_mux
rtk proxy env INTEROP_ADBD_PORT=15556 INTEROP_FFMPEG=/absolute/ffmpeg cargo +stable test -p interop-core --test media_mux_ffmpeg -- --ignored --nocapture
# 可按测试名 real_avcc / pcm_samples 只跑host两项，不需要设备。
```

共享HTTP视频已在Android双AVD经公开fvp Player通过五种codec的首帧、实际暂停、捕获暂停/恢复、再次snapshot、非单色PNG与停止释放；没有调用自维护Kotlin视频方法。初始同步waitFor0阻塞和AV1默认decoder缺失已定位并修正，详见[首帧与状态等待](scrcpy-first-frame-and-latency.md)。

真实产品 HOME/返回以及同一会话旋转 generation 交接、新代像素、触控尺寸已通过。删除旧 Native 视频实现后，产品页面五种编码再测全部通过；视频不再维护 Android 自写解码循环。待完成门槛仍含 PCM真实播放、长后台/系统回收、物理路由变化与长期音频生命周期、长期时钟漂移、慢消费者/断线全链路、四平台二进制锁定。共享PCM公开fvp生命周期已4秒通过，实际产品HOME和Activity重建14秒通过；旧313行Native音频播放循环已删除。暂停时钟先推进约80ms后稳定，恢复后继续前进；这不是扬声器采样证明。OS权限和后台适配按系统要求保留。
