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

以下为实施前记录；该观测已在后续批次实现，实际结果及仍未关闭的范围见文末。

只读核查发现，现有CCodec日志中H264/HEVC为input.delay=0、output.delay=8，AV1为4。这是Codec2参数上界，不是实测积压8帧，也不能直接换算为毫秒。[AOSP定义](https://android.googlesource.com/platform/frameworks/av/+/cdb38d6e4150efa3918d61c52daca8798b3c593e/media/codec2/core/include/C2Config.h)。Rust HTTP转发每个完整AU经mux后立即写chunk，Matroska每AU一个cluster、PTS减首PTS，没有定时攒包或固定偏移；这仍不能仅凭源码排除实际socket背压。现有SPS parser没有完整VUI重排序字段证据，不能宣称重排序深度为零。

下一项研究/实施任务是补`decoded→renderer→snapshot`真实分段，按generation和同一PTS关联，耗时必须使用统一主控单调时钟。MDK官方onFrame/onVideo位于交付renderer之前；本地固定SDK C头`mdk/c/Player.h`的mdkVideoCallback为同步int返回值和frame in/out指针，不能直接把它当可异步投递Dart的普通事件。fvp0.39.1本地`lib/src/callbacks.cpp::MdkSnapshot`收到frameTime却只把像素发给Dart。接入前需验证回调线程、所有权、清理时序和既有回调是否会被替换；优先评估Rust原生回调/有界指标的跨平台路径，不增加Android平台呈现代码、不做逐帧Dart数据搬运。[MDK回调说明](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#templateclass-frame-player-onframestdfunctionintframe-inttrack-cb)。本次只读结论，不冒记新增计时已实现或已测得MediaCodec内部延迟；`buffered()`也只代表未解码packet队列。


## 原生路径分段与持续交互优化（2026-10-18 后续批次）

`bf4262a`增加可选Rust原生观测，`c058957`补真实Flutter合成面的有界新像素检查。没有新增Android播放代码或重建JAR。正常播放默认关闭观测：不注册逐帧回调、不分配指标环、不逐帧进入Dart。观测开启时按generation/token隔离，原生`onVideo`同步返回并保留原frame，最多256条PTS/主控单调时钟；snapshot仅在回调内复制限定尺寸像素，借用指针不跨回调，关闭先撤销请求，迟到回调不能访问Dart已释放的buffer。MDK C前缀按固定0.39头校验，运行版本拒绝未知主次版本；Android诊断snapshot借用固定fvp的video-output导出，正常播放不依赖该诊断接口。

relay写前/写后、MDK onVideo及native snapshot共用Rust单调时钟，按同一归一化PTS连接。MDK秒值转换允许1.1微秒误差，不跨帧模糊匹配；每次操作立即保存关联，避免等长测结束才读取已淘汰环。该测量分清HTTP写耗时、交付renderer之前的等待和snapshot可读之前的等待，不能把它称为显示面板扫描完成时间。`buffered()`仍仅表示未解码packet。[MDK回调与播放语义](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。

固定双API36 x64 AVD、H264、maxSize640/maxFps30/2Mbps、音频关闭；每次真实按键驱动被控夹具计数变化并核对主控实际像素。下表除最后两行均开启同PTS观测、2轮共16次；冷操作保留，失败结果不删除。

| 改动 | P50 / P95（ms） | 结论 |
| --- | --- | --- |
| 原生基线 | 357 / 586 | relay写后到onVideo中位320ms，onVideo到snapshot约12ms |
| 仅AMediaCodec low_latency=1 | 355 / 581 | 无有效改善，未设默认 |
| 仅AMediaCodec surface=0 | 354 / 537 | 无有效改善，未设默认 |
| 指定c2.android.avc.decoder | 447 / 504 | 无有效改善，未设默认 |
| FFmpeg slice回退 | 194 / 450 | 有冷尾延迟，不能声称该次P95达标 |
| 仅repeat间隔33333微秒 | 318 / 405 | 有改善，仍未达门槛 |
| repeat33333加视频fps=-1 | 181 / 343 | 有效候选，仍有冷尾，扩大到80次复验 |
| 正常播放基线，4轮80次，观测关闭 | 359 / 452 | 200 / 300预算失败；四轮呈现、暂停恢复均通过 |
| 正常播放最终候选，4轮80次，观测关闭 | **186 / 241** | 相同200 / 300预算通过；四轮呈现、暂停恢复均通过 |

正常路径结果分别为`/tmp/connect-e2e/video-native-control-80-{baseline,fast}/result.json`，日志`/tmp/connect-video-native-control-80-{baseline,fast}.log`。最终最大样本352ms仍保留，P95通过不等于每次都小于300ms。基线总32秒、候选约15.5秒完成80个串行变化，因此不能直接将这两段的包量/时长视作相同输入负载带宽测试。

最终生产改动只有两处：Rust通过现有`video_codec_options=repeat-previous-frame-after:long=...`将静态重复间隔设为`ceil(1e6 / min(maxFps,30))`微秒，尊重1–29fps的低帧率选择；独立视频Player打开前设置MDK `fps=-1`，尽快呈现解码帧。该Player关闭音轨，独立音源播放器不变。[scrcpy v5.0.1 SurfaceEncoder默认值与自定义覆盖顺序](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)、[MDK setFrameRate](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setframeratefloat-value)。组合试验中relay写后到onVideo中位约130ms、onVideo到snapshot约12ms；不能把全部改善归因于某一个内部队列。

此处调整的是静态画面重复超时，从默认100ms缩短到约33.334ms。Android API契约是在没有新帧时重复一次，不代表固定每秒输出30帧；更早重复可能增加编解码工作，实际包量仍需测量。[MediaFormat契约](https://developer.android.com/reference/android/media/MediaFormat#KEY_REPEAT_PREVIOUS_FRAME_AFTER)。2秒静止观察基线6–15包/300–787字节，候选5–12包/280–988字节，不足以推断真实手机功耗或高动态带宽。首帧仍未改善：同4轮基线启动到可读像素997–1256ms，候选1172–1286ms；不能将持续交互收益写成冷首帧收益。

可复现正常路径门槛：沿用前述drive入口，追加以下定义，不启用TRACE_FRAMES。开启观测则追加`CONNECT_PERF_TRACE_FRAMES=true`，不要混合两种snapshot实现的统计作为同路径对照。

```sh
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=20 \
--dart-define=CONNECT_PERF_MAX_P50_MS=200 \
--dart-define=CONNECT_PERF_MAX_P95_MS=300 \
--dart-define=CONNECT_PERF_IDLE_MS=2000
```

一次早期80次尝试在40次后发现Flutter截图仍为VIDEO4、目标为VIDEO8，未算完整80次基线。固定SDK的integration_test Android截图先acquire ImageView再等待两帧，可能捕获上一幅合成；现在最多8次、1.5秒观察窗口重新获取，每次像素/耗时与原图全部保留，仍不匹配即失败。没有忽略陈旧画面或放宽交互门槛。最终两次80样本的四轮合成面均第一次即匹配；该重试只修测试取样，未宣称修复所有可能的产品停帧。

捕获的H264 CSD解析为Baseline、pic_order_cnt_type=2、num_reorder_frames=0/max_dec_frame_buffering=1；这是所测码流证据，不能从CCodec output.delay上界反推实际B帧数。指定c2.android.avc.decoder实测output.delay=3，AOSP软件libavc含额外显示延迟；默认AVD宿主另有CUVID初始化失败日志与软件解码路径。不同AVD版本/实现不能混为实体手机硬解，也不通过重写SPS或换JAR掩盖等待。[C2SoftAvcDec](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/android16-release/media/codec2/components/avc/C2SoftAvcDec.cpp#920)、[libavc显示延迟](https://android.googlesource.com/platform/external/libavc/+/refs/heads/android16-release/decoder/ih264d_defs.h#48)。

本批仍开放：默认1280/60/8Mbps与高动态图像吞吐、冷首帧、真实ARM硬解/功耗/热、小时级长稳、真实配对adbd切网及已有视频活动恢复、音画共同时间基、四宿主整包。TCP黑洞局部恢复证据沿用上一节，本批80次没有模拟Wi-Fi故障。


### 本批验证边界

Rust bridge17项（含9项原生观测）、真实HTTP媒体16项通过；原生snapshot回归覆盖原frame透传、行拷贝、PTS、容量/超时、关闭/迟到回调和generation隔离。relay关闭观测时不插入frameTrace空字段，开启时有界256条并核对真实mux PTS及写入时钟。最终生产改动后Core lib39 passed/2 ignored、两包all-target clippy -D warnings及cargo fmt通过，Bridge Flutter完整114项通过。严格分析发现有界截图循环缺花括号，修正后4.9秒无问题；165输入生成一致性通过，没有生成文件变化。没有将ignored或命令参数错误计作通过。

Core交叉check iOS/macOS/Windows通过；bridge Android arm64在明确NDK CC/AR后通过。直接在Linux检查其余三个bridge target仍受dart-sys所需宿主C工具链/SDK限制（Windows lib.exe及Apple SDK缺失），失败日志保留在`/tmp/connect-native-trace-check-<target>.log`，不能把Core通过写成四宿主Flutter/bridge整包通过。

最终正式RemotePage五编码约24秒通过，`/tmp/connect-e2e/video-native-final-product-five/result.json`各codec为rendered且mediaAcceptanceComplete=true；H264全屏Settings与浮动退出以及最终图案VIDEO0截图已目视。普通main构建11.6秒/安装588ms，DTD发现并连接本次CLI App，实际热重启1642ms，运行错误工具无错误；`/tmp/connect-native-main-restarted.png`设备列表空态已目视。保留启动跳帧/SurfaceSync及两条FRB旧isolate告警，不当作冷启动流畅证明。

宿主独立检查本批29个精确会话JAR路径均不存在，视频夹具APK已卸载；`/tmp/connect-native-final-remote-cleanup.json`。官方枚举JAR和协作暂停捕获JAR摘要仍分别为764eb6f7…和91606a60…，本批未修改、未重建，普通APK继续嵌入现有产物。


最终`a694b78`的arm64签名release构建63.53秒，同模式`--no-pub`复建22.59秒，两次APK摘要一致；该增量耗时高于前批4.09秒，未做额外归因或宣称打包进一步加速。当前产物`/tmp/connect-artifacts/connect-arm64-video-release.apk`，46,773,534字节、SHA-256 `c9cc21d19df2b5d5ca726ad5b182854bbb5721a10fa06de0981e171e6f5a285f`；原签名身份和包结构/16KB对齐检查通过。未在物理ARM运行。[打包记录](android-packaging.md)。

全部构建结束后停止本批闲置Gradle，删除明确debug模式中间产物/重复debug APK及一个被替代Core测试程序，共59处，实际释放1379.4MiB，空闲63.0GiB。保留release、native hooks、CMake、Gradle、当前视频测试及模式不明的Flutter hash缓存；`/tmp/connect-native-final-cleanup.json`。原有五项未跟踪文件未动、未stage，未push；任务07和完整产品目标保持开放。


## 冷启动身份校验与默认高清复验（2026-10-18 后续）

上一批640/30/2Mbps持续交互结果不覆盖默认画质。本批给真实图案入口增加可选maxSize/maxFps/bitRate，仍使用原来的默认值保留旧基准可复现；追加首帧与关键帧后工作量两个独立门槛，记录实际解码尺寸和各项预算判定，任一失败仍使整体回执失败。本次1秒完整首帧是工程排查门槛，未通过不能写成产品承诺或已验收。

本节冷启动指重新ADB连接后的新捕获/播放器，未重启AVD或清空系统缓存。默认1280/60fps/8Mbps、实际AMediaCodec、关闭诊断trace，三轮8次真实变化的基线完整跑完：实际尺寸均576×1280；首帧1210/1246/1254ms，P50/P95=185/371ms，统计未去掉冷操作。1秒首帧失败，P95也超过300ms，不能套用上一批640结果宣称高清延迟通过。`/tmp/connect-e2e/video-hd-cold-baseline-r2/result.json`和`/tmp/connect-video-hd-cold-baseline-r2.log`。

此前第一次高清尝试只完成一轮后因integration_test注册缺失失败，不是三轮基线：release准备流程过滤了开发插件，直接--no-pub切回drive沿用了该注册。应用目录执行`flutter pub get --offline`重新准备后复跑完成完整采样但性能门槛失败，不能把测试基础设施失败当成媒体性能红证据。

| 身份校验步骤（均为同配置三轮） | 首关键帧后剩余Core工作（ms） | 完整首帧（ms） |
| --- | --- | --- |
| 基线：关键帧后再读/proc并核验 | 95 / 97 / 93 | 1210 / 1246 / 1254 |
| 仅复用launcher的starttime，省重复读取 | 47 / 47 / 48 | 1235 / 1281 / 1205 |
| 再与首关键帧读取并行核验 | **0 / 1 / 0** | 1276 / 1196 / 1245 |

launcher已经为了断线解冻而读取子进程PID/starttime；现在通过有界PID:starttime回执交给Rust，严格拒绝缺失/多字段、非十进制、0/1 PID、0 starttime、溢出和非法UTF8。exec替换程序而保留进程身份，因此无需随后再次cat同一stat；后续每次signal仍检查starttime及完整JAR/SCID nice-name，不退化为数字PID。metadata已经证明app_process进入socket初始化后，才开始identity核验；与首关键帧预读用try_join本地并行，两者成功才发布listener，任一失败另一future被drop且外围取消守卫仍清理。START_APP仍先记录durable permit、提交再等待，不自动重放unknown。[execve属性](https://man7.org/linux/man-pages/man2/execve.2.html)、[/proc starttime字段](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)。

这消除了可复现的关键帧后等待，但**目前完整首帧没有得到改善证据**：不同轮次的枚举/首编码及播放器首次输出浮动掩盖了局部收益。不得将95→0ms直接从独立轮次的总耗时相减，或将source关键帧就绪称为主控画面可见。step1/并行结果分别在`/tmp/connect-e2e/video-hd-cold-{identity,parallel}/result.json`，失败日志保留。

真实Rust→adbd→现有JAR进程回归：step1为7.59秒、并行为4.17秒，错误starttime拒绝、STOP/CONT、连接EOF后暂停进程解冻并退出通过，最后通过独立连接精确删除自己的JAR。最初默认2MiB调试测试线程stack overflow，不是产品回归通过；以RUST_MIN_STACK=8388608重跑，日志`/tmp/connect-cold-identity-real-step1-r2.log`、`/tmp/connect-cold-identity-real-parallel.log`。解析边界单元通过。独立只读review未发现新增正确性问题。

只调整repeat超时约16.667ms的额外候选，在首轮1139ms首次可读后遇到session.pause控制超时，未完成三轮，更未过1秒门槛。已恢复约33.334ms超时，不纳入生产；`/tmp/connect-e2e/video-hd-cold-repeat60/result.json`。不能只挑其首帧数字而忽略暂停失败，也不能仅凭一次失败断言所有设备会有同一根因。后续需对高负载暂停的消费者背压/ACK链路建独立回归；本地先暂停是为解决MDK静止输入确认，不能未经验证简单颠倒顺序。继续保留现有JAR及暂停扩展。


最终保留33.334ms超时并扩大到默认高清4轮80次：P50=**201ms**、P95=**248ms**，门槛仍为200/300ms，没有将201向下取整或放宽门槛。完整首帧1185/1122/1141/1234ms，1秒门槛仍失败；关键帧后开销四轮均0ms，20ms门槛通过。`startupBudgetMet=false`、`postKeyFrameBudgetMet=true`、`inputLatencyBudgetMet=false`、整体`videoPerformanceComplete=false`。四轮实际AMediaCodec、576×1280新像素、Flutter呈现、暂停恢复、输出停止确认与纹理分离、夹具卸载都完成，nativeDeleteConfirmed仍false，不能称原生资源已全部确认删除。`/tmp/connect-e2e/video-hd-cold-final-80/result.json`、`/tmp/connect-video-hd-cold-final-80.log`。该图案负载不等于高动态吞吐或60fps稳定输出验证。

`67d6fb9`提交测量入口，`657990c`提交身份校验时序。复现默认高清严格门槛时，沿用图案drive及环境变量，将定义设为：

```sh
--dart-define=CONNECT_PERF_DECODER=native \
--dart-define=CONNECT_PERF_MAX_SIZE=1280 \
--dart-define=CONNECT_PERF_MAX_FPS=60 \
--dart-define=CONNECT_PERF_BIT_RATE=8000000 \
--dart-define=CONNECT_PERF_ROUNDS=4 \
--dart-define=CONNECT_PERF_TRANSITIONS=20 \
--dart-define=CONNECT_PERF_MAX_START_MS=1000 \
--dart-define=CONNECT_PERF_MAX_POST_KEYFRAME_MS=20 \
--dart-define=CONNECT_PERF_MAX_P50_MS=200 \
--dart-define=CONNECT_PERF_MAX_P95_MS=300 \
--dart-define=CONNECT_PERF_IDLE_MS=2000
```

在release和E2E之间切换后，应先在应用目录执行`flutter pub get --offline`（依赖尚未缓存时使用正常pub get），再执行--no-pub drive；不要手改生成的注册文件。此严格命令当前预期退出非零，不能把完成80次采样等同全指标通过。

后续研究/实施保持三项：记录首包到首次onVideo/renderer的冷阶段，区分AVD软件实现与实体ARM；为高负载暂停的HTTP消费者背压与控制ACK建真实故障回归；独立固定高动态图案、持续时长和码率测量吞吐/内存/热。并行JAR上传与枚举仅列为候选，必须先验证失败/取消后无晚到上传复活文件，不因预计节省几十毫秒跳过清理所有权。保持原有完整产品目标与任务07开放。


本批最终Rust Core lib40 passed/2 ignored（10.30秒）、Core/Bridge all-target clippy -D warnings（4.47秒）及cargo fmt通过；严格Flutter分析7.1秒无问题。ignored不计真实通过；上面的真实进程测试另行显式执行。Core iOS/macOS/Windows MSVC交叉check通过，日志`/tmp/connect-cold-check-{ios,macos,windows}.log`，不代表三宿主Flutter/bridge整包或运行。

正式RemotePage五编码24秒通过，`/tmp/connect-e2e/video-cold-product-five/result.json`各codec rendered且mediaAcceptanceComplete=true；H264全屏Settings/浮动退出、高清最终VIDEO0及普通main设备列表截图已目视。普通main构建12.4秒/安装552ms，DTD实际热重启2325ms、运行错误查询无错误，日志`/tmp/connect-cold-main.log`；仍有启动SurfaceSync/跳帧和两条旧isolate投递告警，不记启动流畅通过。热重启后已detach。

宿主独立核对本批17个精确会话JAR路径均不存在，目标夹具APK已卸载（`/tmp/connect-cold-remote-cleanup.json`）。两个原有scrcpy JAR的完整摘要仍与前文一致，未改、未重建。


当前签名ARM64产物59.50秒构建、同模式复建2.40秒且摘要一致；`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节、SHA-256 `9411b4f9ab12a20c75d18c4ad0942e93b2d8a0fa024c391a7af6ef5a672a66ae`，原签名身份与ZIP/manifest/ELF/16KB对齐检查通过。它包含`657990c`，未物理ARM上机；原c9cc21d1…产物已另存。详见[打包记录](android-packaging.md)。


最终另行显式执行既有真实应用窗口/剪贴板/关闭保留任务测试，4.37秒通过，`/tmp/connect-cold-app-window.log`；它覆盖新并行路径中的START_APP，但不是所有unknown故障/UI迁回验收。随后独立ps和目录检查未发现残留捕获进程或捕获JAR，`/tmp/connect-cold-final-target-inspection.json`。闲置Gradle已停止，清理59处明确debug/过期测试产物，实际释放1373.8MiB、剩余62.6GiB；保留release/native hooks/CMake/Gradle和当前视频测试，`/tmp/connect-cold-cleanup.json`。原先五项未跟踪文件仍未动、未stage、未push，完整目标继续active。


## 动态负载下的合作暂停与JAR重建（2026-10-18）

本批由上一批16.667ms repeat试验的暂停超时继续排查，生产repeat仍33.334ms。
给独立目标增加可选持续变色块，保留中心四位计数采样带；每次暂停后经真实输入
改变目标计数，恢复必须读到新像素。`CONNECT_PERF_PAUSE_CYCLES`默认1、可设1–50，
每次保存阶段/暂停/恢复/新像素耗时，已完成cycle也写宿主日志以保留原生崩溃前的进度。
夹具独立构建/安装/卸载，未加产品原生代码或改变被控免APK要求。

| 真实双API36 x64 AVD，H264 1280/60/8Mbps、AMediaCodec、trace关闭 | 结果 |
| --- | --- |
| 原捕获JAR、静态、2轮×10次暂停 | 20次新像素/呈现/清理通过；不能代表动态负载 |
| 原捕获JAR、动态 | 第5次暂停ACK超时；首次输入1640/1628ms |
| 原JAR加临时主控探针、动态 | 第6次暂停超时；Capture写约1.255ms后无ACK，未判定根因 |
| 仅修gate/consumeReset窗口 | 动态仍出现超时，不是完整修复 |
| 增加有界输出等待及pending退出后的第一次动态 | 主控MDK线程SIGABRT，无最终JSON，不能计通过 |
| 最终源码动态复跑＋相同APK直接复跑 | 各2轮×10次全部通过，共40次；暂停148–306ms，恢复调用至新像素410–869ms |

原JAR的确定性竞态：gate已打开，codec尚未注册时暂停入队，只能置reset；随后
consumeReset清除该位，编码器进入encode，队列中的请求无法返回gate。JVM按真实
调用顺序先红，`isResetRequested`同时检查pending队列后绿。
但实际动态仍超时，故没有止于第一个理论。超时瞬间raw输出最长写447µs、最后完成包距
超时约12ms，未发现该层背压。目标超时前约2秒的SIGQUIT栈：control-recv已读下一消息、
control-send等空队列、video在`dequeueOutputBuffer(-1)`。这支持排查依赖EOS的编码退出，
不能单凭栈断言Android永远丢EOS，或完全排除其他阶段背压。

第二个回归直接反射调用构建后的真实SurfaceEncoder.encode，codec stand-in不产EOS，
先确认正常静止输入继续等待，再在读中入队暂停；旧实现确定性失败。最终将dequeue
等待设为100000µs，完成当前完整packet及releaseOutputBuffer后检查pending请求，
允许进入原finally清理，再在gate发ACK；未提前确认，也未在普通播放中任意丢P帧。
恢复仍要求新session/config/关键帧和真实新像素。100ms只约束该次codec读等待，
不保证socket写、native stop/release或完整暂停在100ms内完成。

仅我们的捕获扩展JAR需要此次重建，SHA-256为
`b46cd074600c33802dc764df8a9e056271725cb9b51daf4a3494dfffadbbac89`；
官方v5.0.1 JAR保持`764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`。
协议128/序列/ACK语义未变。普通Flutter/Rust构建仍直接嵌入产物；不是每次打包重建Java。
独立只读review未发现packet边界、资源清理/ACK、display保留的新缺陷；指出100ms不约束
包写/native清理，以及JVM无EOS用例不覆盖正长度packet。真实压力覆盖实际packet与像素。

原始证据：`/tmp/connect-e2e/video-pause-stress-{baseline,motion,probe,fixed,stack,stack-r2,stack-r3,bounded,bounded-r2,bounded-r3}/`；
对应`/tmp/connect-video-pause-stress-<同后缀>.log`。`bounded`因崩溃没有result.json，
驱动finally仍卸载并确认夹具不存在。两个确定性红日志为
`/tmp/connect-capture-{race,eos}-red.log`，最终JVM绿为`/tmp/connect-capture-eos-green.log`；
目标栈`/tmp/connect-pause-stack-r3-0.txt`，MDK完整tombstone
`/tmp/connect-video-pause-native-tombstone.txt`。临时Rust状态探针、Dart延迟/诊断标记均移除。

**开放问题不被复跑通过覆盖**：第一次候选在主控`JNISurfaceTextu`线程SIGABRT，MDK栈
为0x17951d/0x919ec/0x1631b9（BuildId 901726b6b0358c34d504c453a084538af9c7ef27）。
同APK随后40次通过，但原生崩溃根因/复现率仍未定位，不能称整体稳定验收通过。
动态完整首帧2753–3091ms，8次输入新像素1049–1769ms，远超严格预算；本批功能压力
沿用start5000、P50/P953000ms，`videoPerformanceComplete=true`只对这些门槛成立。
没有放宽前一批严格1000/200/300ms验收或用四个输入计算可信性能分位数。
静止3秒期间实际63–74包、约1.17–1.38MB，不等于稳定60fps/8Mbps；目标自身gfx统计
332帧，中位25ms、P9557ms、7.83% jank，见`/tmp/connect-video-pause-stress-fixed-target-gfxinfo.log`。
夹具绘制/AVD负载与编码/传输/解码需继续分段，不能把所有动态延迟归咎网络。

复现：先构建独立夹具，设置既有drive要求的ADB/主控/目标/APK环境变量（见夹具README），
在apps/connect目录使用：

```sh
rtk proxy env CONNECT_E2E_VIDEO_MOTION=true \
 CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-pause-stress \
 flutter drive -d emulator-5554 --no-pub \
 --driver=test_driver/video_performance.dart \
 --target=integration_test/video_performance_test.dart \
 --dart-define=CONNECT_PERF_DECODER=native \
 --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
 --dart-define=CONNECT_E2E_PORT=25556 \
 --dart-define=CONNECT_PERF_MAX_SIZE=1280 \
 --dart-define=CONNECT_PERF_MAX_FPS=60 \
 --dart-define=CONNECT_PERF_BIT_RATE=8000000 \
 --dart-define=CONNECT_PERF_ROUNDS=2 \
 --dart-define=CONNECT_PERF_TRANSITIONS=2 \
 --dart-define=CONNECT_PERF_PAUSE_CYCLES=10 \
 --dart-define=CONNECT_PERF_IDLE_MS=3000
```

同一编译定义的重复测试可用`--use-application-binary=build/app/outputs/flutter-apk/app-debug.apk`
直接安装运行当前测试APK，免重编译；不要用于改变dart-define的实验。严格性能命令仍按上一节，
本批不关闭任务07或完整目标。下一批优先复现MDK动态原生崩溃，再分段动态积压/冷首帧。


本批实现分批提交：`5a6cfda`为真实压力夹具/恢复新像素与失败回执，`91ae381`为两处
合作暂停修复/JVM回归/可复现捕获JAR。最终JAR --check及JVM通过，
`/tmp/connect-pause-jar-check.log`；严格Flutter分析5.8秒无问题，
`/tmp/connect-pause-analyze.log`。正式RemotePage五编码24秒全部rendered且
mediaAcceptanceComplete=true，`/tmp/connect-e2e/video-pause-product-five/result.json`；
H264全屏Settings/浮动退出与动态最终VIDEO8实际截图已目视。真实应用窗口/剪贴板/
停止保留原任务4.25秒通过，`/tmp/connect-pause-app-window.log`，不外推所有任务迁回。


普通main实际构建10.0秒、安装567ms，DTD实际热重启2729ms、运行错误查询无错误；
`/tmp/connect-pause-main.log`、`/tmp/connect-pause-main-restarted.png`，设备列表已目视后detach。
仍保留启动SurfaceSync及两条旧isolate投递告警，不把它称为启动流畅通过。
ARM64签名release 62.74秒完成，签名/ZIP/manifest/ELF/16KB ZIP对齐通过；另直接检查
APK的libinterop_bridge.so确实嵌入当前b46cd074…完整JAR，x64 debug也单独核对。
当前`/tmp/connect-artifacts/connect-arm64-video-release.apk`为46,773,534字节，SHA-256
`5ea20787311dec169eaed3a911b3a1c88eb7139947ff83de6e2190217e1fc9cb`，未物理ARM运行。
旧9411b4…包保留为`connect-arm64-before-pause-gate-release.apk`。


同模式release热构建2.50秒、摘要一致。停止闲置Gradle，清理382处明确debug输出，
实际释放1488.5MiB、空闲62.5GiB，保留release/native hooks/Gradle/CMake和模式不明的
Flutter缓存。`/tmp/connect-pause-cleanup.json`及`/tmp/connect-pause-remote-cleanup.json`：
目标无捕获进程/JAR且夹具已卸载，自己的SIGQUIT/tombstone已复制留证后精确移除。
MDK x64崩溃二进制`/tmp/connect-pause-libmdk-x64.so`也留存，供后续符号/反汇编定位。
原五项用户未跟踪文件未修改、未stage，没有push，完整目标仍active。
