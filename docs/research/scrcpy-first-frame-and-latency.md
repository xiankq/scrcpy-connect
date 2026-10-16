# scrcpy 首帧与客户端状态等待

调查与实测：2026-10-17。先核对官方开发者文档与固定源码，再用真实 Android 双 AVD 缩小故障。本记录区分已通过的 Android 双 AVD 实测与音频、长期后台和其他平台仍待验收的项目。

## 已确认与修正

- 官方开发者文档明确说明静止屏幕初始不出帧的问题，由 `KEY_REPEAT_PREVIOUS_FRAME_AFTER` 解决。[S01] 官方 5.0.1 server 已设置 100000µs 重复间隔、priority=0、latency=1；本项目没有覆盖它们，不能把重复添加这个配置作为修复。[S02]
- `session.start` 返回前，本项目已从真实 server 收到 CONFIG 和编码关键帧。之后的慢首帧发生于共享播放器路径。
- 起播前的同步 `waitFor(playing, timeout:0)` 会等待尚未请求的状态；本次真实运行中等待延续至约20秒守卫断源，阻塞 Dart 时也无法靠 Dart Timer 中断。删除请求前查询，只在请求后使用实际状态回调与显式正数1ms的有界查询，五编码连续生命周期回归中，本地输出到真实首帧约282～1179ms，编码服务启动另计。不能把0写作“非阻塞”，也不能把 setter 的 Dart 缓存当确认。[P02]
- 同一输入先挂载 Texture 仍然24秒失败；修正状态等待后，未挂载 Texture 也能取得首帧。因此已经移除实验性的 prepared/mount 回调，没有把提前挂载列为本机必需修复。
- 默认 raw MDK Player 在本机只尝试 FFmpeg，AV1出现 `decoder.video -38`。本机 x86_64 SDK 没有捆绑 dav1d，不能据此断言设备不支持AV1。按 MDK 官方建议设置平台 decoder 优先级后，Android 的 AMediaCodec 路径取得真实AV1帧。[M01] AMediaCodec名称不证明硬件加速，模拟器可能使用软件系统编解码器。
- 仍保留 fpsprobesize=0、明确 Matroska 输入、min=0/drop buffer；没有使用可能在探测阶段丢掉初始IDR的 `+nobuffer`。[P01] `max=150`不是固定启动延迟，也不保证长GOP时队列严格不超过150ms。

产品启动顺序保持 `编码关键帧 → media.open → prepare/texture → 请求播放并实际确认 → snapshot像素 → Core.session.ready → 返回界面`。分配纹理、播放器赋值、HTTP连接均不能代替首帧。启动预算从24秒收紧到18秒，早于Rust raw消费者开始后的20秒保护；没有延长超时掩盖问题。迟到ACK仍不能复活已取消会话。

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

两个时间分别计时，不把本地输出时间当端到端总时间，也不把一次模拟器结果当生产延迟SLO。证据临时位于 `/tmp/connect-fvp-platform-decoders.log`、`/tmp/connect-e2e/fvp-platform-decoders-result.json`。后续完整生命周期也已通过：H264/H265/AV1/VP8/VP9本地首帧分别为1016/347/290/294/301ms，PNG实际颜色数1846/2192/2915/2081/2212。五种均通过实际暂停、远端捕获暂停/恢复、再次像素确认、截图、停止与纹理分离，整体12秒。证据 `/tmp/connect-fvp-shared-lifecycle-five.log` 和 `/tmp/connect-e2e/fvp-shared-lifecycle-result.json`；Flutter截图为 `/tmp/connect-e2e/fvp/portable-<codec>.png`，已目视检查H264与AV1实际Settings内容。图片只保留临时目录，不加入Git。

复现首帧回归（目标已开启TCP调试并保持已知可见Settings界面，主控不需要产品内调试权限）：

```sh
cd apps/connect
rtk proxy flutter pub get --enforce-lockfile
rtk proxy flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/fvp_probe.dart \
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

## 生命周期回归与剩余边界

1. 静止输入的暂停原先4秒失败：有界查询约1～2ms返回false，更换decoder无效。官方ControlMessage定义RESET_VIDEO=17，Controller只请求重置现有encoder，不注入点击或重启应用。[S08][S09] 实测在请求本地pause后用该控制消息提供新编码输出，可以收到真实暂停ACK。共享VideoPresentation现按会话串行化：本地pause请求/refresh/真实ACK → Core暂停捕获；恢复则Core先继续捕获并RESET_VIDEO → 本地playing ACK与实际snapshot。确认失败不提交捕获暂停，尽可能恢复本地消费者，保留原始错误。五种编码完整链路已通过；真实 HOME 退后台2秒再返回 Activity 也在产品页面通过，恢复要求真实 snapshot，不能由 streaming 状态代替。更长后台、系统回收仍需另外验收。
2. 旋转已验证同一 session/relay 的 generation 1→2、新代真实 snapshot、Texture 更换及 Core 触控尺寸同步，测试约5秒通过。模拟器自动旋转会随传感器转回；测试夹具关闭目标自动旋转，结束恢复原设置。另一次7秒回归在旋转动画后900ms截图，目视确认画面方向与比例正确；这900ms仅用于稳定视觉检查，不计作首帧时间。
3. 删除267行 RemoteVideoDecoder 及 MainActivity 视频方法后，真实产品页面的五种编码再次全部通过（28秒），包含 Texture、实际首帧、沉浸布局、退出与停止。后续共享PCM暂停恢复、实际产品HOME与Activity重建已通过，旧声音循环也已删除；真实外部AudioManager焦点也已完成双设备临时loss/gain、手动暂停保留和永久loss关闭旧源的验收，见[共享所有权记录](android-share-trust.md)；长期后台、进程回收仍待单独验收。
4. 公共dispose为async-void，只能报告请求及纹理分离，不能伪称native delete已确认。fvp锁文件也不能锁定所有平台下载的MDK二进制；四端归档与摘要仍需固定。

## 回归证据与退出保证

产品五编码日志 `/tmp/connect-shared-product-codecs.log`，截图 `/tmp/connect-e2e/fvp/remote-codec-<codec>-live.png`。真实 HOME 日志 `/tmp/connect-fvp-product-background.log`，旋转日志 `/tmp/connect-fvp-rotation-locked.log`、稳定视觉复验 `/tmp/connect-fvp-rotation-visual.log`。回归源文件分别为 `video_codecs_test.dart`、`background_resume_test.dart`、`video_reconfigure_test.dart`。

旋转测试还发现空闲 Rust 事件观察者令 Dart Stream 取消一直等待。现改为显式 open/cancel 观察者、取消 token 和 RAII 回收，先通知 Rust 再 cancel Dart 订阅；7项 Rust 接口测试、真实旋转结束和 bridge.dispose 均通过。观察者心跳只检测端口存活，不冒充产品状态。

Flutter host driver 曾在应用测试超时后输出成功并返回空 metadata。媒体 driver 现要求清理结束后的 `mediaAcceptanceComplete=true`；已用失败运行确认缺失回执时非零退出。验收同时检查应用断言与真实像素，不能只看 host 的“All tests passed”。

## 状态回调竞态复查

独立复查发现 native `waitFor` 可以先于经 ReceivePort/broadcast 递送的 Dart 回调确认状态；因此“上次 callback 已是 playing”不能跳过本次恢复请求。新共享 `PlaybackConfirmation` 每次先请求，再以正数1ms native query 确认；回调只唤醒实际查询，不独立充当 ACK。`close()` 先阻止新查询、取消并排空所有 waiter，播放器再释放句柄；否则退出时仍在运行的暂停轮询可能读取已删除的 native handle。4项接口回归覆盖迟到回调、无回调确认、释放取消与超时/查询失败清理，独立只读复查通过。

真实五编码各连续3次暂停/恢复回归通过（15秒），本地首帧H264/H265/AV1/VP8/VP9为1179/406/284/293/282ms，每种4次真实snapshot回执（首次+3次恢复）；日志 `/tmp/connect-fvp-final-video-cycles.log`，完整元数据 `/tmp/connect-e2e/fvp-three-cycles-result.json`。复现时使用完整生命周期命令，追加 `--dart-define=CONNECT_FVP_PAUSE_CYCLES=3`。这验证实际调用链，不能声称可以确定触发每一种线程调度。HOME driver也已加专属完成回执校验，历史成功日志仍是实际应用测试通过，而非仅主机空回执。

音频与engine迁移后，实际产品五codec再次26秒通过，完成回执true；日志 `/tmp/connect-final-product-five-codecs.log`。HEVC目视仍低清，沿用已列出的AVD编码器/实际尺寸专项验收，不将首帧渲染成功写成全画质验收。

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
