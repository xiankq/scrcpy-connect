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

从release切回E2E后，先在应用目录执行`flutter pub get --offline`恢复测试插件注册，
再运行--no-pub drive；没有缓存时使用正常pub get。不要手改生成注册文件。
默认高清80次、当前仍失败的1秒首帧门槛及原始证据见
[视频性能记录](../../../docs/implementation/video-performance.md)。
