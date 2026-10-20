# scrcpy 首帧、视频传输与连接稳定性核查

调查日期：2026-10-18。依据 scrcpy v5.0.1、固定 AOSP/Flutter 源码及后续隔离实验，区分协议机制、运行路径和性能归因。当前服务端身份见[vendor清单](../../servers/vendor/README.md)，依赖与首帧规则见[工具链契约](../implementation/repository-tooling.md)，性能结果见[视频性能记录](../implementation/video-performance.md)。

## 结论与产物身份

scrcpy v5.0.1 annotated tag 对象 `a0c27ff382c411af1301dcc1cd8205c9aeb81996` 解引用到源码提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`；tag对象不是源码commit。官方asset大小733930字节，SHA-256 `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`。[Release API][R01]、[tag对象][R02]

核查时 master 也指向该源码，但 develop.md 自称协议4.0且示例使用server4.0。开发文档可解释设计，字节协议应以固定5.0.1源码为准。[master API][R03]、[开发文档][R04]

历史协作暂停扩展、首次codec复用和有界输入候选均未成为当前官方服务端约束；各自的机制与失败结果见[暂停实验](cooperative-capture-pause.md)、[输入队列实验](capture-input-queue.md)及下文。

## 首帧与低延迟已有机制

- **已证：**官方开发者文档把静止画面起始不出帧、快速运动后的最后画面质量差列为 `KEY_REPEAT_PREVIOUS_FRAME_AFTER` 要解决的问题；v5.0.1 已设置 **100000µs（100ms）**，API23+ `KEY_PRIORITY=0`，API26+ `KEY_LATENCY=1`。100ms 是重复上一帧配置，不是端到端首帧时限，也不保证任何编码器严格兑现该延迟。[R04]、[SurfaceEncoder][R05]
- **已证：**v5.0.1 的自定义 codec options 在默认项之后写入，因此可以覆盖默认值；不能仅看到上游默认就断言实际进程一定采用它。[R05]
- **已证：**官方视频说明默认没有额外视频延迟缓冲；H264 被描述为应有更低延迟。官方 decoder 设置 `AV_CODEC_FLAG_LOW_DELAY`，没有在该初始化路径强制 `threads=1`。[video.md][R06]、[decoder.c][R07]
- **推论：**保留已经可用的编码器，优先测量主控播放器实际后端、探测、状态等待与呈现耗时。H264 适合作为性能基线，但不能用文档代替五种编码、硬件/软件后端和具体设备的测量。不能把 server `latency=1` 或 decoder 名称当成端到端低延迟证明。[R05]、[R06]、[R07]

## 帧协议、reset 与连接顺序

**已证：**v5.0.1 demuxer 先读 codec ID、视频 session 尺寸，再处理 session/media 包；媒体头为 12 bytes，CONFIG 不带普通媒体 PTS，H264/H265 CONFIG 合并到后续非 CONFIG 包。后续 session 可能改变尺寸。decoder 会在 AV1 硬件解码的新 session 重建 context。容器主控路径可以把参数放入 CodecPrivate，但必须保留配置、关键帧及新代顺序，不能机械复制 AnnexB 拼包或把 CONFIG 时间当作媒体 origin。[demuxer.c][R08]、[decoder.c][R07]；容器映射是**推论**。

**已证：**官方控制消息 `RESET_VIDEO=17` 调用 capture reset；`CaptureControl` 通过 `signalEndOfInputStream()` 打断编码，编码循环随后清理并启动新 session。这是编码会话重置，不是“立刻输出像素”的确认。[ControlMessage][R09]、[Controller][R10]、[CaptureControl][R11]、[SurfaceEncoder][R05]

**推论：**用官方 reset 恢复现有会话时，主控仍应等待新 session/config 与真实解码帧；不要把控制写入完成、resume ACK 或旧 snapshot 当新一代呈现成功。reset 是官方协议的一部分，不依赖已弃用的 type128 扩展。

**已证：**启用的 socket 固定依 video → audio → control 顺序建立，关闭的通道跳过。forward 模式第一条通道发送 dummy byte；`Server` 在 `DesktopConnection.open()` 完成后才发设备 metadata。所以 video+control 模式若先等待视频 metadata、再连 control，会形成等待环。本项目已经先连 video 和 control，再读 dummy/name/codec；应保留这个顺序。[DesktopConnection][R12]、[Server][R13]、[本地顺序](../../crates/interop_core/src/scrcpy.rs)

**已证：**本地应用窗口启动在 control actor 创建后发送 `START_APP`，随后才等待编码关键帧，避免无系统装饰的空白虚拟显示等待应用绘制、应用启动又等待首帧的循环。`read_video_preface()` 的有界关键帧等待与 `encodedKeyFrameReady` 仅证明编码数据可用；播放器真实像素仍是另一阶段。[本地启动与首包读取](../../crates/interop_core/src/scrcpy.rs)

## 背压与可丢弃边界

**已证：**SurfaceEncoder 同步写出编码输出后，才在 finally 中释放 codec output buffer；Streamer 使用 `IO.writeFully()`。官方 decoder 把编码包加入可增长 vecdeque，由独立线程解码；这不是严格限定包数/时长的队列。默认不加显示延迟也不等于所有阶段零缓冲。[R05]、[Streamer][R14]、[R07]

**已证：**官方显示端 frame buffer 保存一个待消费的解码帧，新帧替换旧帧；screen 统计该跳帧，并让原有 UI 事件消费最新帧。这是**解码后**的替换策略。[frame_buffer.c][R15]、[screen.c][R16]

**推论：**主控消费变慢可能沿 TCP/ADB 写入传回被控编码线程，并妨碍 EOS/reset/暂停到达清理边界。应持续读取/处理通道，限定主控内存与排队时长，及时呈现最新解码帧。不要逐包任意丢弃压缩数据；预测帧可能依赖已丢弃参考帧。若要放弃旧压缩代，应在可验证的 session/config/关键帧边界重新同步，并验证五种编码。

**已证：**本项目 `run_video()` 已在输出 I/O 前释放 session state 锁，并在 paused/awaitingSession 时读取后丢弃视频包；但正常播放的 `output.write_all()` 仍可能等待消费者。这是主控背压观察点，不是本轮已实测的故障归因。[run_video](../../crates/interop_core/src/scrcpy.rs)

## 测量边界

应分别记录编码数据可用、主控请求/确认、实际解码像素与呈现。按同一帧身份和同源时钟比较，避免把socket写入或控制ACK称为首帧。具体门禁与当前复现入口见[视频性能记录](../implementation/video-performance.md)。

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

MDK0.39.0变更及 fvp #146/MDK #117 的不同栈，统一见[SDK修复核查](mdk-sdk-snapshot-followup.md)。公开修复条目没有证明本次 renderer 空std::function已修复；帧转换替代接口的边界见下一节。

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

MDK0.39.0核查时SDK `include/mdk/Player.h:403–416`允许snapshot失败时回调
request为空，完成回调运行在独立线程。调用只调度renderer重绘；不可见surface可能
不重绘。因此调用者超时/撤销诊断token不是MDK请求取消或worker排空证据。
[官方snapshot调度说明](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-snapshotsnapshotrequest-request-snapshotcallback-cb-void-vo_opaque--nullptr)。

发布包fvp0.39.1 `lib/src/callbacks.cpp:693–694`及官方v0.39.1相同方法均在构造
typed-data前无条件解引用`ret->stride/height/data`；该方法也没有使用其它状态回调
的CallbackGuard。MDK失败契约与此存在明确缺口；它与历史renderer内部空std::function不是同一栈，不能混为已证根因。
[固定版本MdkSnapshot](https://github.com/wang-bin/fvp/blob/v0.39.1/lib/src/callbacks.cpp#L637-L688)。

调用侧串行请求、关闭后拒绝新请求以及保留超时槽位，不能证明 MDK worker 已排空。主控生命周期与实际运行结果见[视频性能记录](../implementation/video-performance.md)。

## fvp空结果故障与可复现交付（2026-10-18）

**已证：**核验pub.dev fvp0.39.1归档SHA-256为
`2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`，
其callbacks.cpp与本地锁定包一致（`d31142…623e`），不能用GitHub tag源码行数
代替pub发布包身份。将真实MdkSnapshot函数体、真实callbacks.h枚举与Dart_CObject
头放入最小宿主探针，仅在MDK callback边界注入契约允许的null，原版exit-11。
这是空指针解引用的确定性源边界复现，非历史renderer空std::function实机复现。
[官方pub归档](https://pub.dev/api/archives/fvp-0.39.1.tar.gz)。

**历史补丁与限制：**曾在 fvp 五份原生副本中，将null结果发送为空Uint8List，再由原有Dart逻辑完成Future为null；只提前return会留下永久pending请求。探针也通过真实Dart VM NativeApi.postCObject/ReceivePort验证空与带stride数据。该补丁及本地fork均已移除，当前直接继承原版缺口。

这一源边界复现没有修改MDK renderer二进制，也没有复现其空std::function栈；结果交付仍不证明worker排空。平台SDK分发与整包构建是另外的验证维度。

## 暂停补丁的正常首启重复分配候选（2026-10-18）

历史暂停补丁在SurfaceEncoder能力探测后无条件release，再在初始暂停门后创建捕获codec，即未暂停正常启动也创建两次；上游固定实现原本可复用探测实例。[固定SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)。后续隔离 initial-codec 候选15次确认分配2→1，完整Flutter A/B/A却未取得稳定首帧收益，故未采用。不能把首关键帧之前的分配解释为关键帧之后或稳态的等待。

Android运行时request-sync/drop-input-frames属于setParameters，不是启动MediaFormat选项；编码器flush行为未定义，不能用来清积压。[MediaCodec状态契约](https://developer.android.com/reference/android/media/MediaCodec#States)。

## 同JAR双分配实测与首帧SDK选项（2026-10-18）

目标AVD新生命周期、既有捕获JAR、按具体捕获PID过滤CCodec／MediaCodec系统日志，
三次均实际看到两次c2.android.avc.encoder创建：

| raw诊断 | 第一次allocate→Created ms | 第二次 ms | 两次Created间隔 ms |
| --- | --- | --- | --- |
| 2def2d8cc62c | 78 | 7 | 39 |
| 12c75b20f31a | 3 | 1 | 34 |
| 19ab34757fa4 | 11 | 5 | 33 |

间隔包含能力查询、capture.init与释放，不是纯冗余成本或收益上界。首轮脚本等待静态流后续包超时，只使用分配日志；后两次收到完整首包。没有解码或实际像素，不能与正式E2E首帧比较。

MDK公开`prepare(0)`回调表示媒体信息就绪，不能当首帧已显示；`onFrame/onVideo`
先于renderer接收，snapshot另经渲染／读回。`setBufferRange`的max不是固定延迟保证。
[Player APIs](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。
全局`videoout.buffer_frames`限制renderer缓存帧数，正整数；`profiler.gpu`控制GPU
时间采样。锁定fvp Android JNI_OnLoad主动设为1，因此实验在其初始化后请求0；
未读回SDK内部值，只报告请求。两项都影响进程内其他播放器，不能作为每个会话的
随意开关。[Global Options](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options)、
[固定上游源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/android/fvp_plugin.cpp)。
实际五组对照没有满足原严格性能预算，两个实验均不进入产品默认；首个32×32验证
截图指标与时钟读取括界已保留，详见[实际结果](../implementation/video-performance.md#测量方法)。

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

这些源码不支持“无条件pulse即可保留最新帧”的设想，本轮未实施pulse设备实验。静态冷启与最终单次变化可能丢失的风险，已经足以否定把它直接加入默认。

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
[两类实测及原始证据](../implementation/video-performance.md#测量方法)。

## 普通Driver调度与后续decoder定位（2026-10-18）

上述正常调度缺口现由独立`tool/benchmark/live_video_performance.dart`补齐；实际绑定是
`_DriverBinding`，使用普通Scheduler／Renderer／Widgets混入及测试messenger，没有
Live draw/pump循环。它不是类名为WidgetsFlutterBinding的完整产品App；不将框架
内部仍import flutter_test误写成使用LiveTestWidgetsBinding。
[固定版本Driver绑定源码](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/packages/flutter_driver/lib/src/extension/extension.dart#L36)。
真实Rust／共享播放器、逐次新图案及host实际窗口PNG已跑通；在相同1280/60/8Mbps
下每路60次，原生严格失败、FFmpeg slice通过，具体预算、计时范围和清理见
[完整实测](../implementation/video-performance.md#普通调度基准与解码路径对照)。
这补了反馈循环，没有证明实体手机默认硬解性能，也没有替换产品默认解码器。

同PTS、同主控单调时钟显示relay开始write→onVideo中位原生134.373ms、软件1.414ms。
共享Matroska即时mux和HTTP写路径已有TCP_NODELAY、每包即write，固定攒包解释因此
更弱；但该段仍含socket消费、demux、decoder与图像获取，不能叫纯硬解等待。
使用write完成时刻可能出现微小负值，因为消费者可以在写Future完成前处理已收到
的包；选择writeStartedUs描述边界，不能删除负值后再比较。

codec异步与AImage异步acquire是不同选项，文档默认与实际路径的差异见[SDK核查](mdk-sdk-snapshot-followup.md)。后续实际路径如下；已经启用的机制不再列作新优化候选。

## 实际AImageReader异步路径确认（2026-10-18）

普通Driver基准的原生默认路径已在专用主控AVD上附加LLDB，仅记录少量函数参数、
返回值及调用栈，不调用被测函数、不记录媒体内容。下列三条成功回执可按指针关联，
调用栈均包含libmdk.so：

| 边界 | 实际回执 |
| --- | --- |
| AImageReader_getWindow | 返回0，保存reader与window对应关系 |
| AMediaCodec_configure | window与上项相同，flags=0，返回0 |
| AImageReader_acquireLatestImageAsync | reader与首项相同，返回0，image非空 |

这证明本次默认解码器输出连接到该AImageReader，且成功走异步latest acquire；
Flutter自己的SurfaceTexture日志不能单独证明或否定这条解码路径。
API的窗口及图像获取契约见[Android NDK AImageReader_getWindow](https://developer.android.com/ndk/reference/group/media#aimagereader_getwindow)、
[AImageReader_acquireLatestImageAsync](https://developer.android.com/ndk/reference/group/media#aimagereader_acquirelatestimageasync)。
这里是本次固定二进制的运行证据，不推断所有平台都走同一路径。

探针只确认调用路径。调试器会暂停线程，取得事件时的首帧不能用于延迟对照；另有返回回调注册错误，因此不声称完整调用覆盖。上述成功返回及关联指针足以排除“基线尚未启用异步latest acquire”的候选前提。

MediaCodec输入到输出、图像获取到onVideo需用低开销追踪分别测量；函数断点不能充当逐帧性能计时。

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
该结果促成主控配置修复，这些主控结果不涉及服务端实现变化。
