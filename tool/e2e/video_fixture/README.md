# 视频性能目标夹具

独立测试 APK，既不属于产品依赖，也不改变被控端无需额外 App 的要求。
四个色块编码一个 4 bit 计数器。真实 scrcpy 控制通道的 DPAD_DOWN 松开后，
Android View 更新计数器并绘制新图；主控从实际解码 RGBA 和已呈现的截图识别色块。
因此保留旧帧、空白纹理和只收到控制写入回执均不能通过。

构建：`python3 tool/e2e/video_fixture/build.py`。生成文件全部在临时目录。
驱动安装前要求该独立包不存在，测试后卸载自己的包并返回系统设置。
时延从主控发送操作前的单调时钟开始，到实际新像素可读结束，包含轮询和 snapshot
开销，是输入到解码图像的上界；截图另验真实呈现，不冒充逐帧玻璃到玻璃延迟。


`apps/connect/integration_test/video_performance_test.dart`可通过
`CONNECT_PERF_MAX_SIZE`、`CONNECT_PERF_MAX_FPS`、`CONNECT_PERF_BIT_RATE`
选择码流配置；默认640/30/2000000保留既有基准。结果记录实际解码尺寸。
`CONNECT_PERF_CODEC`可选h264/h265/av1/vp8/vp9（默认h264）；
`CONNECT_PERF_ENCODER`可显式指定目标枚举中的匹配编码器（默认空，交给平台）。
结果分别记录请求值、Core画质回执及实际`video.frameTrace`/`decoder.video`事件；
实际codec观测需开启`CONNECT_PERF_TRACE_FRAMES`，解码器以`decoder.video`为准，
不能仅凭请求值宣称实际使用了某解码器。
这两个参数仅扩展性能测试入口，不改变产品默认；codec/encoder对照不需要重建JAR。
`CONNECT_PERF_MAX_START_MS`与`CONNECT_PERF_MAX_POST_KEYFRAME_MS`分别约束完整首像素
和首关键帧后的Core启动工作；P50/P95门槛沿用独立参数。结果保留每项预算判定，
整体完成仍要求全部通过。该四块计数器不能作为高动态图像吞吐/稳定60fps的证明。

`CONNECT_PERF_PAUSE_CYCLES`可将每轮暂停／恢复次数设为1–50（默认1）。每次暂停
确认后通过真实控制通道改变被控计数器，恢复时必须读到对应的新像素，再核对最终
Flutter合成画面；仅收到resume回执或保留旧帧无法通过。结果`pauseSamples`记录
每次暂停、恢复与新像素耗时及失败阶段，恢复到新像素耗时包含resume调用。

驱动环境变量`CONNECT_E2E_VIDEO_MOTION=true`会向独立夹具传入显式intent参数，
在计数器中间采样带以外每次绘制改变彩色块，并请求下一次动画绘制。默认关闭，
因此既有静态基准仍可复现。结果记录`fixtureMotionEnabled`，配合
`CONNECT_PERF_IDLE_MS=3000`观察没有按键期间的实际包量和字节量。
这会增加目标绘制与编码负载；请求每次动画刷新不等于已经达到60fps，8Mbps配置
也不等于实测吞吐8Mbps。动态与静态延迟应分别报告，不能混为同一基线。

`CONNECT_PERF_SNAPSHOT_STRESS=2000`会在每轮输入／暂停之前连续读取2,000次64×64
截图（允许0–10,000，默认0关闭），逐次等待原生完成并断言真实计数器，避免用并发
请求人为覆盖fvp的单个Dart完成槽。每100次输出`VIDEO_SNAPSHOT_STRESS`进度，最终
结果保留完成数与用时；原生崩溃没有最终JSON时仍可保留最后一次完成回执。
这个隔离对照用于区分持续renderer读回与暂停／释放触发的问题，不是性能优化参数。

`CONNECT_E2E_VIDEO_TIMELINE=true`在独立夹具启用按键处理及首次新计数`onDraw`
开始／结束的`System.nanoTime()/1000`记录，公开`KeyEvent.getEventTime()`另以毫秒
保存。驱动按每次运行ID筛选单一日志tag，保存`target-timeline.json`；最终结果按
递增`fixtureSequence`逐项匹配实际计数，包含暂停期间输入，支持4 bit计数回绕，
`targetTimelineComplete`须为true。原生崩溃时也保留可取得的部分日志并卸载夹具；
时间线采集错误不会覆盖原始主流程错误，正常回调先写完整报告再报观测失败。

配合`CONNECT_PERF_TRACE_FRAMES=true`，relay有界记录保留原始`sourcePtsUs`以及
归一化`ptsUs`，每次完整输入的`VIDEO_INPUT_SAMPLE`日志保留对应阶段与帧回执，
避免原生崩溃抹掉全部已完成输入。源PTS不是编码完成时间，跨设备时钟不可直接
相减；同目标onDraw回调也不是GPU／合成／物理呈现完成。
[时钟定义、对照与边界](../../../docs/implementation/video-performance.md#目标输入绘制与源pts观测2026-10-18)。

同时开启上述时间线、逐帧观测与`CONNECT_PERF_TRACE_CLOCK=true`，每轮输入循环前后
各执行三次有界`session.clock.probe`。目标输入／绘制另保留BOOTTIME／nanoTime／BOOTTIME
读数，驱动在`clockBounds`中保存带量化及往返误差的draw结束→payload区间。
此分析以本轮连续运行、偏移稳定为条件；非空区间不证明没有VM暂停或时钟变化。
源PTS同nanoTime时钟域另列假设，不把它当编码完成时间。探针开销在输入计时之外，
仍会影响预热时间。缺失、逆序或不相容数据会保存报告并使观测验收失败。
[算法、来源及实际结果](../../../docs/implementation/video-performance.md#时钟括号与surface输入实验2026-10-18)。

`CONNECT_PERF_ADB_BURST=true`仅用于ADB传输对照，默认关闭。每次初始化显式写入
该开关，避免持久偏好污染下一组；每轮新连接记录`adbBurstActive`并断言实际协商值
等于请求值。Burst候选必须使用宣告`delayed_ack`的adbd，对不支持的旧设备不能冒充
候选测量。保持其他画质、时间线、像素和预算参数一致；该开关不改变scrcpy JAR。

从release切回E2E后，先在应用目录执行`flutter pub get --offline`恢复测试插件注册，
再运行--no-pub drive；没有缓存时使用正常pub get。不要手改生成注册文件。
默认高清80次、当前仍失败的1秒首帧门槛及原始证据见
[视频性能记录](../../../docs/implementation/video-performance.md)。

`analyze_codec_trace.py`离线分析目标Perfetto中的CCodec `onWorkDone(...@ts=...)`，
与独立宿主raw-drain回执的原始PTS关联；不操作设备或下载工具。
需要官方`trace_processor query`，输入示例和本次原件见
[目标侧分段记录](../../../docs/implementation/video-performance.md#目标ccodec完成边界与源年龄2026-10-18)。
分析器按唯一进程名筛选，拒绝trace data-loss、PTS歧义／接收缺项和时钟不相容，
保留全部匹配及固定最后1/3统计。时钟snapshot是相继读取、并非严格误差括号；
该结果不是纯编码耗时或主控实际呈现延迟，不能代替真实新像素E2E。
校验：`python3 -m unittest discover -s tool/e2e/video_fixture -p test_analyze_codec_trace.py`。


真实视频断网恢复使用`apps/connect/test_driver/video_recovery.dart`和
`integration_test/video_recovery_test.dart`。沿用上述ADB/双设备/fixture环境，
设置`CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-recovery`，在apps/connect运行：

```sh
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/video_recovery.dart \
  --target=integration_test/video_recovery_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=25557
```

主机25557端口须空闲；代理上游默认127.0.0.1:25556，可用
`CONNECT_E2E_UPSTREAM_PORT`覆盖。driver只关闭本次活动ADB socket，继续接受真实
adbd重连；验证新session、真实解码、Flutter合成新图案和停止语义。它拒绝覆盖已有
fixture安装，结束后卸载自己的fixture、恢复Settings并关闭代理。result.json、
proxy-events.json、cleanup.json及截图仅存/tmp；EOF代理不代替物理无线切网验收。
