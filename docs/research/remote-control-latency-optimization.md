# 远控画面与手势低延迟：实现对照与改造顺序

研究日期：2026-10-21。代码审计基线为本仓库提交
`bb6585a42dcc58463d1b8b22d665b1ec4e93bf5a`；对照来源固定为 scrcpy
`a60891aea193d92e7e5c3942700eca63f9d19a5f`（v5.0.1）、
`wsvn53/scrcpy-mobile` `cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09`
及其 scrcpy submodule `2322868e9e256eb5fce0b3d659ab2a409f29bae1`、
EasyControlNext `aeda9901ebf53350491f5454a41269e791918662`（v1.1.2）。

本文记录源码事实、受限条件下的既有实验和待验证的工程推论。它不是已接受的
ADR，也不把参考项目在局域网中的体验外推为本项目 SLO。当前协议、所有权和
产品行为仍以[架构](../implementation/architecture.md)、[ADR](../adr/)和
[产品规格](../../designs/prod/README.md)为准。

## 结论

**“网络稍微延迟就慢很多”通常不是多了一帧解码，而是网络 RTT 被乘进了
逐事件同步等待和排队时间。** 本文审计时的基线至少有三处会把 RTT 或带宽下降放大：

1. 审计基线中，Flutter 把每次 pointer down/move/up 串到同一个 Future 链，后一个事件必须
   等前一个 `session.touch` 完成：
   [界面输入队列](../../app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart#L1152-L1179)、
   [pointer 热路径](../../app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart#L1223-L1266)。
2. 审计基线中，`session.touch` 的响应要等 Rust 控制任务完成
   `AdbStream::write_all()`；经典 ADB 模式下该函数要等 adbd 返回 WRTE 的
   OKAY，因而每个串行触摸事件都等到一次网络往返：
   [控制请求等待](../../crates/interop_core/src/scrcpy.rs#L2357-L2379)、
   [控制写入](../../crates/interop_core/src/scrcpy.rs#L2696-L2707)、
   [经典 ADB ACK](../../crates/adb/src/client.rs#L1015-L1057)、
   [write_all](../../crates/adb/src/client.rs#L1318-L1335)。
3. 审计基线默认画面为 1280/60fps/8Mbps，ADB burst 关闭；经典 ADB 的逐流
   在途/ACK 限制与有限链路带宽叠加后，设备编码、ADB 发送和 TCP 内核会积累
   旧帧。当前产品默认已改为 4Mbps、burst 请求开启且仅在双方协商支持时生效，
   静态重复帧超时改为官方 100ms。

官方 scrcpy、scrcpy-mobile 和 EasyControlNext 的核心手段不是“让网络没有
延迟”，而是避免在 RTT 之上再制造多次往返，并在画面来不及展示时保留最新帧。
逐事件等待、最新 move 合并、完整控制消息批写和播放器实时 GOP 上限已进入
本仓库实现，主机验证与仍未覆盖的实体网络边界见
[验收记录](../implementation/validation.md#控制连接与恢复)。

## 延迟预算与测量边界

一次“手指移动后看到目标画面变化”至少包含：

```text
主控触摸采集
  -> 主控输入派发
  -> 控制传输
  -> 被控注入
  -> 目标 App 处理与绘制
  -> 屏幕捕获与编码
  -> 视频传输
  -> 主控解码
  -> 纹理提交、合成和显示
```

网络只能贡献链路传播与排队时间；应用自己增加的串行 ACK、过深缓冲和旧事件
重放会额外放大它。若 RTT 从 20ms 升到 50ms 后延迟从 100ms 变成数秒，新增
的时间主要来自队列，不是传播时延本身。

需要分别记录：

- 主控触摸采集到 Rust 接纳；
- Rust 接纳到控制 WRTE 发出；
- 被控收到到 `injectInputEvent`；
- 目标 `draw` 或源 PTS；
- 编码输出、主控收到、decoder 输出、`onVideo`、纹理可用；
- 最新可读 snapshot；最终面板扫描是另一层证据。

桌面 scrcpy README 中常见的 `35~70ms` 是特定桌面视觉镜像实验，不是触控往返
或 Android/Flutter 主控指标；来源条件见
[scrcpy 移动端一手来源](scrcpy-mobile-latency-primary-sources.md)。

## 参考实现究竟优化了什么

| 维度 | scrcpy / scrcpy-mobile | EasyControlNext | 本仓库 |
| --- | --- | --- | --- |
| 视频边界 | 直接消费 MediaCodec 包及其 PTS/关键帧标记 | 4 字节长度 + 8 字节 PTS + 编码 payload | scrcpy 包后重封 Matroska，再走 HTTP |
| 解码 | FFmpeg low-delay；移动移植用平台硬件解码 | Android `MediaCodec` 异步输出到 Surface | fvp/MDK，Android 优先 `AMediaCodec:async=1` |
| 默认缓冲 | scrcpy `video_buffer=0`；移动端同样设 0 | 无通用播放器缓冲 | MDK 实时流模式 min 0、max INT64_MAX、drop，renderer 待显示帧 1；仍位于额外链路末端 |
| 旧帧处理 | 已解码 pending frame 被新帧替换 | 解码输出立即交给显示层，队列满时处理背压 | MDK 实时流模式只保留最新关键帧及后续参考链；上游写入仍可向 relay 和 ADB 反压 |
| 输入 | 独立 controller 线程，60 项有界队列，调用方只等本地入队 | UI 线程投递后异步写主 socket，不等待注入结果 | Flutter 每触点最新 move + Rust 有界录取/再合并，连续完整消息按协商 payload 合批写；完成型操作仍等待 |
| 控制/视频 | scrcpy 分逻辑 socket 和线程，但底层仍多路复用 | 优先使用两个独立直连 TCP socket | 分 ADB stream 和 Rust task；控制 WRTE 使用独立有界优先 writer，视频 ACK 留在普通 FIFO |
| 默认带宽 | scrcpy 8Mbps；scrcpy-mobile 4Mbps | 4Mbps、最大 1600、60fps | balanced 为 4Mbps/1280/60fps；支持时使用 burst |
| 弱网自适应 | 无完整 ABR；移动端有显示层丢帧与卡死恢复 | 无 ABR、NACK、FEC 或 WebRTC | 无 ABR；有 MDK drop 和超时恢复，但没有控制输入端到端预算 |

### scrcpy：减少包等待，并让最新帧覆盖旧帧

服务端直接从编码 Surface 取输出，设置允许编码器尽快输出：

- `KEY_PRIORITY=0`（API 23+）；
- `KEY_LATENCY=1`（API 26+）；
- `KEY_REPEAT_PREVIOUS_FRAME_AFTER=100000us`；
- 默认 I-frame interval 10 秒。

见固定
[SurfaceEncoder.java](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L305-L340)。
这些参数让编码器按实时优先输出，而不是按普通录制或播放的批处理策略工作。

客户端不把原始 Annex B 字节重新交给通用 demuxer 找边界，而是直接读取协议中的
12 字节包元数据。FFmpeg 上下文启用 `AV_CODEC_FLAG_LOW_DELAY`，收到包后立即
发送并 drain 输出：
[demuxer.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c#L67-L177)、
[decoder.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L14-L58)。

默认 `video_buffer=0`。屏幕只有一个 pending decoded frame；UI 尚未消费时，
新帧替换旧 pending frame，而不是建立按源 PTS 播放的队列：
[options.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c#L66-L73)、
[frame_buffer.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L35-L72)。
这是“显示来不及就跳到较新状态”的关键。

输入侧有独立 controller 线程和 60 项队列。队列满时，可丢消息会被丢弃；
调用线程只负责推入本地队列，控制线程逐条写本地控制 socket，不等待被控端
注入完成：
[controller.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L6-L8)、
[controller.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L94-L125)、
[controller.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L143-L214)。
服务端以 `INJECT_INPUT_EVENT_MODE_ASYNC` 注入触摸：
[Controller.java](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/Controller.java#L500-L625)。

这里的“异步”不等于无网络往返；可见反馈仍然要等输入到达设备、目标重绘并
编码回传。它避免的是在本地事件处理路径中额外等待网络或注入确认。

### scrcpy-mobile：复用 scrcpy 核心，移动端只替换宿主与渲染

`wsvn53/scrcpy-mobile` 固定快照复用 scrcpy 4.0 附近的 C client。它默认
`--video-buffer 0` 和 `4Mbps`：
[ScrcpyADBClient.m](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/scrcpy-app/ADBClient/ScrcpyADBClient.m#L368-L383)。

iOS 移植把 VideoToolbox 解码帧直接交给 `AVSampleBufferDisplayLayer`，并标记
`DisplayImmediately`，绕过 SDL 的 CPU YUV 上传。显示层暂时不接受数据时，
当前帧被丢弃；只有连续停顿 2 秒才 flush 并请求服务端视频重置：
[decoder-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/decoder-porting.c)、
[texture-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/texture-porting.c)、
[ScrcpyRuntime.m](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/scrcpy-app/ADBClient/ScrcpyRuntime.m#L240-L425)。

它所谓“适配不稳定网络的移动手势”，主要仍是 scrcpy 的独立发送线程与队列，
加上 iOS 压力值和 CANCELED 事件修复；没有自定义预测、拥塞控制或 UDP 媒体
通道。README 同一快照仍写明目前只支持 iOS 主控，不能把它当作已验证的
Android/Flutter 主控实现。

### EasyControlNext：真正缩短用户态路径，但没有解决所有弱网问题

EasyControlNext 在设备可达时优先建立独立主/视频 TCP，失败才走 ADB：
[ClientStream.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/tools/ClientStream.java#L88-L131)。
这样视频发送不会直接占用 ADB 的控制通道。

编码端 `VirtualDisplay -> MediaCodec Surface -> H.264/HEVC`，解码端
`MediaCodec -> Surface` 直接 `releaseOutputBuffer`，没有 Matroska、HTTP、
图片或 Dart 像素中转：
[VideoEncode.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/server/src/main/java/com/shiyunjin/easycontrolnext/server/helper/VideoEncode.java#L50-L127)、
[VideoDecode.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/decode/VideoDecode.java#L17-L64)。

触摸事件由独立 HandlerThread 异步写主 socket；被控端保存原始 downTime 和
offsetTime，并以异步模式注入：
[ClientController.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/tools/ClientController.java#L308-L343)、
[ControlPacket.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/tools/ControlPacket.java#L10-L33)、
[Device.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/server/src/main/java/com/shiyunjin/easycontrolnext/server/entity/Device.java#L204-L240)。

其限制同样明确：视频和控制仍是可靠有序 TCP；编码输出直接阻塞写 socket；
没有 ABR、NACK、FEC、PLI 或帧龄丢帧；直连 socket 没有显式
`TCP_NODELAY`。因此它在低 RTT、带宽尚可的局域网中显得很快，在高抖动或
丢包网络下仍可能积累旧帧。可借鉴其结构，不能把“视觉体验好”解释成完整
弱网算法。

## 本仓库的具体延迟放大点

### 1. 改造前的手势热路径逐事件等待一个 ADB RTT

Flutter 的 `send()` 将请求追加到 `inputQueue.then(...)`，只有前一个
`sendNow()` 完成后才启动下一个。每个 `session.touch` 在 Rust 中等待
`stream.write_all()`；经典 ADB 的 `write_stream_frames()` 发出 WRTE 后等待
对应 OKAY。于是事件处理速率近似受 `1 / RTT` 限制。

若 RTT 为 30ms，单指针事件串行处理上限约为 33 次/秒；60/120Hz 的移动事件
会产生持续增长的待发送队列。若 RTT 为 100ms，上限约为 10 次/秒。网络恢复
后，队列仍会按旧顺序回放，用户看到“手已经停下，画面还在追”。

burst 模式只等待信用而不是逐包 OKAY，能改变这一时序。产品现默认请求
delayed_ack，但对端不支持时仍回退经典模式。已有 AVD 零 RTT 对照没有证明
收益；必须用真实 RTT 做单变量实验，不能仅凭参数名宣称端到端改善。

### 2. 改造前的控制包与视频 ACK 共用 FIFO，没有业务优先级

控制 WRTE 和视频接收 OKAY 最终都进入同一个 64 项 ADB writer FIFO：
[client.rs](../../crates/adb/src/client.rs#L353-L427)。该队列有界且保持流顺序，
但不会区分“触摸”和“视频 ACK”。视频突发、下行 ACK 或慢网络让 writer 饱和时，
触摸可能排在多项视频控制帧之后。底层 TCP 已设置 `TCP_NODELAY`，所以继续
只加 `TCP_NODELAY` 不会解决这个问题。

真正的改进需要：

- 保持同一 ADB stream 的顺序；
- 给控制流独立的有界优先队列或加权调度；
- 视频 ACK 不能无限挤占控制流；
- 已经写入内核的数据无法被用户态超车，因此仍需限制视频在途量。

当前控制流已使用独立 16 项优先 writer，普通 writer 仍为 64 项；每流的
ACK/credit 和有序关闭约束没有放宽。该排队排序只覆盖尚未写入内核的用户态
帧，不消除已经在 TCP 中的视频字节。

此外，同一阶段出队的连续完整控制消息会拼成不超过协商 max payload 的单个
WRTE。字节流协议不要求一条触摸、按键或文本对应一个 ADB packet；批写因此把
classic 模式多个“小消息各等一次 ACK”合并为一次回执等待，同时保持消息顺序、
6 秒期限和画质重建输入栅栏。

### 3. 改造前默认码率与经典 ADB 流控可能先饱和

审计基线 balanced 是 1280/60fps/8Mbps；smooth 才是 720/30fps/2Mbps。
scrcpy-mobile 和 EasyControlNext 默认均为 4Mbps。当前 balanced 已收敛到
4Mbps，并保留 8/12Mbps 显式选择。码率不是越低越好，但在无线链路实际可用
吞吐未知时，8Mbps 更容易先形成编码/发送队列。

经典 ADB 对每个逻辑流一次只允许一个尚未确认的 WRTE，接收端消费完当前包后
才回 OKAY。若协商包大小、实际帧大小和 RTT 的组合达不到目标码率，设备编码
线程会先被阻塞，旧画面则积在编码器输入/输出槽中。此时只把播放器 buffer
设为 0 没有用，因为延迟发生在播放器上游。

### 4. 视频经过额外播放器栈，并对下游采用反压

当前链路是：

```text
scrcpy packet
  -> H.264/H.265 NAL 扫描和长度前缀复制
  -> 每包一个 Matroska Cluster
  -> 本机 chunked HTTP
  -> fvp/MDK 探测、解封装、解码
  -> Flutter Texture
```

代码证据见
[codec.rs](../../crates/interop_core/src/media/codec.rs#L103-L126)、
[matroska.rs](../../crates/interop_core/src/media/matroska.rs#L128-L161)、
[http.rs](../../crates/interop_core/src/media/http.rs#L322-L336)、
[forward_generation](../../crates/interop_core/src/media/http.rs#L565-L603)、
[fvp_video_player.dart](../../packages/interop_bridge/lib/src/media/fvp_video_player.dart#L46-L91)。

这些函数在健康链路中未必产生固定数秒延迟，问题在于每个 HTTP chunk 写完才
继续，`run_video` 又等待本地 relay socket 写完：
[run_video](../../crates/interop_core/src/scrcpy.rs#L2575-L2598)。MDK 或 HTTP
短暂停顿会反向压住 ADB 读取，缩放后的旧帧仍留在设备编码器或中转路径中。
`fps=-1` 只减少播放时钟主动等待；旧的
`setBufferRange(min:0,max:150,drop:true)` 在关键帧间隔大于150ms时还无法执行
drop。当前改为实时流模式后，播放器可在可解码关键帧边界移除旧前缀，但仍不能
清除上游设备编码器或网络已经形成的帧龄。

当前新增的是恢复边界与播放器内旧 GOP 上限，而不是改写信道编码：Rust 持续观察
`arrival - sourcePts` 的相对增长；连续8个新PTS帧增长达到约800ms时，通过控制
优先通道请求`RESET_VIDEO`，并丢弃旧session数据直到设备给出新编码段。该判断
不依赖跨设备时钟同源，但阈值、重置造成的可见停顿和对实体弱网的收益仍需实测。

MDK 0.39.1 的`setBufferRange`契约还说明，`maxMs`小于关键帧间隔时
`drop=true`没有实际丢弃效果。因此播放器改用 `min=0, max=INT64_MAX,
drop=true`（Dart 传 `max=0`）：旧的非关键帧前缀只在可解码关键帧边界被移除，
而不会破坏仍在使用的压缩参考链。它限制播放器已收到的旧 GOP，仍不能清除设备
编码器或网络早于播放器形成的积压。

进程级`videoout.buffer_frames`另设为1，限制renderer已解码待显示帧为最新一张。
该设置影响本进程所有MDK视频输出，不能表述为单会话开关；它在首个实时播放器
初始化前执行，并通过`video.rendererQueue`诊断事件记录意图。

### 5. 已存在“低延迟”参数不等于已覆盖运行路径

当前播放器已设置：

- `min=0`、`max=INT64_MAX`、`drop=true`（实时流模式）；
- 进程级 renderer 待显示帧上限为 1；
- `fps=-1` 立即渲染；
- Matroska 强制输入和很小的 probe；
- Android 首选 `AMediaCodec:async=1`，软件回退 FFmpeg slice。

但仍缺三项证据：

1. 实际打开的 decoder 与运行参数是否有低延迟 effect；
2. decoder 输出到 Flutter texture 是否有固定额外一帧；
3. 弱网队列是否在到达 MDK 前就已经超预算。

因此继续堆叠 `setProperty` 不是第一优先级。可单独试验
`AMediaCodec:async=1:low_latency=1`（API 和厂商支持不同），但必须同时记录
实际 backend、P50/P95、首帧、功耗和失败回退，不能把 setter 成功当成生效。

### 6. 静态重复帧间隔比上游更激进

审计基线曾把 `repeat-previous-frame-after` 覆盖成
`1_000_000 / min(maxFps,30)` 微秒，即最高约 33ms。官方 scrcpy 默认 100ms。
前者的意图是减少静态画面等待，但在受限网络中会让静止画面也持续产生重复帧。
当前已改为官方 100ms；仍应与旧 33ms 做真实 RTT A/B，不能把参数值本身当作
已完成的端到端收益证明。

## 推荐改造顺序

以下是审计后的工程顺序。输入录取/最新 move 和控制 writer 优先级已完成主机实现
与故障夹具验证；真实 RTT A/B、视频原生直送和 latest-frame 邮箱仍未完成。

### P0：移除输入路径中的远端 ACK 同步屏障

目标是让 `session.touch` 的完成语义变成“已安全进入本进程控制发送器”，而
不是“adbd 已确认 WRTE”。协议本身没有输入注入 ACK，因此没有必要为每一次
触摸等待传输层确认。

建议：

- Rust 控制 actor 立即接纳输入，不让 Flutter 持有等待 ADB OKAY 的 Future；
- 写入失败通过连接失败事件统一撤销手势，禁止静默重放；
- 只对真正需要确认的 clipboard、launch 或配置操作保留远端完成语义；
- 保持同一控制 stream 的顺序，不并发乱序写 WRTE。

这是预期收益最大、风险最集中在一处控制协议的修复。它不减少输入到设备的
单向传播时间，但会消除“每个事件额外等一个 RTT”的串行放大。

### P0：有界合并 pointer move，保护 down/up/cancel

Flutter 不应维护无界 Future 链。可采用每触点状态：

- `MOVE` 只保留最新位置，按约 60Hz 或设备刷新周期发送；
- `DOWN`、`UP`、`CANCEL` 不丢弃，并与最后一个 `MOVE` 保持顺序；
- 多指指针状态分别维护；
- 连接阻断时记录积压时长和丢弃数，恢复后从最新状态继续，不回放过期轨迹；
- 失败后主动发送所需 CANCEL 并清除本地触点状态。

对于绘画等需要轨迹连续性的场景，可保留有限历史而不是只留一个位置，但这应
按场景选择，默认状态远控优先“最新位置”。

### P0：控制优先、视频 ACK 有界

在 ADB writer 前增加可验证的调度策略：

- 控制 WRTE 优先；
- 视频 ACK 正常级；
- 同一 stream 保持严格顺序；
- 在队列饱和时丢弃过期控制请求或触发连接失败，不无限增长；
- 记录每类帧的最长等待时间。

优先级不能让已经进入 TCP 内核的视频字节回退，因此还要控制视频在途窗口，
不能把希望全部放在用户态队列排序上。

### P0：在真实 RTT 下做码率、burst 与重复帧 A/B

先测，再改默认值。建议每组只改变一个变量：

| 实验 | 变量 |
| --- | --- |
| A | 旧基线：1280/60/8Mbps、burst 关闭、重复帧 33ms |
| B | 只切 burst 开启，其他同 A |
| C | 只把码率降到 4Mbps，其他同 A |
| D | 只把重复帧改为 100ms，其他同 A |
| E | 当前组合：1280/60/4Mbps、burst 开启、重复帧 100ms |

网络条件至少覆盖无人工延迟、20/50/100ms RTT，以及 0.5% 丢包；带宽上限分别
固定为 2/4/8Mbps。每组使用同一手势轨迹、同一画面变化和多个 session。

如果 4Mbps 或 burst 后输入和画面尾延迟显著下降，根因是链路吞吐与 ADB 流控；
如果只有输入延迟下降，说明逐事件 ACK/控制队列是主因。

### P1：移动端改为原始 packet 直送平台解码器

这是结构性改造，目的不是少几个纯函数，而是把包边界、PTS、解码和 Surface
交给同一条原生实时路径：

```text
scrcpy packet
  -> 有界 packet queue
  -> 平台硬件 decoder
  -> SurfaceTexture / Surface / 平台纹理
  -> Flutter Texture 或 PlatformView
```

移动端优先去掉实时视频中的：

- Annex-B/NAL 重扫与 Matroska 重封装；
- loopback HTTP；
- 通用容器探测、播放时钟和 MDK 内部调度；
- 解码后像素回读。

现有 fvp/MDK 可保留为非移动平台、兼容回退或普通媒体预览。不能为了复用播放器
而把实时远控继续当作“打开一个本地视频 URL”。

### P1：显示前保留 latest-frame 邮箱

不能随意丢弃压缩 P/B 帧，否则参考链会断裂。正确位置是解码后、提交显示前：

- 解码线程持续消费完整 packet；
- 已解码但未展示的帧只保留最新一张；
- 新帧覆盖旧帧；
- 纹理提交或 Flutter 合成慢时不反向阻塞设备编码；
- 只有资源回收和 generation 归属需要等待。

若必须在网络/解封装层丢包，只能以关键帧或完整可解码 GOP 为边界，并主动请求
新 IDR。当前官方 server 没有独立“请求关键帧”消息；`RESET_VIDEO` 会重启编码
流程，代价明显高于只请求 IDR。

### P1：增加按帧龄的降级与恢复

按优先级降级：

1. 降实际 fps；
2. 降码率；
3. 降分辨率；
4. 请求关键帧；
5. 重建编码器或缩短 GOP。

先降 fps 通常比直接降分辨率更能减少队列，又比维持低帧率旧画面更实时。
需要同时记录队列帧龄、RTT/带宽估计和 decoder 输出节奏，避免把所有延迟都
归因于网络。

### P2：只有真实跨网弱网才考虑 UDP/QUIC/WebRTC

scrcpy、scrcpy-mobile 与 EasyControlNext 都没有用 WebRTC 解决局域网镜像。
如果产品目标包含公网、丢包和抖动，可靠的 TCP 媒体流会发生队头阻塞，届时才
需要：

- 独立可靠控制通道；
- 低延迟不可靠或部分可靠媒体通道；
- NACK/FEC、关键帧请求、码率/分辨率自适应；
- 帧龄和播放截止时间，而不是只按到达顺序播放。

这是协议级工程，不能通过调整 `fvp` 或 `setPixels` 达成。

## 测量矩阵与验收

每条手势记录至少包含：

| 段 | 必测事实 |
| --- | --- |
| Flutter | 原始 pointer timestamp、入队时间、当前队列深度、合并次数 |
| Rust control | 接纳时间、mpsc 等待、控制帧大小、写入开始/结束、ADB ACK 时间 |
| ADB | 经典/burst、协商 max payload、writer 等待、视频 ACK 等待 |
| 被控 | 收到控制、注入完成、目标 draw/源帧 PTS |
| 编码 | 输入 Surface 时间、首个 output、PTS、keyframe、包大小、字节率 |
| 传输 | 首字节、整包、relay 写入、消费者读取 |
| decoder | 输入提交、输出可用、`onVideo`、纹理提交、可读 snapshot |

同一事件或同一 PTS 才能关联，不能把不同样本中位数相加当成端到端分位数。

建议先建立以下单项门禁，再讨论产品默认值：

- RTT 0/30/80ms 下，pointer move 队列深度有界，且恢复后不重放过期轨迹；
- `session.touch` 本地回执不再等待 ADB ACK；
- 控制帧在视频突发中的 P95 等待可测量且有上限；
- 2/4/8Mbps 下画面尾延迟与输入到可读像素分别报告；
- 丢包后能请求 IDR 或明确进入恢复，不让旧 GOP 长时间排队；
- 记录实际 decoder、渲染 backend 和硬件/软件路径，不以候选列表代替证据。

## 不应采用的“优化”

- 只设置 `fps=-1`、`buffer=0` 就宣称没有缓冲；上游仍可能有队列。
- 无条件启用 burst 或把窗口调大；这会提高吞吐，也可能增加旧帧在途量。
- 为降低延迟全局强制软件解码；不同设备和后端结果相反。
- 在压缩码流中随意丢普通 P/B 帧；会破坏参考链并造成花屏。
- 把 Flutter 输入串成更快的 Future，但仍逐条等待远端 ACK。
- 只提高线程优先级；网络/ADB 在途队列和同步屏障不会因此消失。
- 直接复制 EasyControlNext 代码而不做许可证评估；该项目为 GPL-3.0。
- 把 scrcpy 桌面局域网的 `35~70ms` 当作本产品移动弱网指标。

## 证据边界

已确认：

- 当前输入串行队列和经典 ADB 写入等待远端 OKAY 的源码事实；
- 当前视频存在 Matroska、loopback HTTP、通用播放器和反压；
- 当前默认画质、burst 开关和 MDK 参数；
- scrcpy、scrcpy-mobile、EasyControlNext 的上述固定源码行为；
- 本仓库既有 AVD 实验中，播放器/解码路径存在独立等待，但测试环境不是实体
  ARM、Wi-Fi、丢包或真实高 RTT。

尚未确认：

- 用户实际网络下三个放大点的贡献比例；
- burst 在当前协商包大小和真实 RTT 下是否降低端到端延迟；
- 旧 8Mbps 是否已超过目标链路实际吞吐，以及 4Mbps 对画质/延迟的实际交换比；
- `AMediaCodec:low_latency=1` 在目标设备是否可用并实际生效；
- 改为原生 packet + Surface 后，在 Android Flutter 上的真实收益；
- 最终面板扫描延迟。

这些项目必须用实体设备与可控网络条件验证，不能由本次源码审计替代。
