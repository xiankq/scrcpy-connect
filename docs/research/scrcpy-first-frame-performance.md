# scrcpy 首帧、视频传输与连接稳定性核查

调查日期：2026-10-18。仅静态读取本仓库、官方 release API、官方当前开发者文档及固定 v5.0.1 源码；本轮未构建 JAR、未运行测试、未连接设备。**已证**表示本轮可直接核查的文件、摘要或源码行为；**推论**表示由实现导出的建议；**需验证**表示尚无本轮设备测量支持。既有设备结果见[先前首帧调查](scrcpy-first-frame-and-latency.md)，不视为本轮重测。

后续实施与实际设备测量另记于[视频性能记录](../implementation/video-performance.md)：保持现有JAR、主控探测对照、真实半包/背压红绿回归及动态图案E2E。下文的“本轮未运行”仅指本报告的资料核查步骤，不覆盖该后续实施。

## 结论与产物身份

**推论：本轮视频传输、首帧与连接稳定性没有证据要求新增 Java 补丁或重新构建 JAR。** 首先改进主控设备的计时、播放器请求/确认顺序、数据消费与背压处理；保持现有服务端协议与暂停扩展。这个结论不意味着可以把当前视频会话换成未修改官方 JAR：当前主控已经依赖暂停扩展 type 128，直接替换会破坏协议。[本地实现](../../crates/interop_core/src/scrcpy.rs)、[已有补丁说明](../../servers/scrcpy/README.md)

| 对象 | 本轮核验 | 结论 |
| --- | --- | --- |
| 官方 release | `v5.0.1`，发布时间 `2026-10-08T06:44:27Z`；annotated tag 对象 `a0c27ff382c411af1301dcc1cd8205c9aeb81996` 解引用到 `a60891aea193d92e7e5c3942700eca63f9d19a5f` | **已证**；不能把 tag 对象当源码 commit。[Release API][R01]、[tag 对象][R02] |
| `servers/vendor/scrcpy-server-v5.0.1` | 本地 SHA-256 `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`；官方 asset API 报同一 digest、大小 733930 bytes | **已证**：该 vendor 文件与官方发布物摘要一致。[R01] |
| `servers/scrcpy/interop-scrcpy-server.jar` | 本地 SHA-256 `91606a603a49bbea2be37ec500cde44a588483ac3162bc466d23b2f9d840deab`，与本仓库 manifest 一致 | **已证**：这是本仓库 cooperative pause 补丁产物，不能称其为未修改官方 JAR。[manifest](../../servers/scrcpy/manifest.json) |
| 补丁文件 | `0001-cooperative-capture-pause.patch` 本地 SHA-256 `bb78d60dfac9ceb43784681563b48af1745a7e6b26a80bffeaa87fb57bf23381`，与 manifest 一致 | **已证**：本轮只核验追踪文件一致性，没有重建验证源码到二进制的对应关系。[补丁](../../servers/scrcpy/patches/0001-cooperative-capture-pause.patch) |
| 当前视频路径 | `start_session_with_settings()` 校验并推送 `CAPTURE_SERVER`；启动参数协议版本仍为 `5.0.1` | **已证**：视频使用上述补丁 JAR；枚举与设备音源保留官方 `SERVER` 路径。[scrcpy.rs](../../crates/interop_core/src/scrcpy.rs)、[audio.rs](../../crates/interop_core/src/audio.rs) |

**已证：**本轮 GitHub API 的 `master` 也指向上述源码 commit。然而当前 `doc/develop.md` 仍自称描述协议 4.0，示例也使用 server 4.0，部分链接固定到更旧 commit。因此开发者文档用于解释设计，字节协议和实现以 v5.0.1 源码为准，不能复制其版本示例。[当前 master API][R03]、[当前 develop.md][R04]

## 首帧与低延迟已有机制

- **已证：**官方开发者文档把静止画面起始不出帧、快速运动后的最后画面质量差列为 `KEY_REPEAT_PREVIOUS_FRAME_AFTER` 要解决的问题；v5.0.1 已设置 **100000µs（100ms）**，API23+ `KEY_PRIORITY=0`，API26+ `KEY_LATENCY=1`。100ms 是重复上一帧配置，不是端到端首帧时限，也不保证任何编码器严格兑现该延迟。[R04]、[SurfaceEncoder][R05]
- **已证：**v5.0.1 的自定义 codec options 在上述默认项之后写入，因此可以覆盖默认项；本项目当前视频启动命令没有传 `video_codec_options`，已有暂停补丁也没有改这些默认值。重复添加这些字段不能解释本项目当前问题。[R05]、[本地启动命令与补丁](../../servers/scrcpy/README.md)
- **已证：**官方视频说明默认没有额外视频延迟缓冲；H264 被描述为应有更低延迟。官方 decoder 设置 `AV_CODEC_FLAG_LOW_DELAY`，没有在该初始化路径强制 `threads=1`。[video.md][R06]、[decoder.c][R07]
- **推论：**保留已经可用的编码器，优先测量主控播放器实际后端、探测、状态等待与呈现耗时。H264 适合作为性能基线，但不能用文档代替五种编码、硬件/软件后端和具体设备的测量。不能把 server `latency=1` 或 decoder 名称当成端到端低延迟证明。[R05]、[R06]、[R07]

## 帧协议、reset 与连接顺序

**已证：**v5.0.1 demuxer 先读 codec ID、视频 session 尺寸，再处理 session/media 包；媒体头为 12 bytes，CONFIG 不带普通媒体 PTS，H264/H265 CONFIG 合并到后续非 CONFIG 包。后续 session 可能改变尺寸。decoder 会在 AV1 硬件解码的新 session 重建 context。容器主控路径可以把参数放入 CodecPrivate，但必须保留配置、关键帧及新代顺序，不能机械复制 AnnexB 拼包或把 CONFIG 时间当作媒体 origin。[demuxer.c][R08]、[decoder.c][R07]；容器映射是**推论**。

**已证：**官方控制消息 `RESET_VIDEO=17` 调用 capture reset；`CaptureControl` 通过 `signalEndOfInputStream()` 打断编码，编码循环随后清理并启动新 session。这是编码会话重置，不是“立刻输出像素”的确认。[ControlMessage][R09]、[Controller][R10]、[CaptureControl][R11]、[SurfaceEncoder][R05]

**推论：**用官方 reset 恢复现有会话时，主控仍应等待新 session/config 与真实解码帧；不要把控制写入完成、resume ACK 或旧 snapshot 当新一代呈现成功。reset 本身不要求新 JAR；当前 type 128 暂停扩展仍须保留。

**已证：**启用的 socket 固定依 video → audio → control 顺序建立，关闭的通道跳过。forward 模式第一条通道发送 dummy byte；`Server` 在 `DesktopConnection.open()` 完成后才发设备 metadata。所以 video+control 模式若先等待视频 metadata、再连 control，会形成等待环。本项目已经先连 video 和 control，再读 dummy/name/codec；应保留这个顺序。[DesktopConnection][R12]、[Server][R13]、[本地顺序](../../crates/interop_core/src/scrcpy.rs)

**已证：**本地应用窗口启动在 control actor 创建后发送 `START_APP`，随后才等待编码关键帧，避免无系统装饰的空白虚拟显示等待应用绘制、应用启动又等待首帧的循环。`read_video_preface()` 的有界关键帧等待与 `encodedKeyFrameReady` 仅证明编码数据可用；播放器真实像素仍是另一阶段。[本地启动与首包读取](../../crates/interop_core/src/scrcpy.rs)

## 背压与可丢弃边界

**已证：**SurfaceEncoder 同步写出编码输出后，才在 finally 中释放 codec output buffer；Streamer 使用 `IO.writeFully()`。官方 decoder 把编码包加入可增长 vecdeque，由独立线程解码；这不是严格限定包数/时长的队列。默认不加显示延迟也不等于所有阶段零缓冲。[R05]、[Streamer][R14]、[R07]

**已证：**官方显示端 frame buffer 保存一个待消费的解码帧，新帧替换旧帧；screen 统计该跳帧，并让原有 UI 事件消费最新帧。这是**解码后**的替换策略。[frame_buffer.c][R15]、[screen.c][R16]

**推论：**主控消费变慢可能沿 TCP/ADB 写入传回被控编码线程，并妨碍 EOS/reset/暂停到达清理边界。应持续读取/处理通道，限定主控内存与排队时长，及时呈现最新解码帧。不要逐包任意丢弃压缩数据；预测帧可能依赖已丢弃参考帧。若要放弃旧压缩代，应在可验证的 session/config/关键帧边界重新同步，并验证五种编码。

**已证：**本项目 `run_video()` 已在输出 I/O 前释放 session state 锁，并在 paused/awaitingSession 时读取后丢弃视频包；但正常播放的 `output.write_all()` 仍可能等待消费者。这是主控背压观察点，不是本轮已实测的故障归因。[run_video](../../crates/interop_core/src/scrcpy.rs)

## 本轮建议与验证边界

| 优先级 | 行动 | 证据状态 |
| --- | --- | --- |
| 1 | 保留两种现有 JAR 及各自职责；不新增首帧/低延迟 Java 补丁，不重建现有 JAR | **推论**：机制已在官方默认值中，当前还有必须兼容的暂停扩展 |
| 2 | 分别记录 ADB 连接/推送/进程、socket、codec+session、CONFIG+关键帧、本地媒体打开、prepare、实际播放确认、实际首像素时刻 | **推论**：分离编码可用与解码可见，才能确认优化收益 |
| 3 | 维持通道顺序与应用启动顺序；播放器请求后再有界等待确认；取消后拒绝迟到结果 | **推论**：避免等待环与把旧代确认用于新代 |
| 4 | 记录每段读取/写入停顿、队列长度/字节/年龄及播放器后端；在主控持续 drain 与资源上限之间明确恢复策略 | **推论**：背压问题应先在消费者侧定位 |
| 5 | 静止屏幕冷启动、五种编码、旋转、新窗口启动、慢消费者、暂停恢复、连接中断取消分别实测；比较首帧分位数与稳定态延迟 | **需验证**：本轮未运行；原记录中的模拟器结果不代表真机或所有平台 |

**需验证：**只有在日志与对照实验确认：按协议建立连接且主控持续消费、正确处理新代配置并请求播放后，特定被控编码器仍未产生可用首帧，或现有暂停补丁出现可复现服务端缺陷，才有依据另行提出服务端源码修改与重建。该判断必须指向具体设备/编码器和失败阶段；目前没有这样的新增证据。

[R01]: https://api.github.com/repos/Genymobile/scrcpy/releases/tags/v5.0.1
[R02]: https://api.github.com/repos/Genymobile/scrcpy/git/tags/a0c27ff382c411af1301dcc1cd8205c9aeb81996
[R03]: https://api.github.com/repos/Genymobile/scrcpy/commits/master
[R04]: https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md
[R05]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java
[R06]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/doc/video.md
[R07]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/app/src/decoder.c
[R08]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/app/src/demuxer.c
[R09]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/control/ControlMessage.java
[R10]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/control/Controller.java
[R11]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/CaptureControl.java
[R12]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/DesktopConnection.java
[R13]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/Server.java
[R14]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java
[R15]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/app/src/frame_buffer.c
[R16]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/app/src/screen.c
