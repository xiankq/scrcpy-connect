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

- 继续降低平台AMediaCodec持续输入到新像素等待；冷连接Core启动核验仍约0.35秒，同连接暖校验已降至46–52ms，见后续连接级目录优化。不能用绕过真实能力/解码验证来换数字。
- 真实Wi-Fi切换、实际已配对Android adbd的网络故障恢复、视频活动恢复继续验证；后续真实TCP黑洞/Runtime TLS协议夹具已补，不能扩大为这些场景已通过。
- 播放器失败传播已由后续生命周期修复补齐，物理MediaCodec崩溃和原生资源释放仍需独立故障实测；不能仅依赖HTTP relay结束。
- Profile/release、真实ARM硬解、不同ROM/分辨率/帧率、并发文件/声音/玻璃覆盖、输入P95/P99、持续高动态和小时级长稳、温度/功耗、共同音画时钟继续开放。

没有把“数据已收到”“编码首帧已就绪”“snapshot已读取”“实际屏幕已呈现”合并为同一个成功标记。

## 持续交互分段与解码路径对照

同日继续使用相同双AVD、H264 640/30和独立计数图案。基准新增每次控制回执耗时、逐次snapshot耗时与MDK原生`decoder.video`事件。控制回执通常1–4ms、snapshot通常1–2ms，却能连续几十次读到旧计数；不能把约350–450ms稳定等待归因于readback本身。冷启动仍有个别较慢snapshot，全部保留在统计中。

先设置P95≤300ms，平台默认路径16次操作实际P50=397ms、P95=784ms失败，`/tmp/connect-video-latency-red.log`。按已公布假设单变量尝试，未满足门槛的设置均撤回：

| 对照（各16次，毫秒） | P50 | P95 | 结论 |
| --- | ---: | ---: | --- |
| `fps=-1`立即渲染 | 352 | 512 | 无稳定充分收益，撤回 |
| AMediaCodec `async=0` | 380.5 | 469 | 撤回 |
| AMediaCodec `image=1` | 401.5 | 546 | 撤回 |
| `avformat.avioflags=direct` | 362.5 | 615 | 撤回 |
| 仅使用默认FFmpeg | 240.5 | 421 | 用于定位，不替代平台默认硬解优先 |
| 仅使用FFmpeg且单线程/slice | 183.5 | 405 | 继续隔离线程策略，不全局固定单线程 |

对应结果目录为`/tmp/connect-e2e/video-latency-{asap,syncdecode,imagereader,direct,software-default,software}/`。这些实验不是把几个设置叠加后挑最快样本。`decoder.video`成功事件可以确认实际打开的后端；`mediaInfo.codec`和候选列表不能。`AMediaCodec`也不证明是物理硬件加速，本批未新增这种承诺。[MDK事件定义](https://github.com/wang-bin/mdk-sdk/wiki/Types#class-mediaevent)、[MDK公开参数](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)、[AMediaCodec参数](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)。

仅取消FFmpeg的跨帧线程、保留slice策略后，4轮80次实际新像素P50=151.5ms、P95=245ms；随后同样80次默认FFmpeg对照为244/254ms。最大值373/460ms，冷样本均未剔除；两组P95≤300ms其实都通过，不能把文件名`fallback-red`误写成失败。目录分别`video-latency-slice`、`video-latency-fallback-red`，每轮实际截图、暂停恢复、纹理分离及夹具自动卸载均通过。继续加入P50≤200ms门槛，以锁住持续等待而非仅比较一次冷峰。

FFmpeg默认允许跨帧线程，其额外等待与本次对照相符；选择`thread_type=slice`避免等待后续帧，仍允许有切片时的帧内并行，不强制所有设备单线程。产品仍保留各平台原先硬解优先，仅改变共享实时视频播放器中的FFmpeg回退参数；音频和文件播放器未改。高分辨率下的吞吐/功耗与各实际codec线程实现仍需继续测量。[FFmpeg线程选项](https://ffmpeg.org/ffmpeg-codecs.html#Codec-Options)。

基准现在支持`CONNECT_PERF_DECODER=platform|software|software-default`，默认platform；后两者要求收到实际FFmpeg打开事件，防止候选与实际后端混淆。相同fixture命令可重复对比，不必编辑生产优先列表。以上收益限于软件回退路径；平台AMediaCodec稳定等待仍约0.35–0.45秒，不能宣称主任务已解决。

加入P50门槛后实际复跑：`software-default`的2轮40次P50=243ms、P95=302ms失败；相同P50≤200/P95≤300要求下，`software`的4轮80次P50=149ms、P95=242ms通过，实际FFmpeg回执与自动卸载均通过。没有放宽预算、跳过冷操作或取消真实新计数判断。`/tmp/connect-video-latency-p50-{red,green}.log`与对应结果目录保留。复现时在前述drive命令后追加以下参数，只将decoder从software-default换成software：

```sh
--dart-define=CONNECT_PERF_DECODER=software \
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=20 \
--dart-define=CONNECT_PERF_MAX_P50_MS=200 \
--dart-define=CONNECT_PERF_MAX_P95_MS=300
```

## 已打开播放器的失败传播

真实回归接缝现在复用正式Bridge的`VideoOutputLifecycle`，经过PortableVideoOutputs和播放器事件流，不是孤立测试代次比较。红阶段确认已打开播放器报错、HTTP仍streaming时，正式`session.failed`为0；另确认迟到旧relay结果会误停已提交的新代，重复故障会多次stop。`/tmp/connect-video-lifecycle-red.log`保留这些失败。

正式事件和250ms媒体poll统一处理已提交输出的device/generation/relay/texture所有权：先同步认领并撤下对应输出，再并行请求远端stop和本地释放，避免等待远端回执期间重复结束，也不在旧清理完成后再查找并关闭新输出。候选尚未提交时的失败事件不能越权关闭旧输出；正式poll的真实恢复失败仍终止原活动，不把已经EOF的冻结旧纹理假称恢复成功或反复消费single-use入口。

新7条回归及既有Portable/Presentation共41条通过，`/tmp/connect-video-lifecycle-final-green.log`。覆盖已打开失败、候选失败、迟到旧代、迟到relay、偏好/暂停合并收据、重叠故障和旧stop/释放未完成时重新打开另一会话。测试中的播放器端口用于精确注入故障及控制回执时序；这不是已验证物理设备MediaCodec崩溃、网络切换自动恢复或原生delete完成。

最终源码正式RemotePage五编码28秒通过，结果`/tmp/connect-e2e/video-latency-product-five/result.json`，日志`/tmp/connect-video-latency-product-five.log`；H264全屏Settings和计数夹具VIDEO12代表截图已目视，其余图案计数逐轮自动检查。完整Bridge114项通过，`/tmp/connect-video-latency-bridge.log`。HEVC既有低清约束与真实网络自动恢复继续开放，没有把这些成功扩大成画质或全链路低延迟验收。

相关应用43项通过，`/tmp/connect-video-latency-app.log`。严格分析首次报新增生命周期模块/测试的5处括号风格问题，修正后4.9秒无问题。普通main构建15.7秒、安装574ms、CLI R热重启2557ms，设备列表截图已目视并detach；`/tmp/connect-video-latency-main.log`与`/tmp/connect-video-latency-main-restarted.png`。FRB旧isolate投递与SurfaceSyncGroup启动告警仍在，不记为启动性能达标。

`25c2ddc`提交失败生命周期修复，`d0215db`提交软件回退线程策略和测量门槛。JAR摘要再次一致，未构建服务端。清理406处过期debug/测试输出和Flutter中间缓存，实际释放3345MiB；筛选时也误删旧Dart AOT缓存，已明确修正记录并用当前代码补建arm64 release：78.42秒通过，同模式第二次4.64秒通过，APK摘要相同。最新签名产物`/tmp/connect-artifacts/connect-arm64-video-release.apk`，46,740,766字节，SHA-256 `506f80ff966bed5669640c66e397120a0a400b9a3271a5fa319b7f7ae657ffd9`；ZIP/manifest/ARM64 ELF/16KB ZIP对齐及签名由打包工具检查，不是物理ARM运行证据。[打包与缓存细节](android-packaging.md)。

闲置Gradle再次停止，保留有效Rust/native hooks/CMake/Gradle及重建后的release缓存、当前成品和临时原始证据，最终空闲73.8GiB。`/tmp/connect-video-latency-cleanup.json`记录误删和补建，未抹去过程。主控普通App保留运行，被控返回Settings；最终四个性能会话精确JAR路径由宿主另验均不存在。原有五项未跟踪文件未动，未push。

## 本批回归与构建边界

`1cc5774`提交Rust阻塞修复和捕获启动分段，`d41a26d`提交播放器探测限制、输出计时与真实图案基准。完整Core测试141 passed / 48 ignored，35 suites，忽略项不计实际设备验证；Bridge完整107项、应用远控/会话/后台相关43项通过。严格Flutter分析无问题，165输入的生成一致性通过，cargo fmt及Core全targets clippy -D warnings通过。日志分别为`/tmp/connect-video-core-regression.log`、`/tmp/connect-video-bridge-regression.log`、`/tmp/connect-video-app-regression.log`、`/tmp/connect-video-clippy.log`。

Core交叉check：aarch64-apple-ios 8.61秒、aarch64-apple-darwin 3.19秒、x86_64-pc-windows-msvc 6.59秒通过（包含共享构建目录锁等待），分别留存`/tmp/connect-video-check-<ios|macos|windows>.log`。Android当前源码已在实际x64 Flutter整包运行，不将这些交叉check当成Apple/Windows宿主Flutter链接和运行，也没有为本批重新生成可分发ARM release。

正式RemotePage五编码28秒通过，`/tmp/connect-e2e/video-product-five/`、`/tmp/connect-video-product-five.log`；H264实际全屏设置页及图案VIDEO4/VIDEO8代表图已目视。r5每张Flutter截图的计数由测试自动验证。宿主另独立检查r5六个精确会话JAR路径均已不存在，没有删除其它远端文件。

普通lib/main.dart实际构建27.4秒、安装584ms，CLI R热重启2250ms；`/tmp/connect-video-main.log`和`/tmp/connect-video-main-restarted.png`，设备列表空态已目视后detach。两条FRB旧isolate投递告警和启动SurfaceSyncGroup告警仍有，未将其写成启动性能达标。

所有编译/测试/drive/run进程结束后停止本批闲置Gradle daemon，实际清理391处debug/测试暂存/incremental目录及29个过期非视频测试可执行文件，释放11132MiB，余量73.2GiB，记录`/tmp/connect-video-cleanup.json`。保留当前视频反馈循环的测试可执行文件、Rust依赖、native hooks、release/Gradle缓存和必要临时原始证据，避免清理导致下一轮视频验证/打包全量重建。用户原先五项未跟踪测试/examples未修改，未push。

## 同一设备连接再次打开远控

后续同日测量发现，每次捕获都会独立推送官方JAR、运行`list_encoders`并清理，即使正在复用同一ADB传输。`EncoderCatalog`现在按实际`Client`连接身份共享一次成功枚举，不按设备ID、地址或banner复用。并发请求共享初始化；失败或取消可重试，连接关闭时拒绝结果，替换连接重新枚举；最多保留32个最近连接的目录，淘汰不关闭连接。缓存不落盘，不复用捕获进程或会话JAR，每次仍重新检查休眠状态、启动服务端并验证编码关键帧与实际解码像素。

窄回归在未复用实现上实际2失败/2通过，最终6项通过：顺序/clone、并发合并、换传输与关闭、失败/取消重试、探测中关闭、容量淘汰不误断线。`/tmp/connect-encoder-catalog-{red,green}.log`。独立只读review未发现可证正确性问题。

双AVD真实相同连接基准先以250ms暖校验门槛失败：第二次校验378ms、Core启动814ms。保持同门槛后4轮通过，首次冷校验361ms/Core805ms/启动到解码1197ms；后三轮校验52/47/46ms、Core431/450/440ms、启动到解码711/707/739ms。优化的是已连接设备的重复打开，首次冷启动没有改善。16次实际新计数P50/P95为348/557ms，不能把启动收益记为持续解码延迟改善。`/tmp/connect-video-warm-validation-{red,green}.log`，结果在`/tmp/connect-e2e/video-warm-validation-{red,green}/`。

随后默认断开/重连3轮15秒通过，校验346/357/360ms，Core741/808/808ms：新传输仍执行完整探测，未错误复用上一连接。逐轮新像素、暂停恢复、截图、纹理分离及夹具自动卸载均通过，`/tmp/connect-video-catalog-reconnect.log`、`/tmp/connect-e2e/video-catalog-reconnect/result.json`。

在前述图案命令后追加可重测同一连接暖启动；默认不复用连接：

```sh
--dart-define=CONNECT_PERF_KEEP_CONNECTION=true \
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=4 \
--dart-define=CONNECT_PERF_MAX_WARM_VALIDATION_MS=250
```

## TCP链路丢失且对端没有EOF

AOSP ADB默认启用1秒间隔、10次失败探测。本项目此前仅设置TCP_NODELAY，空闲网络黑洞不会自动变为closed，既有Runtime监控因此无法进入重连。现于Rust`connect_tcp`建立后、TLS包装前设置相同keepalive；Android/Linux另设11秒TCP_USER_TIMEOUT，覆盖有数据未获ACK而走TCP重传的情况。没有添加固定视频帧间隔期限，也没有修改USB、自定义字节transport或普通反向转发socket。[AOSP连接入口](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/socket_spec.cpp#238)、[Unix探测参数](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/sysdeps_unix.cpp#28)、[TCP_USER_TIMEOUT语义](https://kernel.googlesource.com/pub/scm/docs/man-pages/man-pages/+/refs/tags/man-pages-6.13/man/man7/tcp.7#1212)。

回归完成真实ADB握手后，在测试自己接受的TCP socket上安装RET0过滤器，保持该对象打开，丢包发生在TCP处理/ACK之前；不是仍代答ACK的用户态TCP代理，也不是关闭peer制造EOF。宿主SO_ATTACH_FILTER返回EPERM，user namespace也不可用；该次失败属于夹具权限失败，没有当成目标故障红证据。改在专用API36 x64 AVD中执行同一Rust测试二进制，以测试进程`su 0`安装过滤器；产品没有新增root要求，未改宿主或AVD全局防火墙。

真实Android红阶段两个丢包用例16秒后仍在线/OPEN等待，健康静止17秒通过；最终三项17秒全部通过：空闲丢包被识别、未ACK OPEN不依赖120秒操作期限而结束、健康静止仍在线并可主动关闭。`/tmp/connect-tcp-liveness-android-{red,green}.log`。默认宿主运行显式ignore两项需过滤器权限的用例，不能将ignored计为通过；Android实际命令使用`--include-ignored --test-threads=3 --nocapture`。

这些期限检测的是TCP链路/ACK丢失；仍正常ACK却不处理ADB的代理或daemon应用层挂起、真实Wi-Fi切换、ROM后台策略、视频活动自动恢复与物理双机长稳仍需独立验证。Apple/Windows只共享keepalive，尚未声称它们具有Android/Linux的未ACK数据11秒边界。

公开Runtime另使用真实TLS socket和ADB协议端夹具，手动端点、关闭伴随轮询，按公开事件验证offline→同ID connected、设备记录仍仅一个。作为对照临时仅保留原TCP_NODELAY策略构建测试二进制，构建后立即恢复最终源码并逐字节核对；原策略在25秒恢复期限失败，整项30.23秒。最终策略相同夹具20.84秒通过，包含显式disconnect后第二socket实际EOF、autoReconnect=false和额外5秒无第三次accept的断言。`/tmp/connect-tcp-runtime-android-{red,green}.log`。这是Android内核上真实TCP/TLS与正式Runtime恢复链路，协议端不是实际配对的Android adbd，未宣称实体无线配对/切网或已有视频活动恢复通过。

独立review补强了主动close的验收：原先只检查同步取消标志，现保留peer并要求2秒内真实读到EOF。最终Android三项重新通过，`/tmp/connect-tcp-liveness-android-verified.log`。跨包feature组合会改变测试可执行文件哈希，最终执行路径从本次Cargo JSON的`compiler-artifact.executable`读取，不能拿旧文件名代替当前产物。

交叉构建反馈循环（NDK路径按本机安装配置；两个同名测试分别属于两个包）：

```sh
CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang" \
CARGO_BUILD_JOBS=2 cargo test -p interop-adb -p interop-core \
  --test tcp_liveness --target x86_64-linux-android --no-run \
  --message-format=json > /tmp/connect-tcp-test-artifacts.jsonl
```

分别从JSON读取两个executable，推送专用AVD的`/data/local/tmp/`并chmod755。ADB测试以`adb shell su 0 <binary> --include-ignored --test-threads=3 --nocapture`运行；Core测试以`adb shell su 0 env TMPDIR=/data/local/tmp RUST_MIN_STACK=8388608 <binary> --ignored --nocapture`运行。执行结束删除自己推送的二进制；不在普通手机要求root或安装测试APK。

## 本批最终验证与交付

`9542e05`提交连接级目录复用；`25e9bac`提交TCP丢失识别及Runtime恢复回归。完整Core147 passed/49 ignored、37 suites，`/tmp/connect-catalog-core-regression.log`；ADB50 passed/13 ignored，`/tmp/connect-catalog-adb-regression.log`。新增目录6项包含在Core通过数内；有权限条件的Android故障结果由上面的独立显式运行证明，不把default ignored冒记为通过。最终补强的EOF断言在`connect-tcp-liveness-android-verified.log`实际通过。

两包all-target clippy -D warnings8.51秒、cargo fmt、严格Flutter分析4.7秒及165输入生成一致性通过，日志前缀`/tmp/connect-catalog-{clippy,analysis,generated}`。Core iOS/macOS/Windows MSVC交叉check4.08/4.07/4.02秒通过（`/tmp/connect-catalog-check-<ios|macos|windows>.log`），不是三宿主Flutter整包或运行证据。

最终Rust源码的正式RemotePage五编码24秒通过，`mediaAcceptanceComplete=true`，`/tmp/connect-video-catalog-product-five.log`及`/tmp/connect-e2e/video-catalog-product-five/result.json`；H264全屏Settings与悬浮退出截图已目视。普通`lib/main.dart`构建13.5秒/安装598ms、CLI R热重启1724ms，设备列表空态截图已目视后detach（`/tmp/connect-catalog-main.log`、`/tmp/connect-catalog-main-restarted.png`）。DTD发现的IDE实例没有活动App，实际热重启使用本次CLI连接；旧isolate投递和SurfaceSyncGroup启动告警保留，未宣称启动流畅已通过。

最终arm64签名release总65.03秒（Gradle63.9秒），同模式第二次4.09秒，APK摘要相同。当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,757,150字节、SHA-256 `f701f9690d5e00c4ee9ae23fcefb8c1e96e5c1f99a5a2540985d4309a3d759fb`，原签名身份保留；ZIP/manifest/arm64 ELF/16KB ZIP对齐/签名均由脚本复验。前一批视频APK归档为`connect-arm64-before-tcp-release.apk`，未冒称当前ARM包已物理上机。[打包记录](android-packaging.md)。

所有编译与测试结束、闲置Gradle停止后，按本次Core回归日志的准确可执行文件路径清理30个非视频测试程序及对应incremental、一个旧Android测试程序和debug APK，实际释放8259MiB，剩余65.0GiB。保留当前视频反馈循环、依赖、release/native hooks/CMake/Gradle及所有无法确认模式的Flutter缓存，未按app.dill盲删；`/tmp/connect-catalog-cleanup.json`。AVD内自己推送的三个TCP测试二进制已删除，视频夹具包不存在；临时图像和原始日志继续在/tmp，未进入Git。原有五项未跟踪文件修改时间仍在10月17日，未动、未stage，未push。

## 下一段定位：解码输出到呈现

只读核查发现，现有CCodec日志中H264/HEVC为input.delay=0、output.delay=8，AV1为4。这是Codec2参数上界，不是实测积压8帧，也不能直接换算为毫秒。[AOSP定义](https://android.googlesource.com/platform/frameworks/av/+/cdb38d6e4150efa3918d61c52daca8798b3c593e/media/codec2/core/include/C2Config.h)。Rust HTTP转发每个完整AU经mux后立即写chunk，Matroska每AU一个cluster、PTS减首PTS，没有定时攒包或固定偏移；这仍不能仅凭源码排除实际socket背压。现有SPS parser没有完整VUI重排序字段证据，不能宣称重排序深度为零。

下一项研究/实施任务是补`decoded→renderer→snapshot`真实分段，按generation和同一PTS关联，耗时必须使用统一主控单调时钟。MDK官方onFrame/onVideo位于交付renderer之前；本地固定SDK C头`mdk/c/Player.h`的mdkVideoCallback为同步int返回值和frame in/out指针，不能直接把它当可异步投递Dart的普通事件。fvp0.39.1本地`lib/src/callbacks.cpp::MdkSnapshot`收到frameTime却只把像素发给Dart。接入前需验证回调线程、所有权、清理时序和既有回调是否会被替换；优先评估Rust原生回调/有界指标的跨平台路径，不增加Android平台呈现代码、不做逐帧Dart数据搬运。[MDK回调说明](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#templateclass-frame-player-onframestdfunctionintframe-inttrack-cb)。本次只读结论，不冒记新增计时已实现或已测得MediaCodec内部延迟；`buffered()`也只代表未解码packet队列。
