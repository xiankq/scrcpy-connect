# scrcpy 首帧、视频传输与连接稳定性核查

调查日期：2026-10-18。仅静态读取本仓库、官方 release API、官方当前开发者文档及固定 v5.0.1 源码；本轮未构建 JAR、未运行测试、未连接设备。**已证**表示本轮可直接核查的文件、摘要或源码行为；**推论**表示由实现导出的建议；**需验证**表示尚无本轮设备测量支持。既有设备结果见[先前首帧调查](scrcpy-first-frame-and-latency.md)，不视为本轮重测。

后续实施与实际设备测量另记于[视频性能记录](../implementation/video-performance.md)：保持现有JAR、主控探测对照、真实半包/背压红绿回归及动态图案E2E。下文的“本轮未运行”仅指本报告的资料核查步骤，不覆盖该后续实施。

## 结论与产物身份

后续2026-10-18传输批次仍未改变或重建JAR。下表是初次调查快照；暂停修复后的
当前捕获JAR SHA-256为`b46cd074600c33802dc764df8a9e056271725cb9b51daf4a3494dfffadbbac89`，
官方JAR仍为`764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`。
仅服务端源码／补丁／版本／构建工具链变化或显式可复现核验才需要重建，
Flutter或Rust的传输／播放器改动不会自行改变已嵌入的JAR字节。

后续首次分配调查确实修改了被控服务源码，因此另建`initial-codec`隔离产物
23dc3f84…，验证MediaCodec探测与首捕获复用。它不叠加bounded-input，不覆盖生产：
源端15次确认分配2→1，完整Flutter A/B/A没有稳定首帧收益，故生产仍b46cd074…。
详见[候选及复现](../../servers/scrcpy/experiments/initial-codec/README.md)与
[实际验收](../implementation/video-performance.md#首次编码器分配复用源端减少一次完整首帧未通过)。

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

## snapshot交付、关闭与失败结果边界（2026-10-18）

MDK0.39.0本地锁定SDK `include/mdk/Player.h:403–416`允许snapshot失败时回调
request为空，完成回调运行在独立线程。调用只调度renderer重绘；不可见surface可能
不重绘。因此调用者超时/撤销诊断token不是MDK请求取消或worker排空证据。
[官方snapshot调度说明](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-snapshotsnapshotrequest-request-snapshotcallback-cb-void-vo_opaque--nullptr)。

当前本地fvp0.39.1 `lib/src/callbacks.cpp:693–694`及官方v0.39.1相同方法均在构造
typed-data前无条件解引用`ret->stride/height/data`；该方法也没有使用其它状态回调
的CallbackGuard。MDK失败契约与此存在明确缺口，但本批没有触发null故障或修补
依赖；它与历史renderer内部空std::function不是同一栈，不能混为已证根因。
[固定版本MdkSnapshot](https://github.com/wang-bin/fvp/blob/v0.39.1/lib/src/callbacks.cpp#L637-L688)。

本批主控修复串行snapshot/播放状态、关闭后排队拒绝与在途请求退役；诊断超时保留
native槽位，并以成功native提交后的hook刷新静止源。结果交付仍不能证明MDK内部
worker已完成回调后收尾。完整红绿及静态/动态/恢复证据见
[生命周期记录](../implementation/video-performance.md#截图生命周期与暂停提交顺序2026-10-18)。
后续需单独构造null失败回调验证，并通过可复现的依赖补丁/替代实现处理，不能只改
本机pub缓存或把这些有限次数无崩溃写成整个播放器稳定性完成。


## fvp空结果故障与可复现交付（2026-10-18）

**已证：**核验pub.dev fvp0.39.1归档SHA-256为
`2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`，
其callbacks.cpp与本地锁定包一致（`d31142…623e`），不能用GitHub tag源码行数
代替pub发布包身份。将真实MdkSnapshot函数体、真实callbacks.h枚举与Dart_CObject
头放入最小宿主探针，仅在MDK callback边界注入契约允许的null，原版exit-11。
这是空指针解引用的确定性源边界复现，非历史renderer空std::function实机复现。
[官方pub归档](https://pub.dev/api/archives/fvp-0.39.1.tar.gz)。

**已实施：**仓库内third_party/fvp保留上游许可证／Dart API／全部平台源码，
省略示例和SDK／生成／构建数据。根path override使应用与Bridge共同使用该版本，
lockfile正常记录path，不以原hosted摘要冒充修补源码身份。五份原生副本统一在
ret为null时发送空Uint8List；既有player.dart把空数据转换为null完成Future。
仅提前return会留下永久pending请求，因此不采用。回归同时检查有效带stride缓冲
及未知handle，并通过真实Dart VM NativeApi.postCObject／ReceivePort确认空和
填充typed data可交付。见[来源与补丁](../../third_party/fvp/CONNECT_PATCHES.md)、
[可执行回归](../../tool/fvp_snapshot_regression.py)。

**边界：**该修补没有改变MDK renderer二进制，也没有证明结果交付时worker已排空；
历史空回调崩溃继续开放。Android真实设备链路结果另记[视频性能](../implementation/video-performance.md)。
原生SDK的nightly默认下载／CocoaPods版本范围与四平台整包构建仍需独立闭合，
不因fork源码进入仓库就宣称A41或四端验收通过。scrcpy两个JAR均未修改或重建。


## 暂停补丁的正常首启重复分配候选（2026-10-18）

**已证（源码／现有中间产物）：**固定5.0.1正常Server.start进入SurfaceEncoder的
streamCapture：先createMediaCodec读取capabilities，补丁随后无条件release并置null，
初始CaptureControl.paused=false时门立即放行，再次create后configure／创建Surface／
capture.start／codec.start。即使ignoreVideoEncoderConstraints=true也仍走两次创建。
[已追踪补丁](../../servers/scrcpy/patches/0001-cooperative-capture-pause.patch)、
[上游固定实现](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)。
只读javap对已有.build/classes也看到create／release／置null／await门／再create的
对应顺序，但并非此次重建或反编译当前DEX的新证明。现有CapturePauseTest覆盖门
与真实encode循环，未运行streamCapture，不能锁定或量化双分配。

**需验证：**保留同一JAR，先在真实冷启动以CCodec／MediaCodec日志或Perfetto核对
两次分配释放及跨度；当前log_level=warn不会输出两次Using video encoder，缺少
该行不能否定源码路径。原目标AVD随后宿主OOM退出，未获得新的系统codec切片，
不填造耗时或收益。若量化证实值得消除冗余，需要调整服务端暂停门所有权与测试，
届时才按正常流程重建补丁JAR；不能保留暂停时编码器分配来换首帧数字。

两次分配都发生在首关键帧之前，不能解释本批关键帧后输出722ms或稳态源年龄。
Android运行时request-sync／drop-input-frames属于MediaCodec.setParameters，当前
scrcpy没有对应公开控制，不能伪装为启动MediaFormat option；编码器flush行为
未定义，不用于清积压。[官方MediaCodec](https://developer.android.com/reference/android/media/MediaCodec#States)。
现有priority／latency／repeat配置与先前失败调参结论保持不变，不重复盲调。


## 同JAR双分配实测与首帧SDK选项（2026-10-18）

目标AVD新生命周期、既有捕获JAR、按具体捕获PID过滤CCodec／MediaCodec系统日志，
三次均实际看到两次c2.android.avc.encoder创建：

| raw诊断 | 第一次allocate→Created ms | 第二次 ms | 两次Created间隔 ms |
| --- | --- | --- | --- |
| 2def2d8cc62c | 78 | 7 | 39 |
| 12c75b20f31a | 3 | 1 | 34 |
| 19ab34757fa4 | 11 | 5 | 33 |

间隔包含能力查询、capture.init及释放，不是纯冗余成本，也不是收益上界；首次78ms
不能当成保留同一codec就能全部节省的耗时。第一临时脚本误等静态流后续媒体包而超时，
仅用其系统分配日志，不计成功首帧测量。修正为收到首个完整媒体包即结束，后两次完成；
无解码／实际像素验收，不能与正式E2E首帧直接比较。三次后续明确复核进程、fixture和
JAR均无残留；第二次即时cleanup的captureAbsent=false保留原值，另存稍后复核true。
原始目录`/tmp/connect-codec-allocation-<表中ID>/`含codec.log、result.json及复核文件。

当前证据不足以为此改变暂停所有权／重建JAR。若以后优化，须保证初始未暂停时复用
探测codec，而进入任何暂停ACK门前先在编码线程释放；保留codec后capture.init异常
也必须纳入finally。仅移除首次release会让初始暂停ACK时仍占codec，违反现有契约。
该候选不能解释关键帧之后数百毫秒等待，先处理后者。

MDK公开`prepare(0)`回调表示媒体信息就绪，不能当首帧已显示；`onFrame/onVideo`
先于renderer接收，snapshot另经渲染／读回。`setBufferRange`的max不是固定延迟保证。
[Player APIs](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。
全局`videoout.buffer_frames`限制renderer缓存帧数，正整数；`profiler.gpu`控制GPU
时间采样。锁定fvp Android JNI_OnLoad主动设为1，因此实验在其初始化后请求0；
未读回SDK内部值，只报告请求。两项都影响进程内其他播放器，不能作为每个会话的
随意开关。[Global Options](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options)、
[锁定源码](../../third_party/fvp/android/fvp_plugin.cpp)。
实际五组对照没有满足原严格性能预算，两个实验均不进入产品默认；首个32×32验证
截图指标与时钟读取括界已保留，详见[实际结果](../implementation/video-performance.md#首个验证画面的观测与隔离对照2026-10-18)。

## drop-input-frames不等于保留最新帧（2026-10-18）

固定Android16框架av提交`4b2111885ff934799e70eddae2527a9848c3be29`只读核查：
公开`PARAMETER_KEY_SUSPEND`接受1／0暂停及恢复Surface输入，但API允许参数静默失败。
[API契约](https://developer.android.com/reference/android/media/MediaCodec#PARAMETER_KEY_SUSPEND)。
GBS成功路径中，MediaCodec.setParameters同步等待消息，CCodec调用Surface wrapper，
再同步进入GBS mutex处理；顺序1→0不会简单合并成最后一个0。
[MediaCodec setParameters](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/libstagefright/MediaCodec.cpp#7580)、
[CCodec分发](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodec.cpp#2648)。

但GBS::setSuspend(true)调用releaseAllAvailableBuffers_l，丢弃的是全部待输入buffer，
包括最新变化；清理不更新仅在正常送入路径更新的mLatestBuffer。若源在最终变化后
静止，恢复可能继续重复旧像素或无输出，PTS递增也不能证明像素更新；请求关键帧不能
保证重新取得已经丢掉的最终画面。CONFIG之后、首个实际关键帧之前pulse还可能丢掉
静态启动唯一输入。
[GBS清理与重复源](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/module/bqhelper/GraphicBufferSource.cpp#1234)。

已进入C2NodeImpl workList／fence／component queue的工作不会被清掉，编码器内部、
输出、socket及主控缓存也不受此开关清理。GBS acquire失败会退出清理循环仍返OK，
CCodec忽略wrapper配置错误，另一C2InputSurfaceWrapper::configure路径仍是TODO；
Java调用返回不能证明所有设备已清队列。
[C2Node工作](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2NodeImpl.cpp#115)、
[替代wrapper](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodec.cpp#205)。

因此不实施无条件逐输出pulse，不为该设想修改现有补丁或重建JAR。若后续确需诊断，
只能隔离候选JAR、记录摘要、先试一次成功交付且释放后的非CONFIG／非EOS输出；
同编码会话先有关键帧，参数顺序1→0，不加sleep／flush／time-offset。已有暂停／reset
则跳过，不持CaptureControl锁；恢复0失败须清理终止实验，不能吞异常继续或降级尺寸。
同步调用本身会增加暂停等待，必须重验ACK前资源释放与竞态。
硬门禁包括动态→唯一终值→完全静止、单次变化后静止、静态冷启、旋转、暂停恢复；
最终真实像素必须原样到达，不能靠事后refresh掩盖。之后才比较A/B/A新像素、CPU、
吞吐、首帧与失败数。此处是源码否定与实验边界，未声称已做pulse实机实验或性能改善。


## Flutter测试帧策略与产品呈现边界（2026-10-18）

已对照本机Flutter3.47.6完整framework提交
`5fc346839b5d0eef006ed8404392afb4dfae428d`的源码，非按旧引擎记忆推断。
IntegrationTest继承Live绑定且不覆盖帧策略，默认fadePointers在无pump等条件时跳过
框架帧；fullyLive及benchmarkLive放行。非pump的handleDrawFrame又在除benchmark外
无条件请求下一帧，所以直接启用fullyLive会持续框架绘制，benchmarkLive不能消除此
循环，还会改变pump语义。
[默认和帧处理](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/packages/flutter_test/lib/src/binding.dart#L2754)、
[IntegrationTest继承](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/packages/integration_test/lib/integration_test.dart#L45)。

反过来也不能把默认的空档当正常产品：当前SurfaceTexture回调markDirty后调用
scheduleEngineFrame，经Shell到默认Engine.ScheduleFrame(true)，请求重建layer tree；
旧外部纹理可复用场景路径仍在，但不能保证此处总绕过测试策略。
[SurfaceTexture回调](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/android/io/flutter/embedding/engine/renderer/FlutterRenderer.java#L352)、
[引擎调度](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/common/shell.cc#L1117)、
[默认参数](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/common/engine.h#L893)。

由此保留原门禁及其readback/阶段性呈现范围，回执增加binding和framePolicy；不把
本次fullyLive实验写成纯产品速度。真实普通main静态trace与临时测试trace已分别
采集，实际负载明显不同，但场景／时段不匹配，不报告优化百分比。需用正常
WidgetsFlutterBinding运行入口、连续实际Texture和真实计数器验证补齐性能验收。
[两类实测及原始证据](../implementation/video-performance.md#截图提交时间与测试帧调度边界2026-10-18)。

## 普通Driver调度与后续decoder定位（2026-10-18）

上述正常调度缺口现由独立`benchmark/live_video_performance.dart`补齐；实际绑定是
`_DriverBinding`，使用普通Scheduler／Renderer／Widgets混入及测试messenger，没有
Live draw/pump循环。它不是类名为WidgetsFlutterBinding的完整产品App；不将框架
内部仍import flutter_test误写成使用LiveTestWidgetsBinding。
[固定版本Driver绑定源码](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/packages/flutter_driver/lib/src/extension/extension.dart#L36)。
真实Rust／共享播放器、逐次新图案及host实际窗口PNG已跑通；在相同1280/60/8Mbps
下每路60次，原生严格失败、FFmpeg slice通过，具体预算、计时范围和清理见
[完整实测](../implementation/video-performance.md#普通调度基准与解码路径对照2026-10-18)。
这补了反馈循环，没有证明实体手机默认硬解性能，也没有替换产品默认解码器。

同PTS、同主控单调时钟显示relay开始write→onVideo中位原生134.373ms、软件1.414ms。
共享Matroska即时mux和HTTP写路径已有TCP_NODELAY、每包即write，固定攒包解释因此
更弱；但该段仍含socket消费、demux、decoder与图像获取，不能叫纯硬解等待。
使用write完成时刻可能出现微小负值，因为消费者可以在写Future完成前处理已收到
的包；选择writeStartedUs描述边界，不能删除负值后再比较。

2026-10-18再次核对官方Decoders与本机SDK Changelog：AMediaCodec的`async=1`已是
默认，codec异步与AImage的异步acquire不是同一个选项。既有async=0、image=1、
surface=0、low_latency=1、avioflags=direct等负面实验不重复。
仅保留两个有条件的后续候选：若先证实当前实际使用AImageReader、固定SDK识别选项
且基线尚未启用，再分别测`acquire=latest+async`或`reuse=1`；每次只改一项。
前一组合依据官方“值中包含async”的说明，尚未验证固定二进制接受该组合；配置
被传入不能算生效证据。后一项用于EGLImage复用，亦不承诺当前路径适用。
[AMediaCodec参数](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)、
[全局EGLImage选项](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options)。
若onVideo提前而等待移到snapshot／呈现，总延迟无改善便撤回；不只优化一个回调
数字。尚未确认这些前提，故本批没有为它们再改Fvp或加入生产默认。

scrcpy开发文档仍明确用重复前帧解决静态画面启动无帧，当前参数已经启用；本轮
主控诊断和解码对照没有改变服务端源码、补丁、版本或编译工具链，不需要重建JAR。
两个JAR摘要再次一致。只有这些输入变化或刻意做可复现构建核验时才重建，不把
Flutter播放参数修改附带变成服务端重编译。
[官方采集机制](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md#screen-video-encoding)。


## 实际AImageReader异步路径确认（2026-10-18）

普通Driver基准的原生默认路径已在专用主控AVD上附加LLDB，仅记录少量函数参数、
返回值及调用栈，不调用被测函数、不记录媒体内容。下列三条成功回执可按指针关联，
调用栈均包含libmdk.so：

| 边界 | 实际回执 |
| --- | --- |
| AImageReader_getWindow | reader=0x73b6cac64210，返回0，window=0x73b62ac2e9c0 |
| AMediaCodec_configure | codec=0x73b6cac64130，window与上项相同，flags=0，返回0 |
| AImageReader_acquireLatestImageAsync | reader与首项相同，返回0，image=0x73b55ac5bac0非空 |

这证明本次默认解码器输出连接到该AImageReader，且成功走异步latest acquire；
Flutter自己的SurfaceTexture日志不能单独证明或否定这条解码路径。
API的窗口及图像获取契约见[Android NDK AImageReader_getWindow](https://developer.android.com/ndk/reference/group/media#aimagereader_getwindow)、
[AImageReader_acquireLatestImageAsync](https://developer.android.com/ndk/reference/group/media#aimagereader_acquirelatestimageasync)。
这里是本次固定二进制的运行证据，不推断所有平台都走同一路径。

原始事件为`/tmp/connect-decoder-path-events.jsonl`，完整LLDB日志为
`/tmp/connect-decoder-path-lldb.log`。首次30秒窗口因host仍构建而没有事件，日志以
`.first-empty`后缀保留；第二次16.2秒取得上述关联回执后detach。脚本在入口断点中
注册返回回调时另有Python KeyError，原样保留，不把整次探针称为无错或完整调用
覆盖；上述三项有效返回与指针匹配经独立解析断言，足以确认实际路径。

调试器会暂停线程，第二次首帧1474ms、首次独立运行2304ms都不能用于延迟对照；
两次严格命令均失败，fixture与App清理均确认。原始回执分别在
`/tmp/connect-e2e/decoder-path-probe{,-r2}/result.json`。本轮没有基于它报告性能收益。

这关闭了上一节“若基线未启用，再试异步acquire”的前提：实际已经启用，不再盲试
`acquire=latest+async`。`reuse=1`也尚无基线生效证据，不直接加入默认。下一步需拆开
MediaCodec输入到输出、图像获取到onVideo两段，用有界追踪量测等待；函数断点只用
来辨路径，不能充当低开销逐帧计时。默认解码器、Fvp策略和两个scrcpy JAR均未改。
连接层另已补上[ADB应用失活恢复](../implementation/connection-health.md)，它关闭
健康socket下的无响应缺口，不代表平台延迟、实际无线切网或长稳已验收。


## Codec异步默认值必须以运行路径验证（2026-10-18）

AImageReader异步获取已经启用，仍不能说明codec本身使用async callback。新增同
系统时钟标记后，三轮30输入的组件queue→workDone中位3.600ms，但其后到onVideo
为147.174ms。相同线程持续同步dequeue、没有异步输出事件，促成显式async=1实验；
该参数有3条成功async日志及467条输出callback，后一段降至20.841ms，返回缺省又
升至133.510ms。输入P50/P95相应277/392→153/204→273/389ms，首帧仍失败。
[完整A/B/A与无诊断默认扩量](../implementation/android-decoder-async.md)。

[官方MDK文档](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)当前写
codec async默认1，但固定SDK公开头／Changelog无法解释此次实际缺省选择；项目
源码没有主动async=0覆盖，不把未知内部条件写成已查明。显式配置已进入生产
Android优先级，保留原软件回退与其他平台。不重复此前async=0实验，也不把已启用
AImage acquire再当新的优化候选。

固定Android16[MediaCodec实现](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/libstagefright/MediaCodec.cpp#6032)
的异步模式拒绝同步dequeue、实际输出走onOutputBufferAvailable。关闭后指标mode=1
并不可靠地表示运行期同步：stop/release的setState清异步flag，之后flush重新更新
指标。这解释了本次关闭后的metrics与真实async日志不一致，不拿静态dump覆盖
运行事件。另查output.delay=8用于slot分配，不能等同reorder深度。

新的ATrace仅在已有诊断trace注册后、系统isEnabled时发出，采用固定栈缓冲和成对
调用，非Android不调用。[NDK系统追踪契约](https://developer.android.com/ndk/reference/group/tracing)。
所有比较在各自单调时钟内算区间；PTS只做唯一键，不减远端时间或猜Rust起点。
该结果促成主控配置修复，服务端源码、补丁、版本和工具链均未变，仍无需重建JAR。
