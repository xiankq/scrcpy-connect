# scrcpy 首帧、视频传输与连接稳定性核查

调查日期：2026-10-18。仅静态读取本仓库、官方 release API、官方当前开发者文档及固定 v5.0.1 源码；本轮未构建 JAR、未运行测试、未连接设备。**已证**表示本轮可直接核查的文件、摘要或源码行为；**推论**表示由实现导出的建议；**需验证**表示尚无本轮设备测量支持。既有设备结果见[先前首帧调查](scrcpy-first-frame-and-latency.md)，不视为本轮重测。

后续实施与实际设备测量另记于[视频性能记录](../implementation/video-performance.md)：保持现有JAR、主控探测对照、真实半包/背压红绿回归及动态图案E2E。下文的“本轮未运行”仅指本报告的资料核查步骤，不覆盖该后续实施。

## 结论与产物身份

后续2026-10-18传输批次仍未改变或重建JAR。下表是初次调查快照；暂停修复后的
当前捕获JAR SHA-256为`b46cd074600c33802dc764df8a9e056271725cb9b51daf4a3494dfffadbbac89`，
官方JAR仍为`764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`。
仅服务端源码／补丁／版本／构建工具链变化或显式可复现核验才需要重建，
Flutter或Rust的传输／播放器改动不会自行改变已嵌入的JAR字节。

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

## AOSP Surface 时间轴、输入槽与无重建观测（2026-10-18）

**已证源码事实，非所有厂商API保证：**Android16 `System.nanoTime()`调用
`clock_gettime(CLOCK_MONOTONIC)`；SurfaceFlinger虚拟屏HWC输出用默认`systemTime()`
重新盖时间戳，GPU路径则经默认AUTO的Surface queueBuffer取CLOCK_MONOTONIC。
两条标准实现都没有任意固定半秒偏移或首帧归零。
[libcore System.c](https://android.googlesource.com/platform/libcore/+/fff4fcc0cf7f080cf2511cbb57561482b13b218f/ojluni/src/main/native/System.c#254)、
[Timers.h](https://android.googlesource.com/platform/system/core/+/68be0c2c0006a0740d0b1809abe4717308f90d15/libutils/include/utils/Timers.h#75)、
[VirtualDisplaySurface](https://android.googlesource.com/platform/frameworks/native/+/2827a4a16b0340ecd07c2d5a6c89991799b362bb/services/surfaceflinger/DisplayHardware/VirtualDisplaySurface.cpp#258)、
[RenderSurface](https://android.googlesource.com/platform/frameworks/native/+/2827a4a16b0340ecd07c2d5a6c89991799b362bb/services/surfaceflinger/CompositionEngine/src/RenderSurface.cpp#201)、
[Surface AUTO处理](https://android.googlesource.com/platform/frameworks/native/+/2827a4a16b0340ecd07c2d5a6c89991799b362bb/libs/gui/Surface.cpp#1066)。

**已证：**GBS默认输入时间偏移为0、未开启timelapse或skipFramesBefore变换；普通路径
把bufferTimeNs除1000送入codec。C2NodeImpl即使调整内部timestamp gap也将原始时间
存到customOrdinal，输入为Surface时CCodecBufferChannel输出强制恢复它。
因此该标准路径的媒体PTS与nanoTime同原点；但PTS是虚拟屏buffer的时间，不是应用
drawEnd、GPU fence完成或编码计算开始。重复帧PTS可从上一真实帧递增生成，亦不等于
新像素年龄。实测AVD二进制尚未与这些源码逐字核对，OEM实现也不能据此一概保证；
现有报告仍保留额外PTS假设，优先用已匹配新计数的drawEnd区间。
[GBS时间处理](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/module/bqhelper/GraphicBufferSource.cpp#807)、
[C2保留原时间](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2NodeImpl.cpp#328)、
[输出恢复时间](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodecBufferChannel.cpp#2667)。

**已证结构、占用待测：**C2NodeImpl给Surface输入适配器默认16个slot；较大分辨率才会
查询input/pipeline delay并改为4+delay。它不是“攒满16帧才能输出”或输出buffer数量。
GBS以该数注册输入ID和最大acquired数；C2NodeImpl可能先逐个等待GPU fence，再提交
组件。故源PTS已老且socket写很快，仍不能唯一归因编码计算。没有查到应用可通用设置
的Surface输入队列深度／只留最新帧开关；`KEY_NUM_SLOTS`由codec设置，应用值被忽略，
`allow-frame-drop`用于解码输出，`max-fps-to-encoder`也不保证清空已有在途旧帧。
[C2默认槽及fence等待](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2NodeImpl.cpp#118)、
[输入注册](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodec.cpp#553)、
[KEY_NUM_SLOTS实现契约](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/media/java/android/media/MediaFormat.java#1787)。

**观测方法：**pinned Streamer先write12字节帧头再写body，全部写完后才release codec输出。
在本批独立实验中只跟踪自己启动的`video` TID，`strace -ttt -T -xx -s 12 -e trace=write,writev`
可把头中PTS与实际接收媒体包匹配，无需JAR埋点；syscall耗时可直接验证长写阻塞，
guest wall clock与主控monotonic仍不能直接相减。classic adbd发WRTE后停读服务socket，
等OKAY再恢复，故ACK往返也可反向影响编码输出，不可只看payload复制耗时。
[固定Streamer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java#L77)、
[AOSP classic socket读停启](https://android.googlesource.com/platform/packages/modules/adb/+/ce023afef190b0cea7f8939e9dd5ee3ee79b137b/sockets.cpp#176)。

**后续首帧候选，未优化验收：**当前暂停补丁先创建一个codec取能力后释放，再创建实际
捕获实例。应独立验证能否在不破坏初始暂停、资源释放及错误重试的前提下移除重复创建，
不能未经实测就重建JAR或宣称可节省多少首帧时间。该开销不解释持续运行中每次输入的等待。

## 软件AVC可调参数边界（2026-10-18）

本轮独立只读一手核查固定Android16 frameworks/av
`4b2111885ff934799e70eddae2527a9848c3be29`、frameworks/base
`99b01a65cc4c104933788b3143285ab6bae65827`、libavc
`82092580f1dafe88defd88f873016b585bbd9e52`。实际AVD枚举只有
`c2.android.avc.encoder`和其OMX别名，原件`/tmp/connect-capture-encoders.txt`；
Perfetto实际回调名进一步确认本次使用c2.android.avc.encoder。
没有把系统二进制与对应AOSP构建逐字节等同。

**已证源码：complexity不是这个组件的快速档入口。**C2SoftAvcEnc及其BaseParams
没有complexity参数；软件AVC XML不含complexity limit，Java能力默认range=[0,0]。
组件固定mEncSpeed=IVE_NORMAL，并传入libavc的u4_enc_speed_preset。原生libavc虽有
FAST／HIGH_SPEED／FASTEST，但没有经该组件的MediaFormat complexity暴露，数值方向
也不等同SDK的“较低复杂度通常较快”。不能加入`complexity=0`后宣称ultrafast，
重建scrcpy JAR也不能修改设备系统编码器实现。
[C2参数](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/avc/C2SoftAvcEnc.cpp#80)、
[默认IVE_NORMAL](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/avc/C2SoftAvcEnc.h#50)、
[预设传入](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/avc/C2SoftAvcEnc.cpp#760)、
[Java默认范围](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/media/java/android/media/MediaCodecInfo.java#4075)、
[软件AVC XML](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/libstagefright/data/media_codecs_sw.xml#329)、
[libavc快速档](https://android.googlesource.com/platform/external/libavc/+/82092580f1dafe88defd88f873016b585bbd9e52/encoder/ih264e_utils.c#1176)。

**通用mapper不等于组件支持：**operating-rate是资源规划提示、priority=0是realtime
意图，latency是可选的输入帧数要求，均不是通用Surface队列深度控制。CCodec有这些
映射，但该软件AVC组件没有消费对应参数；工作looper本来已用ANDROID_PRIORITY_VIDEO。
scrcpy已有priority=0／latency=1，重复添加不增加已证机制。KEY_LOW_LATENCY仅用于
解码，KEY_NUM_SLOTS应用设置被忽略。
[SDK契约](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/media/java/android/media/MediaFormat.java#1143)、
[CCodec mapper](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodecConfig.cpp#613)、
[SimpleC2优先级](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/base/SimpleC2Component.cpp#1055)。

`max-fps-to-encoder`确实在GBS交组件前调用FrameDropper，按相邻媒体时间间隔丢帧，
有2ms jitter容差；它不检查当前帧墙钟年龄，不撤回已经提交的旧帧。降低输入上限是
实际减载策略，但不等于维持60fps或自动清空队列。该软件AVC默认B帧0；其CBR映射
IVE_RC_CBR_NON_LOW_DELAY，不能把“改CBR”直接叫开启libavc低延迟。
[FrameDropper](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/module/bqhelper/FrameDropper.cpp#36)、
[GBS丢帧](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/module/bqhelper/GraphicBufferSource.cpp#719)、
[CBR映射](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/avc/C2SoftAvcEnc.cpp#1351)。

实际目标侧Perfetto／同PTS结果见[后续实施记录](../implementation/video-performance.md)。
源码不证明所有OEM行为；本轮不为这些未支持旋钮修改默认编码选项或重建JAR。

## MDK snapshot官方修复与替代接口核查（2026-10-18）

官方fvp最新发布仍0.39.1、MDK为0.39.0。MDK 0.39.0的snapshot条目涉及JPEG编码失败，
没有指出renderer请求队列空完成回调；fvp相关变化主要涉及dispose／callback清理。
没有查到比当前版本更新且明确修复本次`std::function`空回调的已发布版本，
不能把升级当作已有修复。[fvp变更](https://github.com/wang-bin/fvp/blob/master/CHANGELOG.md)、
[MDK 0.39.0](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.39.0)。

仍open的[MDK #117](https://github.com/wang-bin/mdk-sdk/issues/117)报告高频snapshot崩溃，
未给出明确根因或修复版本；已关闭的[fvp #146](https://github.com/wang-bin/fvp/issues/146)
虽然同样bad_function_call，但栈为onStateChanged、2024年关闭，不能认定与本次同因。
MDK releases/latest网页缓存曾误指0.38.0，本轮以releases.atom及0.39.0独立发布页交叉核对。

官方候选是现有`Player.onFrame<VideoFrame>()`获取进入renderer之前的解码帧，
再用`VideoFrame.to()`转换为可读主机内存帧，通过bufferData／bytesPerLine读取。
它可绕开renderer snapshot请求接口，无需全局软件解码；但Android当前硬解后端转换
是否可行、安全及开销均未实测，不能因此删除原生崩溃项或降级像素验收。
[onFrame文档](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#templateclass-frame-player-onframestdfunctionintframe-inttrack-cb)、
[VideoFrame.to契约](https://github.com/wang-bin/libmdk-capi/blob/main/include/mdk/cpp/VideoFrame.h#L222-L233)。

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


## MDK帧转换读回的可行边界（2026-10-18）

独立只读核对fvp0.39.1随包MDK0.39.0固定头（本地
`android/mdk-sdk/include/mdk/{VideoFrame,Player,c/VideoFrame,c/Player}.h`），
与[官方Player回调说明](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#templateclass-frame-player-onframestdfunctionintframe-inttrack-cb)及
[官方AMediaCodec说明](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)。
Context7精确查询无匹配，未由其缺失结果推断能力。

- C `VideoFrameAPI.to`在c/VideoFrame.h:115；C++ VideoFrame.h:223–234说明成功
  总在host内存、失败invalid、不支持压缩输入输出，相同格式尺寸可能返回当前帧。
  C++封装将返回值构造成拥有对象（:126、333–334），析构:128–130使用
  `mdkVideoFrameAPI_delete(&p)`，候选严格照此回收转换句柄；原输入借用不回收。
- C没有clone；ref/unref/delete导出:142起。ref为引用计数句柄，不能推出像素深拷贝
  或GPU线程安全。onDestroy只有c/VideoFrame.h:118无注释声明，不能拿来当deleter。
- Player.h:1059–1080的onFrame specialization attach借用输入、同步filter、detach
  写回。c/Player.h:301说明onVideo位于renderer前。可在同步作用域尝试单次转换、
  复制有界像素并保留原frame指针/return0；不得停止/销毁播放器或把借用指针传worker。
- C RGBA枚举为9、C++为10；官方C++封装明确减1。必须核对格式、尺寸、plane、
  data、stride；EOS帧可能句柄有效但无数据（VideoFrame.h:133）。
- AMediaCodec默认surface=1，copy=1在Surface模式忽略，surface=0才是ByteBuffer
  host输出。Player.h:698仍标记非host frame TODO；没有找到Surface→to支持承诺。
  候选失败不能自动换surface=0或全局软解。Apple/Windows输出路径也须独立验证。
- onVideo位于renderer前，即使转换成功也仅证明解码帧像素可读，不能当作呈现完成。
  转换会阻塞当次回调，时钟开销和Flutter合成画面必须另验；没有公开承诺其不影响
  原Surface资源。回调线程/跨track串行/注销drain也无保证，需保留token/Arc撤销。

这些事实支持一个默认关闭的临时候选实验，不等于MDK renderer快照崩溃已修复。

## VP8实时编码与公开码控参数（2026-10-18）

固定frameworks/av `4b2111885ff934799e70eddae2527a9848c3be29`：C2SoftVpxEnc每次
编码使用`VPX_DL_REALTIME`，设置`g_lag_in_frames=0`和`g_threads=0`，但没有公开
deadline/lag/threads/complexity调节入口。`g_threads=0`在libvpx契约中等价于1线程，
不是自动使用全部核心。[组件配置](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/vpx/C2SoftVpxEnc.cpp#574)、
[实时调用](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/vpx/C2SoftVpxEnc.cpp#1041)、
[线程契约](https://android.googlesource.com/platform/external/libvpx/+/718dd469f67964d8f5fd4c8ebf09513bbfa50146/vpx/vpx_encoder.h#288)。

默认VBR；公开`bitrate-mode=2`经CCodec映射到CBR时，组件还设置
`VP8E_SET_CPUUSED=-8`。固定Android16 libvpx `718dd469f67964d8f5fd4c8ebf09513bbfa50146`
的x86_64配置为realtime-only；负值在此路径固定Speed=8，默认正值cpu_used=4则走
自动选择。CBR同时影响码率控制等行为，不能把A/B结果全归因于speed数字。
[CBR分支](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/components/vpx/C2SoftVpxEnc.cpp#703)、
[公开映射](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodecConfig.cpp#389)、
[x86配置](https://android.googlesource.com/platform/external/libvpx/+/718dd469f67964d8f5fd4c8ebf09513bbfa50146/config/x86_64/vpx_config.h#79)、
[默认值](https://android.googlesource.com/platform/external/libvpx/+/718dd469f67964d8f5fd4c8ebf09513bbfa50146/vp8/vp8_cx_iface.c#55)、
[速度选择](https://android.googlesource.com/platform/external/libvpx/+/718dd469f67964d8f5fd4c8ebf09513bbfa50146/vp8/encoder/encodeframe.c#685)。

scrcpy v5.0.1在默认MediaFormat字段后应用codec options，所以上述参数不需要改JAR。
显式encoder使用`createByCodecName()`并检查MIME；默认选择不承诺硬件。
[固定scrcpy实现](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L280)。

VP8接口没有global headers；不能等待H264式CONFIG或添加SPS/PPS/AnnexB前缀。
当前项目以session尺寸和VP8关键帧构造Matroska轨道，CodecPrivate为空；实际
AMediaCodec解码和新像素证据见[性能记录](../implementation/video-performance.md)。
[空global-header接口](https://android.googlesource.com/platform/external/libvpx/+/718dd469f67964d8f5fd4c8ebf09513bbfa50146/vp8/vp8_cx_iface.c#1415)、
[官方demux仅合并AVC/HEVC配置](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c#L277)。

这只支持控制变量的候选实验，不保证当前系统二进制逐字对应固定AOSP源码，也不证明
VP8在其他设备更快。相同8Mbps不等于相同画质；最终选择还需文本/照片/运动质量、
带宽和功耗验证。不能仅凭软件编码模拟器结果改变所有设备的默认策略。
