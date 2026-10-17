# 视频首帧、持续新像素与阻塞恢复

2026-10-18。按用户最新优先级推进视频性能、首帧和连接稳定性；USB 等产品工作顺延。本批没有修改或重建 scrcpy JAR。[产物与官方机制核查](../research/scrcpy-first-frame-performance.md)区分官方 vendor 文件和当前视频依赖的既有暂停补丁产物。

## 测量范围

两台 API36 x86_64 AVD，主控 emulator-5554、被控 emulator-5556；被控 secure=0 的隔离 TCP 调试实验端经宿主 25556 转发，主控访问 `10.0.2.2:25556`。Flutter3.47.6/Dart3.13.5，fvp0.39.1。Flutter 为 debug，native hooks 编译 Rust release；不把这些数值当物理双机无线、TLS 配对、发布包或热功耗的验收。

- Core `captureStartupTimingMs`：同一 Rust `Instant` 的累计毫秒，依次记录设备/唤醒条件/编码器选择核验、JAR 上传、metadata、编码关键帧及启动完成。不是把设备媒体 PTS 与主控时钟相减。
- 输出 `outputStartupTimingMs`：从创建本代输出起，累计记录 relay 打开、player 打开、实际播放确认和 snapshot 首像素。`video.prepare`/`video.texture` 两项是 player.open 内部独立 Stopwatch 的观测，不能与累计项逐个相加。
- `firstDecodedFrameMs` 从 Core 已返回编码首帧之后开始；不含 ADB 设备连接或 Flutter 冷启动。实际 Texture 挂载和截图另验，不能称它为已经显示到屏幕。
- 图案测试从主控发送真实 `session.key` 前计时，直到实际 MDK snapshot 包含目标新计数器。包含控制传输、目标绘制、编码、媒体传输、解码、snapshot 和最多10ms轮询等待，是输入到解码像素可读的上界。每轮再检查 Flutter 真正呈现的截图；没有测量逐帧玻璃到玻璃延迟。

## 首帧对照与被否定的尝试

同样静止 Settings、H264、maxSize640/maxFps30，未改服务端或验证要求。

| 三次样本（毫秒） | 原配置 | 仅限探测字节数后 |
| --- | --- | --- |
| Core启动 | 924 / 787 / 755 | 882 / 738 / 764 |
| 输出到已解码首像素 | 1131 / 1036 / 995 | 491 / 410 / 411 |
| 启动到已解码首像素（两段相加） | 2055 / 1823 / 1750 | 1373 / 1148 / 1175 |

输出段中位数1036→411ms（约60%减少），完整会话启动中位数1823→1175ms（约36%减少），各只有三次实验样本，不是生产分位数。原始结果 `/tmp/connect-video-baseline-result.json` 和 `/tmp/connect-e2e/video-probe-32bytes/result.json`。

分段红回归 `/tmp/connect-video-probe-red-r3.log` 实际输出1100ms，900ms门槛失败；其中 prepare568ms、texture585ms、opened609ms、playing743ms、verified1098ms。先只加 `avformat.analyzeduration=100000`，实测1060/1122/943ms，没有明显收益，已撤回；不能把这个尝试记作优化。最终仅对本项目已提供 CodecPrivate/尺寸的 Matroska 输入配置 `avformat.probesize=32`，prepare 降到8/2/2ms，三次900ms回归通过；保留原始 IDR、播放确认和32×32像素验证，没有采用会丢弃探测阶段初始包的 `+nobuffer`。

此设置限定在共享实时视频适配器，未改文件播放器或音频策略。32 是 FFmpeg 允许的最小探测字节数，减小探测量可能减少可推断信息，所以必须验证自己的完整容器头与各编码，不可照搬到任意未知裸流。[FFmpeg格式参数](https://ffmpeg.org/ffmpeg-formats.html#Format-Options)、[fvp低延迟实现及初始关键帧注释](https://github.com/wang-bin/fvp/blob/v0.39.1/lib/src/video_player_mdk.dart)。

五编码真实共享播放器及各3次暂停恢复16秒通过：H264/H265/AV1/VP8/VP9 输出首像素545/607/409/294/287ms，每种都有实际PNG和快照回执。`/tmp/connect-video-probe-five.log`、`/tmp/connect-e2e/video-probe-five/result.json`。这里只证明五种仍能启动与恢复，不能据此宣称五种均变快或 HEVC 画质通过。早期计时插桩曾出现编译错误及事件类型错误，均修正后重跑；这两次失败不是用户性能问题的复现。

## 两种真实阻塞先红后绿

1. `run_video` 先接收完整 scrcpy 包再向本地 relay 发送。上游 ADB 已交付半包却不断开时，下游尚未看到首字节，其局部期限无法生效。真实内存 ADB OPEN/OKAY/WRTE→生产 `run_video`→认证 TCP 用例，11秒后仍 `streaming`，实际红日志 `/tmp/connect-video-transport-red.log`。
2. HTTP 消费者保持连接但停止读取，实际 TCP 接收窗口填满后，relay 写入无限等待、上游不再 drain。公开 `MediaStreams` 命令和真实 TCP 用例，12.2秒后仍 `streaming`，实际红日志 `/tmp/connect-video-http-red.log`。

修复：上游完整单元的第一字节之后，header/session/payload 总计限10秒；HTTP响应头和每个实际待交付chunk限10秒。失败沿既有取消路径关闭该视频通道；没有随意丢弃有参考关系的压缩包，也不关闭设备上其它ADB服务。完整包之间依旧可以长期静止，明确取消仍立即结束。

两组窄回归3/3和2/2通过，10.30/10.05秒。包括头、session、payload三类截断、完整包间静止10.3秒、半包取消和消费者背压取消。固定10秒意味着极慢消费者也会被结束；这是已有输出无法交付的期限，不是所有画面都必须固定产生新帧。

```sh
cargo test -p interop-core --lib video_transport_deadline -- --nocapture
cargo test -p interop-core --test media_http video_transport_deadline -- --nocapture
```

## 持续新像素与重复连接

`tool/e2e/video_fixture` 是独立实验目标APK，不属于产品，不改变被控端无需安装额外App的规则。它用四块色彩编码4 bit计数器；真实DPAD_DOWN松开后Android绘制下一个计数。测试逐次识别期望计数，旧帧、空白纹理、仅控制写回执都不能通过。截图按Texture实际矩形映射采样，逐轮检查停止回执的textureDetached，拒绝disposeDeferred/cleanupUnconfirmed，不捏造公开API无法确认的nativeDeleteConfirmed。

r1/r2初始严格颜色不匹配，r3颜色比例可识别但首个操作无变化；独立目标最终截图确认Android首次沉浸教育提示延迟出现、压暗画面并截获按键。夹具取消沉浸请求后r4完整25秒通过：4轮连接/新会话/暂停恢复/停止、32次新计数及4张实际Flutter截图。输入到解码像素P50=448ms、最近秩P95=495ms、最大562ms；约0.45秒的持续交互仍是待优化瓶颈。取帧方式与readback开销计入，不解释成纯网络延迟。

`/tmp/connect-e2e/video-performance-r4/result.json`、`/tmp/connect-video-performance-r4.log`。r4发现host driver成功后SDK直接exit(0)，finally不执行；已由主代理实际卸载自己的夹具并写明人工补清理来源，不能称r4自动清理通过。驱动修正为responseDataCallback中先完成卸载/确认包不存在/返回Settings并写cleanup，再交给SDK退出，finally仅兜底普通异常。

最终r5完整66秒通过：6轮新连接/会话、120次精确新计数、6次暂停恢复、6张实际Flutter截图和6次确认纹理分离。输入到解码像素P50=446ms、最近秩P95=452ms、P99=569ms、最大571ms；启动到解码首像素1189/1119/1121/1028/1212/1244ms。主控每轮单调计时的媒体观测区间共50451ms、640包/535040容器字节，这是低复杂度色块负载，不是高运动带宽或满负荷帧率测试。`videoPerformanceComplete`和`fixtureCleanupConfirmed`均true，cleanup的uninstalled/absent均true。`/tmp/connect-video-performance-r5.log`、`/tmp/connect-e2e/video-performance-r5/`；不是小时级长稳，也不把主动重连误称自动故障恢复。

可重复运行（工作目录apps/connect，先从仓库根构建夹具）：

```sh
python3 tool/e2e/video_fixture/build.py
flutter pub get --offline
CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-performance \
flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/video_performance.dart \
  --target=integration_test/video_performance_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=25556 \
  --dart-define=CONNECT_PERF_ROUNDS=6 \
  --dart-define=CONNECT_PERF_TRANSITIONS=20
```

运行前目标须是专用可唤醒的调试设备，25556转发已建立；驱动拒绝替换已有同名夹具安装。生产构建后使用--no-pub运行集成测试前，须先在应用目录pub get准备测试插件注册，见[打包说明](android-packaging.md)。

## 未关闭的主任务

- 继续降低持续输入到新像素等待；当前Core启动核验约0.35–0.47秒，也需要单独优化，不能用绕过真实能力/解码验证来换数字。
- 真实网络故障重连/已授权TLS、Wi-Fi切换和半开ADB传输；本次主动disconnect/connect不等于网络故障自动恢复。
- 播放器已打开后的失败事件到正式会话失败/资源回收仍有待补齐；不能仅依赖HTTP relay结束。
- Profile/release、真实ARM硬解、不同ROM/分辨率/帧率、并发文件/声音/玻璃覆盖、输入P95/P99、持续高动态和小时级长稳、温度/功耗、共同音画时钟继续开放。

没有把“数据已收到”“编码首帧已就绪”“snapshot已读取”“实际屏幕已呈现”合并为同一个成功标记。

## 本批回归与构建边界

`1cc5774`提交Rust阻塞修复和捕获启动分段，`d41a26d`提交播放器探测限制、输出计时与真实图案基准。完整Core测试141 passed / 48 ignored，35 suites，忽略项不计实际设备验证；Bridge完整107项、应用远控/会话/后台相关43项通过。严格Flutter分析无问题，165输入的生成一致性通过，cargo fmt及Core全targets clippy -D warnings通过。日志分别为`/tmp/connect-video-core-regression.log`、`/tmp/connect-video-bridge-regression.log`、`/tmp/connect-video-app-regression.log`、`/tmp/connect-video-clippy.log`。

Core交叉check：aarch64-apple-ios 8.61秒、aarch64-apple-darwin 3.19秒、x86_64-pc-windows-msvc 6.59秒通过（包含共享构建目录锁等待），分别留存`/tmp/connect-video-check-<ios|macos|windows>.log`。Android当前源码已在实际x64 Flutter整包运行，不将这些交叉check当成Apple/Windows宿主Flutter链接和运行，也没有为本批重新生成可分发ARM release。

正式RemotePage五编码28秒通过，`/tmp/connect-e2e/video-product-five/`、`/tmp/connect-video-product-five.log`；H264实际全屏设置页及图案VIDEO4/VIDEO8代表图已目视。r5每张Flutter截图的计数由测试自动验证。宿主另独立检查r5六个精确会话JAR路径均已不存在，没有删除其它远端文件。

普通lib/main.dart实际构建27.4秒、安装584ms，CLI R热重启2250ms；`/tmp/connect-video-main.log`和`/tmp/connect-video-main-restarted.png`，设备列表空态已目视后detach。两条FRB旧isolate投递告警和启动SurfaceSyncGroup告警仍有，未将其写成启动性能达标。

所有编译/测试/drive/run进程结束后停止本批闲置Gradle daemon，实际清理391处debug/测试暂存/incremental目录及29个过期非视频测试可执行文件，释放11132MiB，余量73.2GiB，记录`/tmp/connect-video-cleanup.json`。保留当前视频反馈循环的测试可执行文件、Rust依赖、native hooks、release/Gradle缓存和必要临时原始证据，避免清理导致下一轮视频验证/打包全量重建。用户原先五项未跟踪测试/examples未修改，未push。
