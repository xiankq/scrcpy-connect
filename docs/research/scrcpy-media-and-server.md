# scrcpy 媒体、server 与 Flutter 接入调查

调查日期：2026-10-16。用途：为 grill-with-docs 提供可追溯事实和后续问题；不是已批准的架构决策。

约束来自当前访谈：Rust + Flutter + FRB；先实现 Android 主控端，主控 Android 7+；被控 Android 5+ 按能力分级；被控端不装 APK、不 root，允许临时 shell JAR；完整功能目标不裁成 MVP；未来保留 iOS / Windows / macOS 接口，本轮不声称验证这些平台。用户已接受 fvp 底层 MDK 闭源，要求媒体实现可替换。

本文标记：**已证**是官方文档或固定源码直接说明；**推论**是从已证事实得到的工程判断；**需 POC**表示尚未执行设备验证，不能写入产品保证。不存在把若干单独能力组合后就当作可以同时工作的默认假设。

## 来源与版本边界

| 对象 | 本次锁定版本 | 来源与边界 |
| --- | --- | --- |
| scrcpy | 最新正式 release `v5.0.1`，2026-10-08 发布；解引用后的源码 commit `a60891aea193d92e7e5c3942700eca63f9d19a5f` | [官方 release][S01]；通过 `git ls-remote` 核对 annotated tag 与 commit。下文 server/client 源码均固定到该 commit。 |
| 官方 server JAR | `scrcpy-server-v5.0.1`；SHA-256 `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536` | [官方构建说明][S02]及 release asset digest。这里只核对官方公布值，未下载二进制重新计算。 |
| fvp | pub.dev 当前 `0.39.1`；tag `v0.39.1` → `a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93` | [pub.dev][F01]、[固定 README][F02]。本轮未运行 Flutter 或编译插件。 |
| MDK | 为调查选定正式 tag `v0.39.0` → `3c3a03646ca2c51a8969bcea9f81cbecce0770df` | [固定 README][M01]。这不等于 fvp 各平台构建自动用了该不可变二进制；SDK 下载地址、摘要与日志仍须锁定并核对。 |
| FRB | 当前 stable `2.13.0`；tag `v2.13.0` → `8631db91a90c699439c9ce2a1fb4164ae8661da9` | [pub.dev][R01]、[固定 zero-copy 文档][R02]。不采用 beta 的行为作承诺。 |

先查 Context7 的 fvp / FRB 文档，再读取上述项目官方仓库、Android / Flutter 官方 API。MDK wiki、Android 和 Flutter 在线文档属于调查当日内容，可能变化。scrcpy v5.0.1 的 `doc/develop.md` 仍保留“4.0”叙述和命令示例；本文遇到差异以 v5.0.1 `Options`、`Streamer`、`DesktopConnection` 和客户端 demuxer 的实际实现为准，不照抄旧示例中的版本参数。[S03]、[S04]、[S05]、[S06]、[S07]

## 已证：启动、协议和生命周期

1. **它是通过 ADB 启动的 shell Java 程序，不是常驻已安装应用。** 官方客户端上传 dex JAR 到 `/data/local/tmp`，使用 `CLASSPATH=... app_process / com.genymobile.scrcpy.Server <version> ...`；server 校验传入版本与其构建版本完全一致。协议没有跨版本兼容保证。自建 Rust 客户端需要自己实现这个固定版本协议，并绑定匹配 JAR；不能仅发送一个“支持 scrcpy”的模糊版本号。[S03]、[S04]、[S08]
2. **reverse / forward 是运输方式，不改变应用层主控关系。** 默认尝试 reverse：主控监听，被控 server 连接；失败可退到 forward：被控监听，主控连接。自建 ADB 客户端可以实现等价运输，但不能假设桌面 `adb server` 的反向映射在所选 Android ADB 库中自动存在。[S06]、[S09]
3. **video → audio → control 按启用项固定排序，同名 socket 顺序建连。** forward 模式只在第一个启用通道发送一个 dummy byte。全部启用通道接好后，server 才在第一个通道写 64 字节设备名。只启用 audio 或 control 时，设备名也不在 video 上。若主控先连 video、等设备名、再去连 audio，会和等待剩余连接的 server 互相阻塞。[S06]、[S08]
4. **SCID 只隔离 socket 名称。** `scrcpy_%08x` 的 31 位随机 SCID 支持同一设备多个客户端，未指定时使用 `scrcpy`。它不隔离应用任务、编码器、声音、剪贴板、全局设置或摄像头资源。[S06]（最后一句是由名称用途得出的推论，资源证据见后文。）
5. **流初始 codec-id 为 4 字节；视频后续存在反复出现的 12 字节 session 包。** session 包给出宽、高和是否由客户端 resize 触发；最高位区分 session 与 media。普通 media 包为 12 字节头加 payload：config / key-frame 标记、61 位微秒 PTS、32 位 payload 长度。config 包没有有效媒体 PTS。音频无视频 session 包；codec-id 的特殊值 0 / 1 表示禁用流 / 配置错误。不能把旧版“codec 后一次宽高”解析器拿来读此版。[S05]、[S07]
6. **旋转不是一个可任意叠加的客户端角度字段。** server 处理物理方向与 capture transform，客户端看到编码尺寸；旋转、显示属性变化或 flex resize 会重置捕获 / 编码并发送新 session。H.264 / H.265 config 会重新出现；官方 demuxer 将配置附加到后续普通包，AV1 不走同一套 H.26x config 合并分支。Rust 层必须保留 session 边界、codec 配置与 PTS，而非只拼 payload。[S05]、[S07]、[S10]、[S11]
7. **控制坐标有时效。** touch 包含产生事件时的视频尺寸；server 用当前映射转换，尺寸不匹配可丢弃事件。快速旋转、缩放后继续沿用旧画面坐标，不会自动得到正确点击。独立显示的输入目标是 display-id，设备主屏与虚拟显示走不同映射。[S12]
8. **退出有多层清理。** server 停止各 processor、关闭连接、释放捕获资源，并显式 `System.exit`。另启 cleanup 子进程，监视父进程管道 EOF、恢复部分设备状态，并删除 server JAR。官方客户端退出还有 1 秒 watchdog：源码明确某些设备睡眠时只关 socket 不足以解开阻塞，随后终止启动 server 的本地主机进程。重写 Android 主控时必须重新证明“关闭 ADB shell channel → 远端 app_process 退出”的实际效果，不能把桌面杀本地 `adb shell` 进程的行为直接照搬。[S08]、[S13]、[S14]
9. **cleanup 不是事务隔离，也不是所有临时 JAR 的回收器。** 它恢复 touches、stay-awake、screen-off timeout、部分显示电源 / IME 状态，且 `SERVER_PATH` 约定为 classpath 第一项。多 server 同改全局设置可发生先后恢复冲突；自建扩展 JAR、额外 socket、临时文件不会因为官方 cleanup 存在就全部得到清理。[S04]、[S13]

## 已证：独立应用窗口、并行会话和摄像头

| 能力 | 官方实现事实 | 不能顺带推定的内容 |
| --- | --- | --- |
| 主屏镜像 | 一次 server 捕获一个配置的视频源，使用一个视频编码器。[S08]、[S10] | 不等于一个 server 可以同时输出主屏、三个应用窗口和摄像头。 |
| 新虚拟显示 | server 明确要求 Android 10+；创建自己的 display；关闭会释放。[S08]、[S15] | Android 5–9 的基础兼容不包含此功能。 |
| 在显示上启动 app | 用 launch intent、`FLAG_ACTIVITY_NEW_TASK`、`setLaunchDisplayId`；可选 `+` 前缀先 force-stop package。[S12]、[S16] | 不是“复制任意 app 的独立进程 / 登录态”；force-stop 会作用于该 package，而非只关闭某个窗口。 |
| 同 app 多窗口 | Android 多实例还取决于 app 的 launch mode、task 与 manifest 适配。[A01] | 两个虚拟 display 不保证同一个第三方 app 可以保留两个独立实例。 |
| 关闭虚拟显示 | 默认销毁其内容；`vd_destroy_content=false` 对应把 app 移回主屏的选择。[S15] | “关闭小窗口”和“结束被控 app”不是天然同义，必须明确产品语义。 |
| 动态 resize | flex display 才能接受 requestResize；server 防抖并按编码约束修正尺寸。[S11] | 拖动窗口每一个像素都产生同等大小编码帧并不成立；非 flex 发 resize 会失败。 |
| 焦点 / IME | Android 13+ 才增加 own-display-group 等标志，14+ 增加 own-focus；IME 默认可能出现在主屏。[S11]、[S15] | 多个窗口都能同时输入文字、各自独享键盘焦点，不能按 Android 10+ 一刀切承诺。 |
| camera source | 要求 Android 12+；server 在 ScreenCapture / NewDisplayCapture / CameraCapture 中选择其一；相机默认音源变为被控麦克风。[S08]、[S17] | 相机模式不会自动同时镜像屏幕；原协议没有动态切换 source 的控制命令。[S18] |
| 多摄像头 / 相机占用 | Camera2 并发组合是设备能力；官方明确不保证两个不同客户端并发访问，即使同应用组合被列为支持。[A02] | 另起一个 JAR 和被控微信 / 拍照 app 同用镜头不保证成功；关闭、拔外置相机、被高优先级使用者抢占需要恢复。 |
| 多编码器 | `getMaxSupportedInstances` 只是资源上界提示，实际可运行数量可能更少。[A03] | 有多个 SCID 或参数列表显示某 encoder，不保证多个 1080p / 60fps 会话能同时工作。 |

**推论：**如果“多个独立 app 窗口”暂通过多个官方 server 实例实现，应将每个窗口视为独立捕获 / 编码资源，另做设备级协调。需要实测同设备多 server 的 JAR 路径上传 / 删除时序、主屏电源和设置恢复、音频重复捕获、task 迁移、摄像头抢占。固定 SCID 之外没有已证的跨实例资源仲裁。避免共用一个会被 cleanup 删除的上传路径，是可验证的工程措施，尚非这里已批准的设计。[S06]、[S08]、[S13]、[A03]

**必须区分两种“多会话”。** 多个被控设备各自拥有显示、编码器、相机、设备剪贴板与系统设置；它们主要在主控侧竞争解码 / 渲染 / 带宽、扬声器 / 蓝牙路由及主控剪贴板。单一被控设备的多个 SCID / 多个虚拟或物理显示，则共享该设备的服务与资源。各 server 的 clipboard listener / setClipboard 指向同一设备剪贴板；多路双向同步要决定哪个会话拥有写入权并避免同步回环。对同一物理显示的电源、旋转和输入会相互影响；虚拟显示的 display-id 可区分输入 / 旋转目标，但 stay-awake、部分电源恢复和全机声音仍不能当作窗口私有状态。音频源由每个 server 启动参数选择，却可捕获同一系统混音，不能由不同 SCID 推导出不同 app 音轨。以上设备级仲裁与主控资源仲裁应分别定义；支持多个 display 更不等于第三方应用可以随意多开。[S12]、[S13]、[S16]、[S28]、[A01]

## 已证与推论：官方 JAR、扩展 JAR、fork 的边界

- **已证：**官方 server 能独立运行，临时额外 dex JAR 也能按 shell `app_process` 模式启动；无需把这个执行模型改成安装 APK。[S03]
- **已证：**官方 control 消息编号及解析是固定枚举；未知类型抛 `ControlProtocolException`。额外 server option 只会告警忽略，不能靠添加未知 option 获得扩展执行。官方没有“从旁加载任意 JAR 自动给当前控制协议注册新命令”的公开机制。[S04]、[S18]、[S19]
- **推论：**“官方 JAR + 独立扩展 JAR”可隔离自定义 RPC、文件或设备服务实验，但两个进程的权限、生命周期、socket、版本协商和资源归属仍需自己实现。它不能直接给正在运行的官方 SurfaceEncoder 加参数，也不能自动把主控麦克风送进任意被控 app 的 AudioRecord。
- **推论：**若必须在同一个捕获图中同时输出 screen / camera、动态调码率或只请求 IDR 而不重建编码器，需要证明旁路进程能达成，或维护 server fork。fork 可以修改已有处理链，但会承担 Android hidden API / ROM workaround、每次协议升级和 cleanup 的维护。scrcpy 自身采用 Apache-2.0，不代表其所有主控侧媒体依赖也采用同一许可。[S20]
- **需 POC：**把独立扩展 JAR 当成研究路线，而非“所有系统接口都已可调用”的事实。具体能力必须逐项验证 shell UID、系统签名权限、SELinux、ROM 服务实现及 Android 版本；反射拿到 Java 方法不等于服务端授权成功。

## 已证：编码、恢复与背压

1. v5.0.1 提供 H.264、H.265、AV1，另有 VP8 / VP9；文档仍明确 H.264 应更低延迟，AV1 encoder 在 Android 设备上不常见。选择需取**被控编码能力与主控解码能力的交集**；这句交集是工程推论，官方 server 没有替 Android 主控自动完成此协商。[S21]、[S22]
2. `list-encoders`、具体 encoder-name、codec-options 是实际入口；SurfaceEncoder 先创建所选 codec，再 configure。其恢复路径是一定次数重试、套用 encoder constraints、必要时降分辨率，不是自动遍历 H.264 / H.265 / AV1 的协议协商。[S10]
3. 编码器尺寸有 alignment、profile/level、吞吐与当前资源约束；capability 列表不是成功 configure / sustained run 的保证。[S10]、[A03] **需 POC：**测 decoder 名称和实际软硬解、首帧、稳定帧率、温度、功耗与多窗口总负载，不能只记录 codec 枚举。
4. 官方屏幕帧率本来可变：静态画面不按承诺的固定 fps 产生新帧。SurfaceEncoder 配置重复前帧和 I-frame interval（默认 10 秒），但不得据此把无新帧判定为断连，也不能用固定 60fps 重造原始时间线。[S10]、[S21]
5. 原 control 有 `RESET_VIDEO`，对应 EOS / 重启捕获编码，**不是**仅请求一个关键帧。Android 提供 `PARAMETER_KEY_REQUEST_SYNC_FRAME`，但官方此版没有把它作为单独 control 消息公开。发生解码丢参考帧、从后台恢复或网络换线时，等待 GOP、reset、扩展 IDR 请求各有恢复时间和画面中断代价。[S10]、[S18]、[S23]、[A04]
6. server 把编码 packet 同步 `writeFully` 到流，再 release 输出 buffer。主控读得慢会沿 socket / ADB 堆积并阻塞编码线程；客户端把所有 packet 排进无界队列只是换了堆积位置。官方 frame buffer 替换的是**已解码待显示帧**，不能据此任意丢压缩 P/B 帧。压缩队列的丢弃需保留可解码参考链，或丢到可恢复关键帧并重新配置。[S10]、[S24]、[S25]（背压传播和丢弃策略为推论。）

## 已证与推论：Rust、fvp / MDK、Dart、Texture 两条路径

### 接口证据

- MDK 的 `setMedia("stream:")` 配合 `appendBuffer(const uint8_t*, size_t, int)` 是字节流输入；官方有 WebSocket 把 FLV 数据追加进去的示例。`avformat.input` 可以强制 demux 格式，wiki 特别提到裸 H.264。它不是接受 scrcpy header 的专用 demuxer。[M02]、[M03]
- fvp 高级 `Player` 暴露 `nativeHandle`，实际为 `mdkPlayerAPI*` 的地址；其生成 C FFI binding 中存在 `appendBuffer`，但高级 Dart `Player` 尚无同名包装。原生 fvp 通过该 handle 构造 MDK Player 并附着 Android Surface。因此存在扩展绑定或 C ABI shim 的入口；必须按真实结构和生命周期使用，不能把它当成 `mdkPlayer*` 或任意 decoder 指针。[F03]、[F04]、[F05]
- 原生 MediaCodec 输入 API 接受每包 presentation-time；Flutter Texture 只用 texture ID 表示后端纹理，到帧自动重绘通常不执行 Dart。把解码像素逐帧经 FRB 回传再构造 Dart Image，不是使用 Texture 的必经路线。[A05]、[A06]
- FRB 官方 zero-copy 文档明确其保证有场景限制，Rust → Dart 异步 / stream 的 typed byte arrays 是典型支持情形。它没有保证 Dart → 后续播放器输入、FFmpeg demux、codec input buffer、GPU / Flutter 合成全过程都零拷贝。[R02]

### 候选 A：Rust 解 scrcpy 包后直接进原生媒体适配器

```text
ADB stream → Rust 协议/session/config/PTS → native media adapter → decoder → Surface / Flutter Texture
                                 └────→ recorder（保持设备时间戳）
Flutter / FRB：控制、状态、指标、纹理句柄；不要求逐帧传像素
```

**推论：**此路线可以把带 PTS 的 packet 边界保留到 decoder / recorder，媒体适配器可切换直接 MediaCodec 或 MDK 的适当入口；但只有“接口存在”的证据，不等于已实现跨端框架。Android texture / Surface 的创建、重建、释放仍需原生插件。若选 MDK `appendBuffer` 入口，它仍是下述 B 的字节流问题，不因调用者改为 Rust 就自动保留 PTS。

### 候选 B：Rust 输出到 fvp / MDK 字节输入

```text
ADB stream → Rust 解协议 → 裸 elementary stream 或重新封装的流 → MDK appendBuffer / 本地标准流 URL
                           （可经 Dart 扩展绑定，也可原生 shim）             → fvp texture
```

**已证：**scrcpy 提供 `raw_stream=true`，去掉设备 / 流 / 帧元数据，官方用裸 H.264 TCP 给 VLC 的示例；因此本地转封装不是 H.264 的理论必需步骤。**推论：**正常模式保留 header，在 Rust 解析后只向 MDK 追加 codec payload 也可作为实验。但这两者都会使 `appendBuffer` 本身拿不到 scrcpy 的逐帧 PTS 和视频 session 事件：其签名没有 PTS / stream-id / dimensions 参数。播放器从裸流重新探测 / 推断时序不等于恢复设备原时间线。[S03]、[M02]

**需 POC：**对 H.264 / H.265 / AV1 分别验证 raw demux 格式、config、首帧、可变帧率、长时间静态、旋转 / flex resize / codec reset，以及 EOF / 取消。若音视频要精确同步或无重编码录制，需证明重新封装能保留原始 PTS（且容器接受 codec、音频 codec 和尺寸变化），或找到明确的 packet-level decoder 接口。`video_player.networkUrl(...)` 存在，不构成可播放 scrcpy 私有协议的证据。

**低延迟的限制：**fvp `lowLatency=1` 配置零最小缓冲及降低探测；`2` 另设 1000ms 上限与 drop。源码注释 `+nobuffer` 可能丢首个关键帧包。MDK 可以进一步设置 buffer range；Android AMediaCodec 的专门 `low_latency` 模式要求 API 30+。这些选项没有给本项目端到端延迟上界，Android 7 主控不能假设具备 API 30 decoder 模式。[F06]、[M02]、[M04]

**Surface 生命周期：**fvp 原生实现区分普通 GL/Texture 与 decoder 直连 Surface；直连 Surface 销毁前要释放 codec，源码直接记录顺序错误可能导致 decoder 卡住、下一个 Surface 不出帧。**推论：**后台、锁屏、窗口转移、旋转、Flutter view 重建必须触发媒体生命周期处理，不能仅保留旧 texture ID。不同 renderer / 路径的 GPU 零拷贝也不能代替整条网络到显示链路的拷贝测量。[F05]、[A06]

## 已证：音频、回传、通话与录制

### 下行音频及同步

- scrcpy 音频捕获整体要求被控 Android 11+；Android 11 启动需解锁 / 临时 shell Activity workaround，12+ 不需这一步；10 及更低自动无音频。音频捕获失败默认继续视频，`require-audio` 才要求失败整个会话。[S26]、[S27]
- 可选 Opus（默认）、AAC、FLAC、PCM；部分设备无 Opus encoder，需要更换。原始 PCM 省编码但需要音频参数及更高带宽，不等于无缓冲。官方音频目标缓冲默认 50ms、输出缓冲 10ms，与视频默认不缓冲不同。[S26]
- `output` 默认捕获设备总输出并关闭本机播放；`playback` / `audio-dup` 能保留设备播放，但要求 Android 13+，应用可拒绝被捕获。shell 的实现用 hidden audio policy，不能直接把普通 app 的 AudioPlaybackCapture 权限限制等同于它，也不能保证所有受保护 / 通话声音都捕得到。[S26]、[S28]、[A07]
- 原音频源没有按当前虚拟窗口 / package / display-id 分离的公开选项；另开两个 app 窗口不自动得到两条互相独立的应用声音。[S26]、[S28]
- AudioRecordReader 用设备 monotonic timestamp，失败时按样本时长估算并保证 PTS 单调；录制使用设备微秒时间基、共同 origin。**推论：**A/V 同步需保留同一设备时间线，再决定播放时钟 / 缓冲；两个独立裸流播放器都“低延迟”不保证嘴型同步，主控与被控的 monotonic 时钟也不能直接相减当单向网络时延。[S29]、[S30]

### 主控麦克风回传与电话

- **已证：**官方 audio socket 是 server → client；现有 control 协议没有主控音频 payload / 被控音频输出通道。因此 `--audio-source=mic` 指的是**被控端**麦克风，不是主控麦克风回传。[S03]、[S18]
- **推论：**扩展 JAR 可研究接收音频并用 AudioTrack 播放，但“被控扬声器播出”与“被任意被控 app 当作麦克风输入”是两项能力。本轮没有官方依据证明后者在不安装被控 APK、不 root 条件下可通用实现；不能把传字节成功当作虚拟麦克风成功。电信通话上行注入更没有因此被证明。
- **已证：**Android 对并发录音有优先级 / 静音规则，通话优先；通话捕获涉及特权权限。主控端音频焦点、来电静音与前台服务条件另受系统约束；Android 15+ target 的 app 非顶层且无前台服务时不能请求音频焦点。蓝牙通信设备选择和媒体播放路由也不同，通信输入可能随系统所选 output 自动匹配。[A08]、[A09]、[A10]
- **需 POC：**分别验证远程听声、被控 mic 监听、主控对讲到被控扬声器、给特定 app 提供远端 mic、电话 / VoIP 接听。包含双方来电、蓝牙连接 / 断开、免提切换、双端同时录音、回声与反馈；不能用一项成功覆盖其他项。

### 录制和方向

- 官方录制在主控侧复用编码包 mux，不抓 Flutter 窗口；使用设备 PTS，网络抖动不改写源时序。官方 recorder 等待配置包、统一音视频 origin、修正非单调 PTS，结束调用 muxer trailer。[S30]、[S31]
- capture-orientation 会改变收到的画面；客户端 record-orientation 是 MP4 / MKV 的显示变换，不重编码像素；record 不支持 flip。播放方向和录制方向可以分开。[S21]
- **推论 / 需 POC：**播放器正确显示一次旋转，不代表输出文件所有消费软件都正确支持流中尺寸变化。固定录制方向、重编码固定 canvas、遇变化分段、原包单文件各有不同结果；须测用户实际的系统相册 / 分享 / 编辑器。应用被杀或磁盘满导致 trailer 未写完后的可恢复性也未证实，不能宣称所有 MP4 都可恢复。[S30]

## 需要带回访谈的具体约束 / 故障场景

以下不是删功能清单；是完整目标必须定义行为的场景。

| 编号 | 场景 / 约束 | 证据等级与含义 |
| --- | --- | --- |
| C01 | video 已连，主控等设备名才连 audio | **已证**启动死锁；所有启用通道建连有先后要求。[S06]、[S08] |
| C02 | 更换 JAR 但没更换协议解析器 | **已证**版本拒绝或包格式错读；升级应成套。[S04]、[S07] |
| C03 | 被控旋转 / 折叠 / flex resize 后仍按旧头解析 | **已证**新的 session 包可能被误当 payload 长度；同时旧坐标可被丢弃。[S05]、[S12] |
| C04 | Android 5–9 上要求真正独立 app display | **已证**不满足新虚拟显示版本条件；需明确不可用原因而不是永远重试。[S08] |
| C05 | 打开第二个同 app 窗口，原窗口移动或消失 | **推论**task / launch mode 决定，不是 SCID 能隔离。[S16]、[A01] |
| C06 | 用户关小窗口时 app 被销毁，或突然出现在主屏 | **已证**两种关闭策略行为不同；需选语义。[S15] |
| C07 | 两个虚拟窗口争键盘焦点 / IME 出主屏 | **已证 + 需 POC**不同 Android 版本 display flags 不同。[S11]、[S15] |
| C08 | 第三路视频 configure 失败，前两路仍在工作 | **已证资源限制 + 推论场景**并发 codec 数量受实时资源限制。[A03] |
| C09 | 选 AV1 但目标只有 decoder，没有 encoder | **已证能力区分**不能按 Android 版本或 codec 名称承诺双端硬件路径。[S10]、[S22] |
| C10 | 目标宣告支持分辨率，但 encoder 首帧失败 | **已证**官方仍有 configure / 约束 / 降尺寸恢复。[S10] |
| C11 | UI / Dart GC 卡顿后视频越来越落后 | **推论**无界 packet / event 队列积压，需有界队列与观测；FRB stream 本身不是实时背压策略。[S24]、[R02] |
| C12 | 为追实时随意丢 P 帧，随后花屏到下一 IDR | **推论**压缩参考链被破坏；已解码帧替换策略不能直接搬到编码包。[S25]、[A04] |
| C13 | 原始 payload 能播放，但静态时长 / A/V / 录制错位 | **推论 + 需 POC**appendBuffer 没有逐帧 PTS 参数，裸流再探测可能失去源时序。[M02]、[S29] |
| C14 | 从后台回前台仍黑屏，网络与控制正常 | **已证风险 + 需 POC**Surface 失效 / codec 释放顺序需处理；旧 texture ID 不保活。[F05]、[A06] |
| C15 | Android 11 锁屏启动：有画面无声音 | **已证**音频 foreground workaround 条件；默认可降级视频继续。[S26]、[S27] |
| C16 | 两个 app 窗口都在播同一份全机声音 | **推论**原音频无窗口 / app 隔离选择。[S26]、[S28] |
| C17 | 为保留被控本机声音启用 duplication，却录不到某 app | **已证**Android 13+ 且 app 可 opt-out。[S26] |
| C18 | 按“麦克风回传”后声音只从被控扬声器出 | **未证目标能力**不等于任意被控 app 获得虚拟 mic；需拆分定义。 |
| C19 | 主控接电话 / 蓝牙切通信路由，远程音频突然静音 | **已证系统规则 + 需 POC**焦点、route、输入抢占有独立状态。[A08]、[A09]、[A10] |
| C20 | 相机列表能列出组合，但被控相机 app 同时开后断流 | **已证边界**跨客户端并发不保证；相机与屏幕单实例互斥。[A02]、[S08] |
| C21 | 息屏断开网络后远端进程未退出 | **已证官方 watchdog 背景 + 需 POC**Android ADB 库的 shell cancellation 行为未核实。[S14] |
| C22 | 两会话恢复 stay-awake，把仍用中的另一会话设置改掉 | **推论**cleanup 保存旧值但没有跨会话仲裁。[S13] |
| C23 | 两进程共用上传路径，cleanup 提前删 JAR | **推论**已加载进程与未来 class load / cleanup 启动时序需测，独立 SCID 不解决路径复用。[S04]、[S13] |
| C24 | 录制中旋转后，第三方播放器显示错方向 / 尺寸 | **需 POC**容器变换与动态分辨率支持并非同一问题。[S21]、[S30] |
| C25 | 录制遇磁盘满 / app 被杀，文件打不开 | **已证需 trailer + 需 POC**需定义结束、分段、恢复和失败提示。[S30] |
| C26 | 设备静止几秒不更新画面，被判定“连接断开” | **已证可变帧率**媒体无新帧不能独立作为活性检测。[S21] |
| C27 | camera 会话仍接受 screen touch / clipboard 命令 | **已证**camera Controller 只处理该模式的命令子集，不是全屏控制会话。[S12]、[S18] |

## 需 POC：可证伪的验证包

这些是当前范围内的验证顺序和测量范围，不是实现已通过或未来平台运行已验证。C18、C20、C24、C25、C27等录制/专用相机/通用虚拟麦克风资料仅归档，不属于执行清单；通话所需双向音频保留独立验证。

1. **协议与关闭**：在 Android 主控用选定 ADB 库跑固定 JAR；组合 video / audio / control 开关、forward / reverse 等价路径，验证 dummy、首通道设备名、错误码、session/config/PTS；逐阶段取消启动。输出每个阶段时序与远端 PID / socket / 设置恢复证据。
2. **三 codec 原生输入**：相同设备 / 场景比较 Rust → native decoder、Rust → MDK stream（裸流 / 保 PTS 封装）和经 Dart 扩展输入；记录 codec、实际硬解、原始 PTS 到呈现的关系、首帧、队列深度、内存与丢帧。避免把本地主控时钟减设备 PTS 当延迟；用双端视觉计时或可校准方法。
3. **重配置与生命周期**：持续旋转、折叠、flex resize、切后台、屏幕锁定、Flutter Surface 重建、主动 reset、编码器异常；记录有没有必须重连 / 丢音频 / 花屏 / 错点；区分“可恢复”“降质量”“会话结束”。
4. **同设备并行**：主屏 + 两个不同 app display + 同 app 两实例，逐项增加负载，不预设可以同时成功。测 encoder 配额、GPU / 温升、task / IME / focus、关闭顺序、全局设置、每条音频语义；把失败保留为具体能力结果。
5. **声音与通话矩阵**：被控 Android 11 / 12 / 13+，output / playback / dup / mic、Opus / AAC、双方来电、主控蓝牙、VoIP / 媒体 app 切换。双向通话音频依shell通话专项验证，不做通用虚拟麦克风或对讲扬声器产品实验；普通音频播放不能证明电话上行成功。
6. **录制验证包已归档**：不执行录屏容器、录屏保存或恢复实验；当前相册中的已有视频播放与手动取回另见任务10。

7. **扩展 JAR 边界**：独立版本握手、权限探测、异常退出、ADB 断线、重连撞旧实例；核实清理只作用本会话、官方 JAR 与扩展 JAR 相互不覆盖、不误删，不依赖不受支持的跨进程对象操作。

## 许可、替换接口与平台下限：沿用事实

- fvp 为 BSD-3-Clause；MDK 有自己的许可，官方明确 Flutter 用户可免费用于商业软件且包含 key。已接受闭源不等于把 MDK 改成 BSD，也不自动覆盖将来脱离 Flutter 的独立原生产品。FFmpeg 及可选 dav1d / libass 等应按实际分发物保留各自声明；FFmpeg 构建可因 GPL 组件改变许可，锁定二进制后仍需核对。[F07]、[M01]、[M05]
- **推论：**可替换边界至少要保留 codec config、设备 PTS、session/dimensions、解码 / 渲染状态、音频 clock / route、统计与 shutdown 语义；如果接口只暴露 `play(url)`，将来的 packet decoder 替换会被迫重做协议 / 同步层。这里只记录边界必须表达的信息，不决定最终模块 API。
- fvp 自身 Android minSdk 21；Darwin podspec iOS12 / macOS10.13；FRB模板更低值只是模板。当前 Flutter 官方支持页对应 3.47：Android API24+、iOS15+、Windows10+、macOS12+。因此当前 Flutter 的 Android7+ 主控基线一致；被控 Android5+ 是 JAR 功能分级，不能和主控运行平台混为一谈。未来 Apple / Windows 仅有依赖支持证据，本轮未验证构建和行为。[F08]、[F09]、[R03]、[R04]、[A11]

## 2026-10-17 多编码与设备级质量实施验收

以下是该日实施事实。2026-10-18默认主屏H264自动编码器的冷目录策略已调整为
直接尝试实际捕获，不把unknown标成available；已知不支持及非默认格式／named
encoder／独立应用窗口继续预检。质量选项和设置保存仍枚举验证。实际范围、失败
样本及后续验收见[冷启动实施](../implementation/video-cold-start.md#默认主屏直接捕获实施2026-10-18)。

Rust core 现使用自己的 ADB 连接运行校验过 SHA 的官方 5.0.1 JAR，传入 `list_encoders=true`，解析设备返回的 `--video-codec` / `--video-encoder`，不按 Android 版本硬编码支持状态。枚举解析遵循固定提交的 [LogUtils](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/util/LogUtils.java)。编码器名称限制为 1–256 个 ASCII 字母、数字、点、下划线或连字符，传给远端 shell 前还会引用整个参数；枚举不兼容的 codec / encoder 组合在启动前拒绝。

`session.quality.options{deviceId?}` 返回五种 codec、MIME、实际 encoder 列表与 `unknown/available/unavailable`、原因。没有设备或探测失败时不返回 `available=true`；已枚举也仅证明设备报告了 encoder，不保证其参数、当前资源或本机 decoder 可配置成功。五种 wire ID 分别为 `h264`、`h265`、`\0av1`、`\0vp8`、`\0vp9`，core 对请求与实际四字节 ID 作一致性校验；默认保持 H.264。[固定 VideoCodec](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/VideoCodec.java)

质量保存在 `settings.deviceQuality[deviceId]`，最多 256 项；未设置的设备继承全局默认。`session.quality` 先验证完整参数及目标实际枚举组合，再仅保存这台设备的下次启动设置，返回 `appliesNextSession/needsRestart`，不隐式停止、替换或迁移任何当前会话/应用任务。元数据恢复生成新设备 UUID 时清空旧质量映射。单次 `session.start/apps.launch` 可提供经过相同验证的覆盖参数，不修改持久化偏好。`videoEncoder:null` 表示由平台选择，不把它虚报为已知的实际 encoder 名称。

官方 `SurfaceEncoder` 在 MediaCodec 配置前就写 codec header，因此 header 不能作为编码成功证据。core 还等待有界的实际编码关键帧：8 秒、最多 64 个包、32 MiB 首帧缓冲；结果标记 `encodedKeyFrameReady`，不冒充主控已经渲染。主控首帧仍由实际 decoder 回报；仅有目标关键帧不足以保证更换本机 decoder 不失败，所以此版没有“无损热切换”承诺。[SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L102)

真实验收使用 `emulator-5556` 的授权 adbd `127.0.0.1:15556`，独立临时 Runtime/会话，不操作主控 `5554`、不安装被控 APK、不重启系统、不改变目标屏幕状态。官方 JAR 实际列出 8 个软件 encoder：H.264 两个、H.265 一个、AV1 一个、VP8 两个、VP9 两个。五种 codec 均收到实际标识、尺寸与关键帧，FFmpeg 强制 `-frames:v 1` 后均产生经 PNG 头核对尺寸的 **324×720** 图像；显式使用 `c2.android.avc.encoder`、`c2.android.hevc.encoder`、`c2.android.av1.encoder`、`c2.android.vp8.encoder`、`c2.android.vp9.encoder`。这验证目标编码与宿主 FFmpeg 解码，不等于 Android 本机五种 decoder 的实际渲染验收。[真实测试](../../crates/interop_core/tests/video_quality_android.rs)

AV1 的原始 packet 不能在测试中随意拼接为无边界 OBU 输入：本次 raw OBU demux 曾失败；保持 access-unit 边界并使用测试专用 IVF `AV01` 封装后真实解码通过。VP8/VP9 同样使用测试 IVF，H.264/H.265 使用原始 Annex B。该封装仅存在测试，不加入产品播放链路。静止画面不保证定时产生后续关键帧，负例保活通过旧 scrcpy 控制通道真实回复验证；测试不伪造 Native 纹理确认。不存在 encoder 返回 `encoder_unavailable` 后原 session ID/codec 不变；有效质量保存后原会话仍保留旧尺寸参数。

测试工具是临时 `imageio-ffmpeg==0.6.0` 提供的 `ffmpeg 7.0.2-static`，SHA-256 为 `e7e7fb30477f717e6f55f9180a70386c62677ef8a4d4d1a5d948f4098aa3eb99`，不作为产品依赖或分发二进制。执行命令：

```sh
env INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  INTEROP_FFMPEG=/tmp/interop-test-tools/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2 \
  /home/xiankq/.cargo/bin/cargo +stable test -p interop-core --test video_quality_android -- --ignored --nocapture
```

补充真实同次启动覆盖：持久化设置保持 VP8 / maxSize 720 时，单次请求 H.264 / maxSize 640，实际解码 **288×640**，随后读取持久化设置仍未改变；含此项完整测试退出 0、耗时 12.79 秒。默认测试另覆盖无设备未知状态、非法参数原子拒绝、设备级偏好隔离/恢复清理、五种 wire ID、解析错误及 codec/encoder 不兼容。AVD 的软件 encoder 成功不代表厂商硬编、长时间运行、多窗口资源或目标设备所有分辨率/FPS 都通过；也没有对未枚举组合实施伪回退。

## 产品与实施边界

真实任务及单实例迁移见[ADR 0005](../adr/0005-real-application-tasks-in-linked-windows.md)；窗口关闭、资源保护和设备声音规则在[交互规则](../../designs/prod/interaction-rules.md)维护。声音按实际打开的控制页面确定设备播放意图，同设备去重，多设备自动混音；固定音源和手动混音模式不属于当前产品。

通话控制与双向语音分别验证；源码接口或普通声音播放不证明目标 HAL、麦克风路由和主控权限均已满足。播放器的实际时间轴、全屏、旋转与 surface 行为以[共享媒体实施](../implementation/architecture.md)及对应运行记录为准。

官方 JAR 与扩展服务的固定版本、源码差异和生命周期见 [servers](../../servers/)。复用服务端 JAR 不等于复用完整客户端；四端依赖说明也不等于[实际整包编译](cross-platform-build-contract.md)通过。

## 一手来源索引

[S01]: https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1
[S02]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/build.md
[S03]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md
[S04]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Options.java
[S05]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java
[S06]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/DesktopConnection.java
[S07]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c
[S08]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Server.java
[S09]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/adb/adb_tunnel.c
[S10]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java
[S11]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/NewDisplayCapture.java
[S12]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/Controller.java
[S13]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/CleanUp.java
[S14]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c
[S15]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/virtual-display.md
[S16]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/Device.java
[S17]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/camera.md
[S18]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/ControlMessage.java
[S19]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/ControlMessageReader.java
[S20]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/LICENSE
[S21]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/video.md
[S22]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/VideoCodec.java
[S23]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/CaptureControl.java
[S24]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/util/IO.java
[S25]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c
[S26]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/audio.md
[S27]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioDirectCapture.java
[S28]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioPlaybackCapture.java
[S29]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioRecordReader.java
[S30]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/recorder.c
[S31]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/recording.md
[F01]: https://pub.dev/packages/fvp/versions/0.39.1
[F02]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/README.md
[F03]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/player.dart
[F04]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/generated_bindings.dart
[F05]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/android/fvp_plugin.cpp
[F06]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/video_player_mdk.dart
[F07]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/LICENSE
[F08]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/android/build.gradle
[F09]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/darwin/fvp.podspec
[M01]: https://github.com/wang-bin/mdk-sdk/blob/3c3a03646ca2c51a8969bcea9f81cbecce0770df/README.md
[M02]: https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs
[M03]: https://github.com/wang-bin/mdk-examples/blob/master/Native/stream.cpp
[M04]: https://github.com/wang-bin/mdk-sdk/wiki/Decoders
[M05]: https://ffmpeg.org/legal.html
[R01]: https://pub.dev/packages/flutter_rust_bridge/versions/2.13.0
[R02]: https://github.com/fzyzcjy/flutter_rust_bridge/blob/8631db91a90c699439c9ce2a1fb4164ae8661da9/website/docs/guides/types/translatable/zero-copy.md
[R03]: https://github.com/fzyzcjy/flutter_rust_bridge/blob/8631db91a90c699439c9ce2a1fb4164ae8661da9/frb_codegen/assets/integration_template/cargokit/app/rust_builder/android/build.gradle
[R04]: https://github.com/fzyzcjy/flutter_rust_bridge/blob/8631db91a90c699439c9ce2a1fb4164ae8661da9/frb_codegen/assets/integration_template/cargokit/app/rust_builder/ios/REPLACE_ME_RUST_CRATE_NAME.podspec
[A01]: https://developer.android.com/develop/ui/views/layout/support-multi-window-mode#multi-instance
[A02]: https://developer.android.com/reference/android/hardware/camera2/CameraManager#getConcurrentCameraIds()
[A03]: https://developer.android.com/reference/android/media/MediaCodecInfo.CodecCapabilities#getMaxSupportedInstances()
[A04]: https://developer.android.com/reference/android/media/MediaCodec#PARAMETER_KEY_REQUEST_SYNC_FRAME
[A05]: https://developer.android.com/reference/android/media/MediaCodec#queueInputBuffer(int,int,int,long,int)
[A06]: https://api.flutter.dev/flutter/widgets/Texture-class.html
[A07]: https://developer.android.com/media/platform/av-capture
[A08]: https://developer.android.com/media/platform/sharing-audio-input
[A09]: https://developer.android.com/media/optimize/audio-focus
[A10]: https://developer.android.com/reference/android/media/AudioManager#setCommunicationDevice(android.media.AudioDeviceInfo)
[A11]: https://docs.flutter.dev/reference/supported-platforms
