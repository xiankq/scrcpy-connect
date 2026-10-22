# scrcpy 移动端延迟的一手来源与适用边界

调查日期：2026-10-21。本文回答一个容易混淆的问题：scrcpy 官方公开的低延迟数字能否直接用作 Android 或 Flutter 主控的端到端延迟目标。范围限定为 scrcpy 官方文档、固定版本源码和维护者公开的实验记录；本项目自己的设备结果另见[视频性能记录](../implementation/video-performance.md)。

## 结论

1. **官方 README 的 `35~70ms` 不是移动主控指标。** scrcpy v5.0.1 README 在功能列表中写有 `low latency: 35~70ms`，链接到 PR #646。该 PR 的实验是桌面 scrcpy 客户端观察一台 Android 设备上播放的 30fps 计数视频；作者报告低延迟分支在 1080×1920 下约两帧（约 67ms）、在 448×800 下约一帧（约 33ms）。这不是触控到目标响应的往返延迟，也没有给出当前版本、实体手机、无线网络、移动宿主或分位数结果。
2. **该数值带有明确的历史条件。** PR #646 页面在 2026 年增加了“这些测量非常旧，较新的设备表现更好”的编辑说明。README 仍保留该范围，但公开资料没有提供可替代的 v5.0.1 统一基准，因此应把它视为“官方曾在特定桌面路径观察到约一帧量级的视觉镜像延迟”，不能当作当前设备或产品的保证值。
3. **官方 scrcpy v5.0.1 没有 Android 客户端。** README 明确列出客户端运行于 Linux、Windows 和 macOS，Android 设备是被镜像的目标。开发文档把 client 描述为计算机上的 `scrcpy` 二进制，依赖 SDL 和 FFmpeg；设备上的 server 负责采集、编码和输入注入。官方公开的 `35~70ms` 因而属于桌面 client + Android server 的组合。用户通常所说的第三方同名项目 `wsvn53/scrcpy-mobile` 是另一条来源链；其固定快照复用 scrcpy 4.0 附近的 C client，不能反向证明官方有移动客户端或官方移动端指标。
4. **“默认无视频缓冲”只排除一层已知播放器延迟，不等于零延迟。** 官方文档说明默认不增加视频缓冲，以取得最低可能延迟；音频则有不可避免的默认 50ms 目标缓冲。采集、编码、ADB/socket 传输、解码、纹理提交、合成和屏幕扫描仍各自耗时。官方也没有把 `KEY_REPEAT_PREVIOUS_FRAME_AFTER=100ms` 声明为首帧或端到端上限。
5. **对本项目唯一可靠的结论是必须实测移动路径。** 不能把 `35~70ms` 宣传为 Android/Flutter 主控的默认效果，也不能把桌面 scrcpy 的 33ms 直接判给移动端输入延迟。应继续按相同事件或同一 PTS 分开记录输入派发、目标绘制、编码、传输、解码、Flutter 呈现和可读像素，并对实体 ARM、Wi-Fi、profile/release 等环境单独给出分位数。

## 一手证据

### 固定版本身份

- 官方 v5.0.1 annotated tag 为 `a0c27ff382c411af1301dcc1cd8205c9aeb81996`，解引用到源码提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`。
- 调查时官方 `master` 也指向 `a60891aea193d92e7e5c3942700eca63f9d19a5f`。本文只引用该提交的 README 和文档，避免让未固定页面的措辞漂移。
- 来源：[v5.0.1 release](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)、[v5.0.1 源码提交](https://github.com/Genymobile/scrcpy/commit/a60891aea193d92e7e5c3942700eca63f9d19a5f)、[固定 README](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/README.md)、[固定开发者文档](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md)。

### `35~70ms` 的来源与实验条件

v5.0.1 README 的功能列表把低延迟写成 `35~70ms`，并把链接指向 [PR #646](https://github.com/Genymobile/scrcpy/pull/646)。该 PR 同时解释了当时 H.264 包边界处理为何会多等一帧：

- Android server 知道 `MediaCodec` 输出的完整包边界，但旧客户端把原始码流交给 FFmpeg，经 `av_read_frame()` 或 parser 判断帧结束时，需要看到下一帧的数据。
- 维护者改为由设备发送每个包的元数据，客户端直接按完整包送入 decoder，从而取消“等待下一帧才开始解码当前帧”的额外等待。
- 实验在 Android 设备上播放从 0 递增、每秒 30 帧的计数视频，在桌面 scrcpy 窗口观察对应数字。PR 报告：

  | 抓取尺寸 | 修改前 | 修改后 | “收到包后到渲染”的平均值 |
  | --- | ---: | ---: | ---: |
  | 1080×1920 | 约 3 帧，约 100ms | 约 2 帧，约 67ms | 12ms |
  | 448×800 | 约 2 帧，约 67ms | 约 1 帧，约 33ms | 8ms |

  PR 还说明渲染值是在关闭跳帧、使用 `--render-expired-frames` 的条件下测得；这些是作者报告的观察值，没有样本数量、分布、设备型号、宿主系统、连接方式或当前版本复验。

因此，这个实验最多证明该方案在当时的桌面视觉镜像路径上减少了一帧等待，不能证明：

- Android/Flutter 主控也有相同延迟；
- 触控或按键从主控发出，到目标应用响应并回到画面的总往返小于 70ms；
- 当前手机硬件、编码器、Codec、Flutter renderer 或 Wi-Fi 都有相同表现；
- `35~70ms` 是任何设备上的 P50、P95 或产品承诺。

README 链接的是 PR，而 PR 在 2026 年补充了“测量很旧、较新设备更好”的说明，这也说明该数字不能替代当前基准。

### 官方客户端与被控端的职责

v5.0.1 README 的平台描述是：

- scrcpy 通过 USB 或 TCP/IP 镜像 Android 设备；
- 使用计算机的键盘和鼠标控制设备；
- 客户端支持 Linux、Windows、macOS；
- Android 设备最低要求 API 21，音频转发要求 API 30+。

开发文档进一步把两侧明确分开：

- server 运行在 Android 设备上，作为 `shell` 进程采集屏幕、用 `MediaCodec` 编码，并通过 socket 发送视频、音频和控制消息；
- client 运行在宿主计算机上，使用 SDL 建立 UI 和输入事件循环，使用 FFmpeg 解码；
- 视频默认不增加播放缓冲；新帧尽快显示；
- 输入事件由 client 主线程转换为控制消息，进入 controller 队列，再由独立线程写入 socket；
- server 的 controller 从 socket 读取控制消息，并注入 Android 输入系统。

来源：[README](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/README.md)、[客户端结构](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md#client)、[视频采集与编码](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md#screen-video-encoding)、[输入注入](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md#input-events-injection)。

这些文档没有给出 Android client 支持。官方 issue [#7022](https://github.com/Genymobile/scrcpy/issues/7022) 是 2026-09-04 提出的“直接在 Android 上运行 scrcpy 自身作为客户端”功能请求，调查时仍为 open、没有评论或关联实现。该 issue 只能证明这个能力尚未成为官方已交付内容，不能把第三方实现视为官方兼容路径或官方性能证据。

### 第三方 scrcpy-mobile 的固定来源

本次另核对 GitHub 上同名、关注度最高的 [wsvn53/scrcpy-mobile](https://github.com/wsvn53/scrcpy-mobile) 固定提交 [`cdbc6ac7`](https://github.com/wsvn53/scrcpy-mobile/tree/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09)（2026-10-21 核对）。它实际是 **scrcpy C client 的移动宿主移植**，不是另写一套编解码协议：

- 仓库把官方 scrcpy 作为 submodule；固定 wrapper 指向 scrcpy 提交 `2322868e9e256eb5fce0b3d659ab2a409f29bae1`（2026-05-12，接近 v4.0），并用 `porting/src` 替换平台入口。
- [README](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/README.md) 说明项目面向 iOS/Android 手机控制 Android，但同一快照明确写“目前只支持从 iOS 控制 Android”；不能把它扩展成已经验证的 Android 主控方案。
- [ScrcpyADBClient.m](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/scrcpy-app/ADBClient/ScrcpyADBClient.m#L368-L383) 设置 `--video-buffer 0`、默认 `4Mbps`，并保留 scrcpy 的原始 packet framing。
- [decoder-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/decoder-porting.c) 使用 VideoToolbox 硬件解码，绕过 SDL 的 CPU YUV 上传；[texture-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/texture-porting.c) 在硬件层渲染时直接跳过 SDL 纹理更新。
- [ScrcpyRuntime.m](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/scrcpy-app/ADBClient/ScrcpyRuntime.m#L240-L425) 把帧直接交给 `AVSampleBufferDisplayLayer`，标记 `DisplayImmediately`；显示层忙时先丢弃当前帧，只有连续停顿达到 2 秒才 flush 并请求视频重置。
- 输入仍复用 scrcpy client 的 60 项控制队列和独立发送线程；[input_manager-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/input_manager-porting.c) 主要修复 iOS 压力值恒为 0 和系统手势取消事件，不是网络预测或自研拥塞控制。

因此，scrcpy-mobile 的低延迟来源与官方 scrcpy 相同：原生 packet 输入、低延迟硬件解码、默认无视频缓冲、显示前最新帧语义，以及输入发送不等待远端注入结果。它没有把 ADB/TCP 改成 WebRTC，也没有公开证据证明其在丢包、跨公网或高抖动网络下仍保持桌面局域网延迟。

### 官方默认值与可调参数

固定版本文档给出以下与延迟有关的默认事实：

| 项目 | 默认或说明 | 不能推出 |
| --- | --- | --- |
| 视频缓冲 | 默认没有额外视频缓冲，以最低延迟为目标；`--video-buffer` 可用于抖动平滑 | “无缓冲”不等于链路没有排队或解码延迟 |
| 音频缓冲 | 不可避免；默认目标为 50ms，可调整 | 该 50ms 不能加入视频输入到画面的总延迟，音画要另行建立共同时钟 |
| 视频码率 | 默认 8Mbps | 更高码率不保证更好或更差延迟，取决于编码器和网络 |
| 编码 | H.264 为默认；文档称 H.265 质量可能更好，但 H.264 应有更低延迟 | 文档排序不是对所有设备、所有帧内容的实测保证 |
| 尺寸 | `--max-size` 可限制宽高，README 称降低分辨率可能显著改善性能 | 低分辨率不证明触控响应、Flutter 合成或 GPU 呈现同步改善 |
| 帧率 | `--max-fps` 限制采集帧率；画面不变时不产生新帧 | 采集上限不等于实际持续帧率或输入延迟 |
| 解码 | 桌面客户端默认尝试硬件解码，失败回退软件；Linux 需要 EGL/VA-API，Windows/macOS 有各自后端 | 不能将桌面 hardware decode 默认值移植为 Android/Flutter 必有同等路径 |

来源：[视频选项](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/video.md)、[音频缓冲](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/audio.md#buffering)、[连接方式](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/connection.md)。

### 固定源码中的包路径

v5.0.1 client 的 `demuxer.c` 直接读取协议中的 codec、session 尺寸、12 字节包头和 payload，不经过通用容器探测；`decoder.c` 使用独立线程，入队后由解码线程取包，并设置 `AV_CODEC_FLAG_LOW_DELAY`。`frame_buffer` 只保留一个待消费的解码帧，新帧可替换旧帧。默认不创建视频 regulator，除非显式设置 `--video-buffer`。

这与[客户端低延迟路径](scrcpy-client-latency-path.md)中的源码结论一致。它说明官方路径释放了已有包边界和最新帧替换的延迟，但仍不能证明从输入事件到最终扫描显示的整体上限。

来源：[固定 demuxer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c)、[固定 decoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c)、[固定 frame buffer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c)。

### 静态屏与首帧

开发文档说明只在新帧产生时发送画面；静止画面在启动时可能没有帧，快速运动后最后一帧质量也可能下降。官方以 `KEY_REPEAT_PREVIOUS_FRAME_AFTER` 解决这两个问题。固定 v5.0.1 server 设置重复间隔为 100000µs（100ms），并设置 `KEY_PRIORITY=0`、API 26+ `KEY_LATENCY=1`。

这 100ms 是允许编码器重复上一帧的配置间隔，不是端到端首帧预算，也不保证具体编码器准时回调。首帧、持续视频延迟和输入往返必须分别验证；固定源码分析见[首帧与性能核查](scrcpy-first-frame-performance.md)。

来源：[SurfaceEncoder 固定源码](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)。

## 从官方来源到移动端指标的推论

**推论：** 如果产品主控是 Android 或 Flutter，实际路径至少是：

```text
主控输入事件
  → Android/Flutter 事件与坐标转换
  → Rust/control socket
  → 被控 server 注入
  → 目标应用处理与绘制
  → 被控 Surface/虚拟屏
  → MediaCodec 编码
  → ADB/网络与中继
  → 主控 decoder
  → 纹理/GPU 合成
  → 主控帧调度与显示
  → 可读像素或面板扫描
```

官方实验只覆盖了其中“编码包到达后到桌面窗口渲染”的一段，并以视觉计数代替输入往返。移动端新增或改变的事件处理、Texture、Flutter renderer、系统 decoder、后台调度、网络和屏幕同步，都应由本项目自己的可复现实验回答。

建议在报告移动端延迟时同时写明：

- **对象**：Android 主控、被控 Android 或两者版本；主机/虚拟设备型号。
- **方向**：视觉镜像延迟、输入到目标绘制、输入到解码像素、输入到最终屏幕扫描，或音画同步。
- **起止点与时钟**：输入事件时间、目标 draw/PTS、socket 包、decoder callback、renderer submit、可读 snapshot；跨设备不能直接相减。
- **环境**：USB/TCP、Wi-Fi 频段与拓扑、profile/release、CPU/GPU、编码器、Decoder、分辨率和码率。
- **分布**：样本数、P50/P95/P99、失败样本、冷/热启动和持续时间；平均值不能替代尾延迟。
- **证据层级**：源码、主机夹具、模拟器、GPU 截图、实体设备可读像素和最终面板要分别命名。

本仓库现有严格历史门禁为首帧 1000ms、输入到可读像素 P50≤200ms/P95≤300ms、窗口确认 3000ms；它们是特定测试环境的历史预算，不是外部 scrcpy 官方指标，也不能自动成为产品 SLO。当前实测和未覆盖边界见[视频性能记录](../implementation/video-performance.md)。

## 不应采用的说法

- “scrcpy 官方保证移动端 35~70ms 延迟。”
- “35~70ms 是触控到目标响应的往返延迟。”
- “官方支持 Android 客户端，所以可直接复用其性能结论。”
- “默认无视频缓冲，因此端到端只由网络决定。”
- “桌面端使用硬件解码，手机端 Flutter/Texture 也必然一样。”
- “把各段中位数相加就是端到端中位数。”

## 本报告未回答的问题

- v5.0.1 在 2026 年实体 Android 主控、Flutter profile/release 下的 P50/P95/P99；
- Wi-Fi 漫游、拥塞、TCP 重传和跨公网时输入延迟与视觉延迟的差异；
- 不同 OEM MediaCodec、GPU、Impeller/Skia renderer 和显示刷新率的影响；
- 音频 50ms 目标与视频共同时钟下的音画偏差；
- `wsvn53/scrcpy-mobile` 在真实 iOS 设备、不同 Android 厂商、Wi-Fi 丢包/高 RTT 下的 P50/P95/P99；本文只核对固定源码，没有运行其二进制或建立性能 A/B。
