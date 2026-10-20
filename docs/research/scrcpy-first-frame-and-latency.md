# scrcpy 首帧与客户端状态等待

调查与实测：2026-10-17。先核对官方开发者文档与固定源码，再用真实 Android 双 AVD 缩小故障。本记录区分已通过的 Android 双 AVD 实测与音频、长期后台和其他平台仍待验收的项目。

当前依赖与首帧确认规则见[工具链契约](../implementation/repository-tooling.md)和[架构](../implementation/architecture.md)。

## 已确认与修正

- 官方开发者文档明确说明静止屏幕初始不出帧的问题，由 `KEY_REPEAT_PREVIOUS_FRAME_AFTER` 解决。[S01] 官方 5.0.1 server 已设置 100000µs 重复间隔、priority=0、latency=1；调查时本项目未覆盖它们，不能把重复添加这个配置作为修复。[S02]
- `session.start` 返回前，本项目已从真实 server 收到 CONFIG 和编码关键帧。之后的慢首帧发生于共享播放器路径。
- 起播前的同步 `waitFor(playing, timeout:0)` 会等待尚未请求的状态；本次真实运行中等待延续至约20秒守卫断源，阻塞 Dart 时也无法靠 Dart Timer 中断。删除请求前查询，只在请求后使用实际状态回调与显式正数1ms的有界查询，五编码连续生命周期回归中，本地输出到真实首帧约282～1179ms，编码服务启动另计。不能把0写作“非阻塞”，也不能把 setter 的 Dart 缓存当确认。[P02]
- 同一输入先挂载 Texture 仍然24秒失败；修正状态等待后，未挂载 Texture 也能取得首帧。因此已经移除实验性的 prepared/mount 回调，没有把提前挂载列为本机必需修复。
- 默认 raw MDK Player 在本机只尝试 FFmpeg，AV1出现 `decoder.video -38`。本机 x86_64 SDK 没有捆绑 dav1d，不能据此断言设备不支持AV1。按 MDK 官方建议设置平台 decoder 优先级后，Android 的 AMediaCodec 路径取得真实AV1帧。[M01] AMediaCodec名称不证明硬件加速，模拟器可能使用软件系统编解码器。
- 仍保留 fpsprobesize=0、明确 Matroska 输入、min=0/drop buffer；没有使用可能在探测阶段丢掉初始IDR的 `+nobuffer`。[P01] `max=150`不是固定启动延迟，也不保证长GOP时队列严格不超过150ms。

## 实验与证据

工具链 Flutter3.47.6/Dart3.13.5，fvp0.39.1，controller emulator-5554/target emulator-5556，均Android API36 x86_64。真实链路为 Rust ADB → 官方scrcpy5.0.1 → 私有帧 → Rust Matroska/HTTP → 公开fvp Player → 实际snapshot；没有调用自维护Kotlin播放器。

| 单次实验 | 结果与解释 |
| --- | --- |
| 直接Player：先Core ACK/挂载再snapshot | 约3秒/730种颜色。用于缩小范围；提前ACK不是产品首帧证明。 |
| Portable原流程、waitFor0 | 约20秒断源才出现像素或24秒超时；不能记为成功。 |
| 保留waitFor0，仅先挂载 | prepare约567ms、texture582ms、挂载615ms，仍24秒失败；排除“只要提前挂载就能修好”。 |
| 先挂载，删除全部同步waitFor0，回调确认 | 首帧981ms、Core.ready成功；暂停另报4秒失败。 |
| 同条件改为请求后timeout1查询 | 首帧966ms，实际查询耗时0～1ms；暂停查询真实返回false，没有伪造已暂停。 |
| 未挂载，timeout1，原decoder | H264首帧783ms/H265188ms；AV1 FFmpeg open/decode失败。 |
| 移除实验avcodec flags/threads | AV1仍报同样错误，未把它归咎于低延迟参数；最终未保留这两个实验选项。 |
| 未挂载、请求后timeout1、官方平台decoder优先级 | 下表五种编码均取得实际首帧、Core.ready、真实PNG截图和停止释放回执；整个测试10秒通过。 |

| 编码 | 编码服务启动ms | 本地输出到首帧ms | 实际PNG字节 |
| --- | ---: | ---: | ---: |
| H264 | 1277 | 1126 | 57601 |
| H265 | 819 | 351 | 64035 |
| AV1 | 789 | 384 | 69234 |
| VP8 | 845 | 295 | 50339 |
| VP9 | 804 | 296 | 56903 |

两个时间分别计时，不把本地输出时间当端到端总时间；一次模拟器运行也不是生产延迟SLO。历史完整生命周期中的远端捕获暂停依赖已弃用的[协作暂停补丁](cooperative-capture-pause.md)，不代表当前原版JAR行为。

复现首帧回归（目标已开启TCP调试并保持已知可见Settings界面，主控不需要产品内调试权限）：

```sh
flutter pub get --enforce-lockfile
cd app
flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/fvp_probe.dart \
  --target=integration_test/fvp_video_lifecycle_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_FVP_CODECS=h264,h265,av1,vp8,vp9 \
  --dart-define=CONNECT_FVP_FIRST_FRAME_ONLY=true
```

回归要求每种编码在本地输出5秒内取得真实像素且Core ACK仍成功；之后读取PNG、停止准确会话并关闭对应relay。`FIRST_FRAME_ONLY=true`明确不表示已验证pause/resume；默认完整生命周期模式检查它们；去掉最后一个FIRST_FRAME_ONLY参数即可复现，不静默跳过失败。

## 官方实现对照

固定scrcpy master与v5.0.1目标均为 `a60891aea193d92e7e5c3942700eca63f9d19a5f`；fvp0.39.1源码为 `a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93`。版本与JAR必须匹配，不能照抄develop.md中旧版本示例。

官方decoder设置 `AV_CODEC_FLAG_LOW_DELAY`，没有显式threads=1。[S04] FFmpeg帧线程可能等待后续帧；LOW_DELAY会禁用对应帧线程路径。[F01] 当前故障已经通过状态等待对照定位，未保留额外强制线程参数。若将来测到具体decoder的帧线程延迟，应单独验证其选项，不能凭配置字符串宣称硬件后端已低延迟。

官方把H264/H265 CONFIG与后续包合并，CONFIG不使用普通媒体PTS。[S05][S06][S07] 本项目走标准容器：CONFIG进CodecPrivate，NAL转长度前缀，首个有效媒体PTS建origin；不需要机械拼接AnnexB。不写伪造固定帧率，每包独立Cluster保留整数微秒。FFmpeg真实解码的独立证据见[共享媒体研究](cross-platform-media-pipeline.md)。

MDK `prepare(0)`仅可确认媒体信息，不保证那一刻已经显示首帧；默认state setter是异步请求。[M01] fvp公开 `getGlobalOption` 实际仍被注释，不能直接调用C++文档的runtime hint getter；最终使用文档列出的各平台优先级并逐流实测。iOS/macOS/Windows的候选列表不构成这些平台的构建或运行验收。

## 生命周期与退出边界

官方 RESET_VIDEO=17 只请求重置现有编码器，不注入点击或重启应用。[S08][S09] 当静止输入不能确认本地 pause 时，实验通过 reset 提供新输出以收到真实ACK；这不等于官方存在捕获暂停协议。当前行为以[架构](../implementation/architecture.md)为准。

公共 dispose 为 async void，只能确认请求与纹理分离，不能宣称 native delete 已确认。Flutter host driver 还曾在应用超时后返回空 metadata；因此媒体验收同时校验应用完成回执和像素，不能只读主机的“All tests passed”。

## 状态回调竞态复查

独立复查发现 native `waitFor` 可以先于经 ReceivePort/broadcast 递送的 Dart 回调确认状态；因此“上次 callback 已是 playing”不能跳过本次恢复请求。新共享 `PlaybackConfirmation` 每次先请求，再以正数1ms native query 确认；回调只唤醒实际查询，不独立充当 ACK。`close()` 先阻止新查询、取消并排空所有 waiter，播放器再释放句柄；否则退出时仍在运行的暂停轮询可能读取已删除的 native handle。接口回归覆盖迟到回调、无回调确认、释放取消与超时/查询失败清理。

Android双AVD五种codec各三轮pause/resume均取得首次及恢复snapshot，覆盖上述真实调用链；不能据此声称穷举所有线程调度、物理设备和长期后台。HEVC画质限制另见[模拟器约束](hevc-emulator-constraints.md)。

## 无装饰应用显示的启动顺序复查

2026-10-17，多窗口真实页面回归发现：主屏出图，打开Settings独立窗口却在8秒首帧等待后报`encoder_start_failed`。把流程缩小到已有`real_application_display_clipboard_and_task_survive_session_stop`（不启动或暂停主屏）仍稳定失败，排除了必须有旧冻结窗口的解释。修复前同一用例11.26秒失败。

官方客户端在控制线程和视频demuxer启动后提交START_APP，不等待首个解码帧；服务端收到请求后等待虚拟display可用，再在该display启动应用。[S10][S09] 本项目旧顺序是先读取关键帧，再创建控制actor并发送START_APP。无系统装饰的新显示尚无应用内容时，这形成启动依赖环；重复帧参数不能替代首次内容。此因果判断来自源码和下面的单变量实测。

现保留socket、codec及session尺寸校验，在会话尺寸收到后创建控制actor并提交一次START_APP，再等待有界关键帧；不放宽关键帧、解码或真实任务断言。修复后相同用例4.25秒通过，覆盖真实应用、剪贴板和关闭后任务保留。复现命令（官方adb只用于部署，测试实际调用Rust ADB）：

```bash
env INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 cargo test -p interop-core --test scrcpy_device real_application_display_clipboard_and_task_survive_session_stop -- --ignored --nocapture
```

这项结果不证明主控多窗口UI或并发资源全部通过；它们继续由独立Android E2E验收。

## 一手来源

[S01]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md#screen-video-encoding
[S02]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L282-L318
[S03]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/video.md
[S04]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L31
[S05]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c
[S06]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/packet_merger.c
[S07]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/Streamer.java#L96-L111
[F01]: https://github.com/FFmpeg/FFmpeg/blob/n7.1/libavcodec/pthread.c#L44-L64
[F02]: https://ffmpeg.org/doxygen/7.1/structAVCodecContext.html
[F03]: https://github.com/FFmpeg/FFmpeg/blob/n7.1/libavformat/demux.c
[P01]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/video_player_mdk.dart#L340-L353
[P02]: https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/player.dart
[M01]: https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs/82b2c09b7892711a9f1e319424e258d3fb5d9978
[M02]: https://github.com/wang-bin/mdk-sdk/wiki/Decoders/cffa9514397313c46d60b98ea9def02d60e87afa

[S08]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/ControlMessage.java
[S09]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/Controller.java

[S10]: https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/scrcpy.c#L902-L970
