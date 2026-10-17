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

从release切回E2E后，先在应用目录执行`flutter pub get --offline`恢复测试插件注册，
再运行--no-pub drive；没有缓存时使用正常pub get。不要手改生成注册文件。
默认高清80次、当前仍失败的1秒首帧门槛及原始证据见
[视频性能记录](../../../docs/implementation/video-performance.md)。
